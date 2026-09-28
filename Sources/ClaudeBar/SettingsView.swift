import ClaudeBarCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var labels: [UUID: String] = [:]

    var body: some View {
        Form {
            Section("Accounts") {
                if model.profiles.isEmpty {
                    Text("No accounts saved. Use “Save Current Login…” from the menu bar.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.profiles) { profile in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Name", text: binding(for: profile), prompt: Text(profile.email))
                                .onSubmit { model.rename(profile, to: labels[profile.id] ?? "") }
                            Text(details(for: profile))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if profile.id == model.activeProfile?.id {
                            Text("Active").font(.caption).foregroundStyle(.green)
                        }
                        Button("Remove", role: .destructive) { model.remove(profile) }
                    }
                }
            }

            Section("General") {
                Toggle("Toggle accounts with \(AppModel.hotKeyDescription)", isOn: $model.hotKeyEnabled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        LoginItem.setEnabled(enabled)
                        launchAtLogin = LoginItem.isEnabled
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            model.refresh()
            launchAtLogin = LoginItem.isEnabled
        }
    }

    private func binding(for profile: Profile) -> Binding<String> {
        Binding(
            get: { labels[profile.id] ?? profile.label ?? "" },
            set: { labels[profile.id] = $0 }
        )
    }

    private func details(for profile: Profile) -> String {
        [profile.email, profile.organizationName, profile.planBadge]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
