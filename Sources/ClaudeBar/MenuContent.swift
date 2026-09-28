import AppKit
import ClaudeBarCore
import SwiftUI

struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.profiles.isEmpty {
            Text("No accounts saved yet")
        }

        ForEach(model.profiles) { profile in
            Button {
                model.switchTo(profile)
            } label: {
                Text(row(for: profile))
            }
        }

        if let email = model.unsavedLoginEmail {
            Divider()
            Text("Logged in as \(email) (not saved)")
        }

        Divider()

        if model.runningClaudeCount > 0 {
            Text("⚠︎ \(model.runningClaudeCount) claude session\(model.runningClaudeCount == 1 ? "" : "s") running")
            Text("   Running sessions keep the old account until restarted")
            Divider()
        }

        if model.unsavedLoginEmail != nil || model.profiles.isEmpty {
            Button("Save Current Login…") { model.saveCurrentLogin() }
                .disabled(!model.canAddProfile)
        }
        if model.canAddProfile {
            Button("How to Add Another Account…") { model.showAddAccountHelp() }
        }
        Button("Refresh") { model.refresh() }
            .keyboardShortcut("r")
        Button("Settings…") { model.openSettings() }
            .keyboardShortcut(",")

        Divider()

        Button("Quit ClaudeBar") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func row(for profile: Profile) -> String {
        let marker = profile.id == model.activeProfile?.id ? "✓ " : "    "
        var text = marker + profile.title
        if profile.label != nil { text += " — \(profile.email)" }
        if let plan = profile.planBadge { text += "  [\(plan)]" }
        return text
    }
}
