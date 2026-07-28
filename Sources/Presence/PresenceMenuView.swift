import AppKit
import SwiftUI

struct PresenceMenuView: View {
    @ObservedObject var controller: PresenceController

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            settings
            Divider()
            footer
        }
        .frame(width: 340)
        .onAppear {
            controller.recordInteraction()
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Presence")
                        .font(.title2.weight(.semibold))
                    Text("Smart display wake")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Presence detection", isOn: $controller.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(controller.status.color.opacity(0.14))
                    Image(systemName: controller.status.symbol)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(controller.status.color)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(controller.status.title)
                            .font(.headline)
                        if controller.isCameraActive {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                                .help("Camera active")
                        }
                    }
                    Text(controller.status.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))

            if case .permissionDenied = controller.status {
                Button("Open Camera Privacy Settings") {
                    controller.openCameraSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
    }

    private var settings: some View {
        VStack(spacing: 13) {
            settingRow("Camera", symbol: "video.fill") {
                Picker("Camera", selection: $controller.selectedCameraID) {
                    Text("Automatic").tag("")
                    ForEach(controller.cameras) { camera in
                        Text(camera.name).tag(camera.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 170, alignment: .trailing)
            }

            settingRow("Check after", symbol: "keyboard") {
                Picker("Inactivity timer", selection: $controller.inactivitySeconds) {
                    ForEach(controller.inactivityOptions, id: \.self) { seconds in
                        Text(controller.formattedTimer(seconds)).tag(seconds)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
            }

            settingRow("Absence grace", symbol: "hourglass") {
                Picker("Absence grace period", selection: $controller.absenceGraceSeconds) {
                    ForEach(controller.absenceOptions, id: \.self) { seconds in
                        Text(controller.formattedTimer(seconds)).tag(seconds)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
            }

            settingRow("Launch at login", symbol: "arrow.clockwise") {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { controller.launchesAtLogin },
                        set: { controller.setLaunchAtLogin($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if let message = controller.loginItemMessage {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings") {
                        controller.openLoginItemSettings()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
        .disabled(!controller.isEnabled)
        .padding(16)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.secondary)
                Text("Frames are processed on this Mac and never saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            HStack {
                Button(controller.isPaused ? "Resume" : "Pause") {
                    controller.recordInteraction()
                    controller.isPaused.toggle()
                }
                .disabled(!controller.isEnabled)

                Spacer()

                Button("Quit Presence") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
    }

    private func settingRow<Content: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .foregroundStyle(.primary)
            Spacer()
            content()
        }
    }
}
