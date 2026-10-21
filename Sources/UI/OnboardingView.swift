import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel

    let onRequestAccess: () -> Void
    let onOpenSystemSettings: () -> Void
    let onRevealApp: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 66, height: 66)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text("Every Dock click. A new window.")
                        .font(.system(size: 24, weight: .semibold))
                    Text("Dock clicks and window switching, without the wait.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text("Click a running app’s Dock icon and it gets its **New Window** command. Hold **⇧ Shift** — or any other modifier — for the Dock’s normal behavior. Apps that aren’t running launch normally, which is already a new window.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                Text("⌥")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(width: 26, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                Text("Tab")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                Text("opens the Metal window switcher for the current Space — release Option to switch, Esc to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 11) {
                step(number: "1", title: "Grant Accessibility access",
                     detail: "Used only to read the Dock and trigger the target app’s own menu command.")
                step(number: "2", title: "Click any running Dock icon",
                     detail: "The click is swallowed, then the app opens a fresh window.")
                step(number: "3", title: "Hold Shift to use macOS normally",
                     detail: "All modified clicks pass through untouched.")
            }

            statusBox

            HStack(spacing: 10) {
                if !model.permissionGranted {
                    Button("Grant Accessibility Access", action: onRequestAccess)
                        .buttonStyle(.borderedProminent)
                    Button("Open Settings", action: onOpenSystemSettings)
                } else {
                    Label("Monitoring is ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                }

                Spacer()

                Button(model.permissionGranted ? "Done" : "Later", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }

            HStack {
                Button("Reveal app in Finder", action: onRevealApp)
                    .buttonStyle(.link)
                    .font(.caption)
                Spacer()
            }
        }
        .padding(28)
        .frame(width: 600, height: 590)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusBox: some View {
        HStack(spacing: 10) {
            Image(systemName: model.permissionGranted ? "checkmark.shield.fill" : "hand.raised.fill")
                .foregroundStyle(model.permissionGranted ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.permissionGranted ? "Accessibility granted" : "Accessibility permission is required")
                    .font(.callout.weight(.medium))
                Text(model.permissionGranted
                     ? "Dock clicks and the ⌥Tab window switcher are ready."
                     : "macOS will not let any app intercept Dock clicks or keyboard shortcuts without this permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill((model.permissionGranted ? Color.green : Color.orange).opacity(0.08))
        )
    }

    private func step(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text(number)
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.secondary.opacity(0.13)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
