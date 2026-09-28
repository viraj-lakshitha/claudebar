import XCTest
@testable import ClaudeBarCore

// MARK: - Fakes

final class FakeLive: LiveCredentialStore {
    var blob: Data?
    var failWrites = false
    var writes: [Data] = []
    init(_ blob: Data?) { self.blob = blob }
    func read() throws -> Data? { blob }
    func write(_ blob: Data) throws {
        if failWrites { throw ClaudeBarError.keychain("fail") }
        writes.append(blob)
        self.blob = blob
    }
}

final class FakeConfig: OAuthAccountStore {
    var account: Data?
    var failWrites = false
    init(_ account: Data?) { self.account = account }
    func readOAuthAccount() throws -> Data? { account }
    func writeOAuthAccount(_ json: Data) throws {
        if failWrites { throw ClaudeBarError.commandFailed("disk full") }
        account = json
    }
}

final class FakeVault: ProfileVault {
    var items: [UUID: ProfileSecret] = [:]
    func load(_ id: UUID) throws -> ProfileSecret? { items[id] }
    func save(_ secret: ProfileSecret, for id: UUID) throws { items[id] = secret }
    func delete(_ id: UUID) throws { items[id] = nil }
}

final class FakeStore: ProfileStore {
    var profiles: [Profile] = []
    func load() throws -> [Profile] { profiles }
    func save(_ profiles: [Profile]) throws { self.profiles = profiles }
}

func accountJSON(_ uuid: String, _ email: String) -> Data {
    try! JSONSerialization.data(
        withJSONObject: ["accountUuid": uuid, "emailAddress": email, "organizationName": "Org \(uuid)"],
        options: [.sortedKeys]
    )
}

func credentialBlob(_ token: String, plan: String = "max") -> Data {
    Data(#"{"claudeAiOauth":{"accessToken":"\#(token)","refreshToken":"r-\#(token)","expiresAt":1767225600000,"subscriptionType":"\#(plan)"}}"#.utf8)
}

// MARK: - Tests

final class CredentialParserTests: XCTestCase {
    func testParsesPlanAndExpiry() {
        let info = CredentialInfo(blob: credentialBlob("a", plan: "pro"))
        XCTAssertEqual(info.plan, "pro")
        XCTAssertEqual(info.expiresAt, Date(timeIntervalSince1970: 1_767_225_600))
    }

    func testToleratesGarbage() {
        let info = CredentialInfo(blob: Data("not json".utf8))
        XCTAssertNil(info.plan)
        XCTAssertNil(info.expiresAt)
    }

    func testPlanBadge() {
        XCTAssertEqual(Profile(email: "a", plan: "max", accountUuid: "1").planBadge, "Max")
        XCTAssertNil(Profile(email: "a", accountUuid: "1").planBadge)
    }
}

final class ClaudeConfigFileTests: XCTestCase {
    var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(".claude.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testReplacesOnlyOAuthAccount() throws {
        let original: [String: Any] = [
            "numStartups": 42,
            "projects": ["/tmp/x": ["allowedTools": ["Bash"]]],
            "oauthAccount": ["accountUuid": "A", "emailAddress": "a@x.com"],
            "hasCompletedOnboarding": true,
        ]
        try JSONSerialization.data(withJSONObject: original).write(to: url)

        let file = ClaudeConfigFile(url: url)
        XCTAssertEqual(try OAuthAccountInfo(json: XCTUnwrap(file.readOAuthAccount())).accountUuid, "A")

        try file.writeOAuthAccount(accountJSON("B", "b@x.com"))

        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(root["numStartups"] as? Int, 42)
        XCTAssertEqual(root["hasCompletedOnboarding"] as? Bool, true)
        XCTAssertNotNil(root["projects"] as? [String: Any])
        XCTAssertEqual((root["oauthAccount"] as? [String: Any])?["emailAddress"] as? String, "b@x.com")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("claudebar.bak").path))
    }

    func testMissingFile() throws {
        let file = ClaudeConfigFile(url: url)
        XCTAssertNil(try file.readOAuthAccount())
        XCTAssertThrowsError(try file.writeOAuthAccount(accountJSON("B", "b")))
    }
}

final class AccountSwitcherTests: XCTestCase {
    var live: FakeLive!
    var config: FakeConfig!
    var vault: FakeVault!
    var store: FakeStore!

    override func setUp() {
        live = FakeLive(credentialBlob("a1"))
        config = FakeConfig(accountJSON("A", "a@x.com"))
        vault = FakeVault()
        store = FakeStore()
    }

    func makeSwitcher() throws -> AccountSwitcher {
        try AccountSwitcher(live: live, config: config, vault: vault, store: store)
    }

    /// Captures A, then simulates `/login` as B and captures B.
    func captureBoth(_ switcher: AccountSwitcher) throws -> (Profile, Profile) {
        let a = try switcher.captureCurrent(label: "Personal")
        live.blob = credentialBlob("b1", plan: "pro")
        config.account = accountJSON("B", "b@x.com")
        let b = try switcher.captureCurrent()
        return (a, b)
    }

    func testCaptureCreatesThenUpdates() throws {
        let switcher = try makeSwitcher()
        let first = try switcher.captureCurrent()
        live.blob = credentialBlob("a2")
        let second = try switcher.captureCurrent(label: "Home")
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(switcher.profiles.count, 1)
        XCTAssertEqual(second.title, "Home")
        XCTAssertEqual(vault.items[first.id]?.credentialBlob, credentialBlob("a2"))
        XCTAssertEqual(store.profiles.count, 1)
    }

    func testProfileLimit() throws {
        let switcher = try makeSwitcher()
        _ = try captureBoth(switcher)
        live.blob = credentialBlob("c1")
        config.account = accountJSON("C", "c@x.com")
        XCTAssertThrowsError(try switcher.captureCurrent()) {
            XCTAssertEqual($0 as? ClaudeBarError, .profileLimitReached(2))
        }
    }

    func testSwitchRecapturesOutgoingAccount() throws {
        let switcher = try makeSwitcher()
        let (a, b) = try captureBoth(switcher)

        // B's tokens get rotated by Claude Code while B is active.
        let rotated = credentialBlob("b2", plan: "pro")
        live.blob = rotated

        try switcher.switchTo(a.id)
        XCTAssertEqual(live.blob, credentialBlob("a1"))
        XCTAssertEqual(try OAuthAccountInfo(json: XCTUnwrap(config.account)).accountUuid, "A")
        XCTAssertEqual(vault.items[b.id]?.credentialBlob, rotated)

        try switcher.switchTo(b.id)
        XCTAssertEqual(live.blob, rotated)
        XCTAssertEqual(try OAuthAccountInfo(json: XCTUnwrap(config.account)).accountUuid, "B")
    }

    func testSwitchRollsBackKeychainWhenConfigWriteFails() throws {
        let switcher = try makeSwitcher()
        let (a, _) = try captureBoth(switcher)
        config.failWrites = true

        XCTAssertThrowsError(try switcher.switchTo(a.id))
        XCTAssertEqual(live.blob, credentialBlob("b1", plan: "pro"))
    }

    func testSwitchRefusesToDropUnsavedLogin() throws {
        let switcher = try makeSwitcher()
        let a = try switcher.captureCurrent()
        live.blob = credentialBlob("z1")
        config.account = accountJSON("Z", "z@x.com")

        XCTAssertThrowsError(try switcher.switchTo(a.id)) {
            XCTAssertEqual($0 as? ClaudeBarError, .unsavedCurrentLogin(email: "z@x.com"))
        }
        XCTAssertEqual(live.blob, credentialBlob("z1"))

        try switcher.switchTo(a.id, discardUnsaved: true)
        XCTAssertEqual(live.blob, credentialBlob("a1"))
    }

    func testSyncActiveOnlyWritesWhenChanged() throws {
        let switcher = try makeSwitcher()
        let a = try switcher.captureCurrent()
        let firstCapture = switcher.profiles[0].capturedAt

        XCTAssertEqual(try switcher.syncActive()?.id, a.id)
        XCTAssertEqual(switcher.profiles[0].capturedAt, firstCapture)

        live.blob = credentialBlob("a2")
        try switcher.syncActive()
        XCTAssertEqual(vault.items[a.id]?.credentialBlob, credentialBlob("a2"))
    }

    func testRemoveAndRename() throws {
        let switcher = try makeSwitcher()
        let (a, b) = try captureBoth(switcher)
        try switcher.rename(b.id, to: "  Work ")
        XCTAssertEqual(switcher.profiles.first { $0.id == b.id }?.title, "Work")
        try switcher.rename(b.id, to: "")
        XCTAssertEqual(switcher.profiles.first { $0.id == b.id }?.title, "b@x.com")

        try switcher.remove(a.id)
        XCTAssertNil(vault.items[a.id])
        XCTAssertEqual(store.profiles.map(\.id), [b.id])
    }
}

final class ParsingTests: XCTestCase {
    func testProcessDetection() {
        let ps = """
          101 /Users/v/.local/share/claude/versions/1.0.0/claude --resume
          102 node /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js
          103 /Applications/Claude.app/Contents/MacOS/Claude
          104 /Applications/ClaudeBar.app/Contents/MacOS/ClaudeBar
          105 /bin/zsh -l
          106 node /usr/local/bin/claude
        """
        XCTAssertEqual(ProcessDetector.parse(ps), [101, 102, 106])
    }

    func testKeychainAccountParsing() {
        let output = """
        keychain: "/Users/v/Library/Keychains/login.keychain-db"
        attributes:
            "acct"<blob>="viraj"
            "svce"<blob>="Claude Code-credentials"
        """
        XCTAssertEqual(ClaudeKeychain.parseAccount(output), "viraj")
        XCTAssertEqual(ClaudeKeychain.quote(#"a "b""#), #""a \"b\"""#)
    }
}
