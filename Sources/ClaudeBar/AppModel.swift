import AppKit
import ClaudeBarCore
import SwiftUI

/// Usage limits shown for one account.
struct UsageState {
    var snapshot: UsageSnapshot?
    var error: String?
    var isLoading = false
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var activeProfile: Profile?
    /// Email of a live login that is not saved in ClaudeBar.
    @Published private(set) var unsavedLoginEmail: String?
    @Published private(set) var runningClaudeCount = 0
    @Published private(set) var usage: [UUID: UsageState] = [:]
    /// Set while the user is logging in to a new account in Terminal.
    @Published private(set) var isWaitingForNewLogin = false
    @Published var hotKeyEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hotKeyEnabled, forKey: Self.hotKeyDefaultsKey)
            updateHotKey()
        }
    }

    static let hotKeyDefaultsKey = "hotKeyEnabled"
    static let hotKeyDescription = "⌃⌥⌘C"
    static let usageCacheKey = "usageCache"
    static let maxProfiles = 5
    /// How often usage limits are re-fetched in the background.
    static let usageInterval: TimeInterval = 5 * 60

    private var switcher: AccountSwitcher?
    private var hotKey: HotKey?
    private var timer: Timer?
    private var settingsWindow: NSWindow?
    private var loginWatchTimer: Timer?
    private var loginWatchStarted: Date?
    private var lastUsageFetch: Date?
    private let usageClient = UsageClient()

    var canAddProfile: Bool { profiles.count < (switcher?.maxProfiles ?? Self.maxProfiles) }

    /// Text next to the menu bar icon, e.g. "Personal · 23%".
    var menuBarTitle: String {
        guard let active = activeProfile else {
            return unsavedLoginEmail.map { Self.shorten($0) } ?? "Claude"
        }
        var title = Self.shorten(active.title)
        if let session = usage[active.id]?.snapshot?.session {
            title += " · \(Int(session.utilization.rounded()))%"
        }
        return title
    }

    static func shorten(_ title: String, max: Int = 16) -> String {
        // Emails read better without the domain in the menu bar.
        let base = title.contains("@") && !title.contains(" ") ? String(title.split(separator: "@")[0]) : title
        return base.count > max ? String(base.prefix(max - 1)) + "…" : base
    }

    init() {
        UserDefaults.standard.register(defaults: [Self.hotKeyDefaultsKey: true])
        hotKeyEnabled = UserDefaults.standard.bool(forKey: Self.hotKeyDefaultsKey)

        do {
            switcher = try AccountSwitcher(
                live: ClaudeKeychain(),
                config: ClaudeConfigFile(),
                vault: KeychainProfileVault(),
                store: JSONProfileStore(),
                maxProfiles: Self.maxProfiles
            )
        } catch {
            presentError(error)
        }

        loadUsageCache()
        refresh()
        updateHotKey()
        refreshUsage(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refresh()
                self.refreshUsage()
            }
        }
    }

    // MARK: - State

    func refresh() {
        guard let switcher else { return }
        do {
            let login = try switcher.currentLogin()
            activeProfile = try switcher.syncActive()
            unsavedLoginEmail = (login != nil && activeProfile == nil) ? login?.account.email : nil
        } catch {
            activeProfile = nil
            unsavedLoginEmail = nil
        }
        profiles = switcher.profiles
        runningClaudeCount = ProcessDetector.runningClaudePIDs().count
    }

    // MARK: - Usage

    /// Fetches usage limits for every saved account. Without `force`, runs at
    /// most every `usageInterval`.
    func refreshUsage(force: Bool = false) {
        guard let switcher else { return }
        if !force, let last = lastUsageFetch, Date().timeIntervalSince(last) < Self.usageInterval { return }
        lastUsageFetch = Date()

        for profile in profiles {
            let credential = try? switcher.credential(for: profile.id)
            guard let credential, let token = credential.accessToken, !credential.isExpired() else {
                // Only the active account's token gets refreshed (by Claude Code).
                // Keep showing the last known numbers for the others.
                usage[profile.id, default: UsageState()].error = profile.id == activeProfile?.id
                    ? "Run `claude` to refresh the sign-in."
                    : "Updates when you switch to this account."
                continue
            }
            usage[profile.id, default: UsageState()].isLoading = true
            let id = profile.id
            Task {
                do {
                    let snapshot = try await usageClient.fetch(accessToken: token)
                    usage[id] = UsageState(snapshot: snapshot)
                    saveUsageCache()
                } catch {
                    usage[id, default: UsageState()].error = error.localizedDescription
                    usage[id, default: UsageState()].isLoading = false
                }
            }
        }
    }

    private func loadUsageCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.usageCacheKey),
              let cache = try? JSONDecoder().decode([UUID: UsageSnapshot].self, from: data) else { return }
        usage = cache.mapValues { UsageState(snapshot: $0) }
    }

    private func saveUsageCache() {
        let cache = usage.compactMapValues(\.snapshot)
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: Self.usageCacheKey)
        }
    }

    // MARK: - Actions

    func switchTo(_ profile: Profile) {
        guard let switcher, profile.id != activeProfile?.id else { return }
        refresh()

        if runningClaudeCount > 0 {
            let plural = runningClaudeCount == 1 ? "session is" : "sessions are"
            guard confirm(
                title: "\(runningClaudeCount) Claude Code \(plural) running",
                message: "Running sessions keep using \(activeProfile?.title ?? "the current account") until you restart them, and may overwrite the new login when they refresh their token. Quit them first if you can.",
                confirmTitle: "Switch Anyway"
            ) else { return }
        }

        do {
            try switcher.switchTo(profile.id)
        } catch ClaudeBarError.unsavedCurrentLogin(let email) {
            guard confirm(
                title: "\(email) is not saved",
                message: "Switching will log this account out of Claude Code. Save it first to switch back to it later.",
                confirmTitle: "Switch and Discard"
            ) else { return }
            do { try switcher.switchTo(profile.id, discardUnsaved: true) } catch { presentError(error) }
        } catch {
            presentError(error)
        }
        refresh()
        refreshUsage(force: true)
    }

    /// Switches to the other saved account (hotkey action).
    func toggle() {
        refresh()
        guard profiles.count >= 2 else {
            NSSound.beep()
            return
        }
        let currentIndex = profiles.firstIndex { $0.id == activeProfile?.id } ?? -1
        switchTo(profiles[(currentIndex + 1) % profiles.count])
    }

    /// Returns true if the login was saved.
    @discardableResult
    func saveCurrentLogin(title: String? = nil) -> Bool {
        guard let switcher else { return false }
        defer {
            refresh()
            refreshUsage(force: true)
        }
        do {
            guard let login = try switcher.currentLogin() else {
                throw ClaudeBarError.noLiveCredential
            }
            guard let label = prompt(
                title: title ?? "Save \(login.account.email)",
                message: "\(login.account.email)\n\nOptional name shown in ClaudeBar (e.g. Personal, Work).",
                defaultValue: switcher.profile(matching: login)?.label ?? ""
            ) else { return false }
            try switcher.captureCurrent(label: label.isEmpty ? nil : label)
            return true
        } catch {
            presentError(error)
            return false
        }
    }

    func rename(_ profile: Profile, to label: String) {
        do { try switcher?.rename(profile.id, to: label) } catch { presentError(error) }
        refresh()
    }

    func remove(_ profile: Profile) {
        guard confirm(
            title: "Remove \(profile.title)?",
            message: "ClaudeBar forgets this account's saved login. Claude Code itself is not logged out.",
            confirmTitle: "Remove"
        ) else { return }
        do { try switcher?.remove(profile.id) } catch { presentError(error) }
        refresh()
    }

    // MARK: - Add account

    /// Guided flow: keep the current login safe, open Terminal for `/login`,
    /// then offer to save the new login as soon as it appears.
    func addAccount() {
        refresh()
        guard canAddProfile else {
            presentError(ClaudeBarError.profileLimitReached(switcher?.maxProfiles ?? Self.maxProfiles))
            return
        }

        // Don't lose the login we're about to replace.
        if unsavedLoginEmail != nil {
            guard saveCurrentLogin(title: "First, save the account you're logged in to") else { return }
            guard canAddProfile else {
                presentError(ClaudeBarError.profileLimitReached(switcher?.maxProfiles ?? Self.maxProfiles))
                return
            }
        }

        activate()
        let alert = NSAlert()
        alert.messageText = "Log in to the new account"
        alert.informativeText = """
        ClaudeBar will open Terminal and start `claude`.

        1. Type /login and sign in with the other account in your browser.
        2. When it says you're logged in, come back here. ClaudeBar spots the new login and asks you to name it.

        Your saved accounts stay available. You can switch back any time.
        """
        alert.addButton(withTitle: "Open Terminal")
        alert.addButton(withTitle: "I'll Do It Myself")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openTerminalWithClaude()
        case .alertSecondButtonReturn:
            break
        default:
            return
        }
        startWatchingForNewLogin()
    }

    func cancelWaitingForNewLogin() {
        loginWatchTimer?.invalidate()
        loginWatchTimer = nil
        loginWatchStarted = nil
        isWaitingForNewLogin = false
    }

    private func startWatchingForNewLogin() {
        cancelWaitingForNewLogin()
        isWaitingForNewLogin = true
        loginWatchStarted = Date()
        loginWatchTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.checkForNewLogin() }
        }
    }

    private func checkForNewLogin() {
        if let started = loginWatchStarted, Date().timeIntervalSince(started) > 15 * 60 {
            cancelWaitingForNewLogin()
            return
        }
        refresh()
        guard unsavedLoginEmail != nil else { return }
        cancelWaitingForNewLogin()
        saveCurrentLogin(title: "New login detected")
    }

    /// Opens Terminal running `claude` via a `.command` file, which needs no
    /// Automation permission.
    private func openTerminalWithClaude() {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeBar-login.command")
        let contents = """
        #!/bin/zsh -il
        echo "ClaudeBar: type /login and sign in with the account you want to add."
        echo
        claude || echo "Could not start claude. Is Claude Code installed and on your PATH?"
        """
        do {
            try contents.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            presentError(error)
        }
    }

    /// A plain window instead of a `Settings` scene: opening that scene from a
    /// menu bar agent app is unreliable across macOS 13 and 14+.
    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: self)))
            window.title = "ClaudeBar Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Hotkey

    private func updateHotKey() {
        if hotKeyEnabled, hotKey == nil {
            hotKey = HotKey(keyCode: HotKey.keyC, modifiers: HotKey.controlOptionCommand) { [weak self] in
                guard let self else { return }
                Task { @MainActor in self.toggle() }
            }
        } else if !hotKeyEnabled {
            hotKey = nil
        }
    }

    // MARK: - Dialogs

    private func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }

    private func confirm(title: String, message: String, confirmTitle: String) -> Bool {
        activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func prompt(title: String, message: String, defaultValue: String) -> String? {
        activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = defaultValue
        field.placeholderString = "Personal"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func presentError(_ error: Error) {
        activate()
        let alert = NSAlert()
        alert.messageText = "ClaudeBar"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.runModal()
    }
}
