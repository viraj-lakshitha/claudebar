import SwiftUI

@main
struct ClaudeBarApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.activeProfile == nil ? "person.crop.circle.badge.questionmark" : "person.crop.circle.fill")
                Text(model.menuBarTitle)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
