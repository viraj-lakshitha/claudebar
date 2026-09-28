import AppKit
import ClaudeBarCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var activeProfile: Profile?
    /// Email of a live login that is not saved in ClaudeBar.
    @Published private(set) var unsavedLoginEmail: String?
    @Published private(set) var runningClaudeCount = 0
    @Published var hotKeyEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hotKeyEnabled, forKey: Self.hotKeyDefaultsKey)
            updateHotKey()
        }
    }

    static let hotKeyDefaultsKey = "hotKeyEnabled"
    static let hotKeyDescription = "⌃⌥⌘C"

    private var switcher: AccountSwitcher?
    private var hotKey: HotKey?
    private var timer: Timer?
    private var settingsWindow: NSWindow?

    var canAddProfile: Bool { profiles.count < (switcher?.maxProfiles ?? 2) }

    init() {
        UserDefaults.standard.register(defaults: [Self.hotKeyDefaultsKey: true])
        hotKeyEnabled = UserDefaults.standard.bool(forKey: Self.hotKeyDefaultsKey)

        do {
            switcher = try AccountSwitcher(
                live: ClaudeKeychain(),
                config: ClaudeConfigFile(),
                vault: KeychainProfileVault(),
                store: JSONProfileStore()
            )
        } catch {
            presentError(error)
        }

        refresh()
        updateHotKey()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
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

    func saveCurrentLogin() {
        guard let switcher else { return }
        do {
            guard let login = try switcher.currentLogin() else {
                throw ClaudeBarError.noLiveCredential
            }
            guard let label = prompt(
                title: "Save \(login.account.email)",
                message: "Optional name shown in the menu (e.g. Personal, Work).",
                defaultValue: switcher.profile(matching: login)?.label ?? ""
            ) else { return }
            try switcher.captureCurrent(label: label.isEmpty ? nil : label)
        } catch {
            presentError(error)
        }
        refresh()
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

    func showAddAccountHelp() {
        activate()
        let alert = NSAlert()
        alert.messageText = "Add another account"
        alert.informativeText = """
        1. Save the account you're logged in to now (Save current login…).
        2. In a terminal run `claude`, then `/logout`, then `/login` with the other account.
        3. Come back here and choose Save current login… again.

        After that, pick either account from this menu or press \(Self.hotKeyDescription) to toggle.
        """
        alert.runModal()
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
                Task { @MainActor in self?.toggle() }
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
