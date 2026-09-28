import AppKit
import ClaudeBarCore
import SwiftUI

/// The panel that opens from the menu bar icon.
struct PopoverView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if model.profiles.isEmpty {
                emptyState
            }

            ForEach(model.profiles) { profile in
                AccountCard(
                    profile: profile,
                    isActive: profile.id == model.activeProfile?.id,
                    usage: model.usage[profile.id],
                    onSwitch: { model.switchTo(profile) }
                )
            }

            if let email = model.unsavedLoginEmail {
                Banner(systemImage: "person.crop.circle.badge.exclamationmark", tint: .orange) {
                    Text("Logged in as **\(email)**, which isn't saved.")
                } action: {
                    Button("Save") { model.saveCurrentLogin() }
                        .disabled(!model.canAddProfile)
                }
            }

            if model.isWaitingForNewLogin {
                Banner(systemImage: "hourglass", tint: .accentColor) {
                    Text("Waiting for you to `/login` in Terminal…")
                } action: {
                    Button("Cancel") { model.cancelWaitingForNewLogin() }
                }
            }

            if model.runningClaudeCount > 0 {
                Banner(systemImage: "exclamationmark.triangle.fill", tint: .yellow) {
                    Text("\(model.runningClaudeCount) `claude` session\(model.runningClaudeCount == 1 ? "" : "s") running. Sessions keep their account until restarted.")
                }
            }

            Divider()
            footer
        }
        .padding(12)
        .frame(width: 340)
        .onAppear {
            model.refresh()
            model.refreshUsage()
        }
    }

    private var header: some View {
        HStack {
            Text("Claude Code Accounts").font(.headline)
            Spacer()
            Button {
                model.refresh()
                model.refreshUsage(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh accounts and usage")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No accounts saved yet").font(.subheadline.weight(.semibold))
            Text("Click **Add Account** to save the account you're logged in to and add another one.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                model.addAccount()
            } label: {
                Label("Add Account", systemImage: "plus.circle")
            }
            .disabled(!model.canAddProfile)
            .help(model.canAddProfile ? "Log in to another Claude account and save it" : "Account limit reached")

            Spacer()

            Button {
                model.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit ClaudeBar")
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Account card

struct AccountCard: View {
    let profile: Profile
    let isActive: Bool
    let usage: UsageState?
    let onSwitch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(profile.shortTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(isActive ? Color.accentColor : Color.secondary))

                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }

                Spacer(minLength: 4)

                if let plan = profile.planBadge {
                    Text(plan)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }

                if isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Button("Switch", action: onSwitch)
                        .controlSize(.small)
                }
            }

            UsageSection(usage: usage)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isActive ? Color.accentColor.opacity(0.35) : Color.clear)
        )
    }

    private var subtitle: String {
        var parts: [String] = []
        if profile.label != nil { parts.append(profile.email) }
        if let org = profile.organizationName, !org.isEmpty, !org.contains(profile.email) { parts.append(org) }
        return parts.isEmpty ? profile.email : parts.joined(separator: " · ")
    }
}

// MARK: - Usage

struct UsageSection: View {
    let usage: UsageState?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let windows = usage?.snapshot?.windows, !windows.isEmpty {
                ForEach(windows) { UsageBar(window: $0) }
            } else if usage?.isLoading == true {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading usage…").font(.caption).foregroundStyle(.secondary)
                }
            }

            if let status = statusText {
                status.font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: Text? {
        if let error = usage?.error {
            if let fetched = usage?.snapshot?.fetchedAt {
                return Text("As of \(fetched, style: .relative) ago · \(error)")
            }
            return Text(error)
        }
        if let fetched = usage?.snapshot?.fetchedAt {
            return Text("Updated \(fetched, style: .relative) ago")
        }
        if usage == nil {
            return Text("Usage not loaded yet")
        }
        return nil
    }
}

struct UsageBar: View {
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.title).font(.caption)
                Spacer()
                Text("\(Int(window.utilization.rounded()))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(color)
            }
            ProgressView(value: min(max(window.utilization, 0), 100), total: 100)
                .progressViewStyle(.linear)
                .tint(color)
            if let reset = window.resetsAt {
                Text(Self.resetText(reset))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var color: Color {
        switch window.utilization {
        case 90...: return .red
        case 70..<90: return .orange
        default: return .accentColor
        }
    }

    static func resetText(_ date: Date, now: Date = Date()) -> String {
        let remaining = date.timeIntervalSince(now)
        guard remaining > 0 else { return "Resetting now" }
        if remaining < 24 * 3600 {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .abbreviated
            formatter.maximumUnitCount = 2
            return "Resets in \(formatter.string(from: remaining) ?? "")"
        }
        return "Resets \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }
}

// MARK: - Banner

struct Banner<Content: View, Action: View>: View {
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: Content
    @ViewBuilder let action: Action

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(tint)
            content.font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            action.controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.1)))
    }
}

extension Banner where Action == EmptyView {
    init(systemImage: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
        self.action = EmptyView()
    }
}
