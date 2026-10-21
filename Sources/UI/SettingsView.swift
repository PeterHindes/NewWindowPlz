import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    let onRequestAccess: () -> Void
    let onOpenSystemSettings: () -> Void
    let onTestOverlay: () -> Void
    let onTestSwitcher: () -> Void
    let onRequestScreenCapture: () -> Void
    let onOpenScreenRecordingSettings: () -> Void
    let onCopyDiagnostics: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                SettingsCard(title: "Dock clicks", systemImage: "dock.rectangle") {
                    Toggle(isOn: $settings.monitoringEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open a new window on every Dock click")
                            Text("Hold ⇧ Shift, ⌘, ⌥, or ⌃ for the Dock’s normal behavior.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    Divider()

                    HStack(spacing: 9) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.callout)
                        Spacer()
                        if !model.permissionGranted {
                            Button("Grant Access", action: onRequestAccess)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        } else {
                            Button("Accessibility Settings", action: onOpenSystemSettings)
                                .buttonStyle(.link)
                        }
                    }

                    if let failure = model.lastFailure {
                        Text(failure)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SettingsCard(title: "Window switcher", systemImage: "rectangle.on.rectangle") {
                    Toggle(isOn: $settings.altTabEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable ⌥Tab window switcher")
                            Text("Hold Option and press Tab. Shift-Tab goes back; release Option to switch. Only current-Space windows are shown.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    HStack(spacing: 9) {
                        Circle()
                            .fill(switcherColor)
                            .frame(width: 8, height: 8)
                        Text(switcherStatusText)
                            .font(.callout)
                        Spacer()
                        Button("Preview", action: onTestSwitcher)
                            .disabled(!isOverlayReady)
                            .controlSize(.small)
                    }

                    Text("Shows each on-screen window in the current Space, including multiple windows from the same app. Tab updates only the selection index and submits a new prewarmed frame.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    Toggle(isOn: Binding(
                        get: { settings.showWindowSnapshots },
                        set: { newValue in
                            settings.showWindowSnapshots = newValue
                            if newValue && !model.screenCaptureGranted {
                                onRequestScreenCapture()
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show window snapshots")
                            Text("Captured asynchronously after the switcher opens. Requires Screen Recording permission; relaunch if snapshots stay blank after granting.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    HStack(spacing: 9) {
                        Circle()
                            .fill(model.screenCaptureGranted ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(model.screenCaptureGranted
                             ? "Screen Recording granted"
                             : "Screen Recording required for snapshots")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !model.screenCaptureGranted {
                            Button("Open Settings", action: onOpenScreenRecordingSettings)
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                    }
                }

                SettingsCard(title: "Metal overlay engine", systemImage: "waveform.path.ecg.rectangle") {
                    HStack(spacing: 9) {
                        Circle()
                            .fill(overlayColor)
                            .frame(width: 8, height: 8)
                        Text(model.overlayReadiness.label)
                            .font(.callout)
                        Spacer()
                        Button("Test Overlay", action: onTestOverlay)
                            .disabled(!isOverlayReady)
                    }

                    Text(model.overlayRendererDescription)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    if let openMicros = model.overlayOpenMicroseconds {
                        HStack(spacing: 16) {
                            metric("OPEN", value: String(format: "%.2f ms", openMicros / 1_000))
                            if let switcherMicros = model.switcherOpenMicroseconds {
                                metric("SWITCH PREP", value: String(format: "%.2f ms", switcherMicros / 1_000))
                            } else if let firstFrame = model.overlayFirstFrameMicroseconds {
                                metric("FRAME SUBMIT", value: String(format: "%.2f ms", firstFrame / 1_000))
                            }
                        }
                    }

                    Text("Prewarmed borderless NSPanel + CAMetalLayer, native display-link pacing, and no window or drawable allocation when either overlay opens. The same surface hosts the app switcher and the renderer test.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsCard(title: "General", systemImage: "gearshape") {
                    Toggle(isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open at login")
                            Text(LoginItemManager.statusDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    if let loginError = model.loginItemError {
                        Text(loginError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SettingsCard(title: "Diagnostics", systemImage: "stethoscope") {
                    HStack {
                        Text("Dock app tiles cached")
                        Spacer()
                        Text("\(model.cachedDockTileCount)").monospacedDigit()
                    }
                    .font(.callout)

                    HStack {
                        Text("Event tap")
                        Spacer()
                        Text(model.eventTapDescription)
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)

                    Text(model.lastAction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Spacer()
                        Button("Copy Diagnostics", action: onCopyDiagnostics)
                            .controlSize(.small)
                    }
                }

                HStack {
                    Text("New Window Plz 1.2.2")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("Accessibility · optional Screen Recording for snapshots · no network")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(20)
        }
        .frame(width: 580, height: 670)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.rectangle.on.rectangle")
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("New Window Plz").font(.title2.weight(.semibold))
                Text("Dock clicks and app switching.").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusText: String {
        if !model.permissionGranted {
            return "Waiting for Accessibility permission"
        }
        if !settings.monitoringEnabled {
            return "Paused"
        }
        return model.monitoringActive ? "Monitoring running app tiles" : "Starting event tap…"
    }

    private var statusColor: Color {
        if !model.permissionGranted { return .orange }
        if !settings.monitoringEnabled { return .secondary }
        return model.monitoringActive ? .green : .orange
    }

    private var switcherStatusText: String {
        guard model.permissionGranted else { return "Waiting for Accessibility permission" }
        guard settings.altTabEnabled else { return "Paused" }
        if model.altTabActive {
            return model.altTabWindowCount > 0
                ? "Ready · \(model.altTabWindowCount) windows on this Space"
                : "Ready"
        }
        return "Starting ⌥Tab listener…"
    }

    private var switcherColor: Color {
        guard model.permissionGranted else { return .orange }
        guard settings.altTabEnabled else { return .secondary }
        return model.altTabActive ? .green : .orange
    }

    private var overlayColor: Color {
        if case .ready = model.overlayReadiness { return .green }
        if case .unavailable = model.overlayReadiness { return .red }
        return .orange
    }

    private var isOverlayReady: Bool {
        if case .ready = model.overlayReadiness { return true }
        return false
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(.callout, design: .monospaced).weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}
