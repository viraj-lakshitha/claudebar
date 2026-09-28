import SwiftUI

@main
struct ClaudeBarApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: model.activeProfile == nil ? "person.crop.circle.badge.questionmark" : "person.2.circle")
                if let active = model.activeProfile {
                    Text(active.shortTitle)
                }
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
