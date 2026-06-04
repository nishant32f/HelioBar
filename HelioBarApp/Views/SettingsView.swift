import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    var onRetryBluetooth: () -> Void = {}

    @AppStorage("age") private var age = 30
    @AppStorage("alertEnabled") private var alertEnabled = false
    @AppStorage("alertThreshold") private var alertThreshold = 100
    @AppStorage("alertDurationMin") private var alertDurationMin = 3
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .liquidGlassInset(cornerRadius: 8)
                Text("Settings")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
            }

            compactSection {
                settingStepper(
                    icon: "person.crop.circle",
                    title: "Age",
                    value: "\(age)",
                    rangeText: "Max HR ≈ \(220 - age) bpm",
                    valueBinding: $age,
                    bounds: 10...100
                )
            }

            compactSection {
                settingToggle(
                    icon: "bell.badge",
                    title: "Elevated alert",
                    subtitle: "Notify when HR stays high",
                    isOn: $alertEnabled
                )
                Divider().opacity(0.35)
                settingStepper(
                    icon: "gauge.with.dots.needle.67percent",
                    title: "Threshold",
                    value: "\(alertThreshold) bpm",
                    rangeText: nil,
                    valueBinding: $alertThreshold,
                    bounds: 80...200,
                    step: 5
                )
                settingStepper(
                    icon: "timer",
                    title: "Duration",
                    value: "\(alertDurationMin) min",
                    rangeText: nil,
                    valueBinding: $alertDurationMin,
                    bounds: 1...30
                )
            }

            compactSection {
                settingActionRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Bluetooth access",
                    subtitle: "Allow HelioBar in Privacy settings"
                ) {
                    Button(action: openBluetoothPrivacy) {
                        Image(systemName: "lock.open")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .help("Open Bluetooth Privacy")
                    .accessibilityLabel("Open Bluetooth Privacy")

                    Button(action: onRetryBluetooth) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .help("Retry Bluetooth")
                    .accessibilityLabel("Retry Bluetooth")
                }
            }

            compactSection {
                settingToggle(
                    icon: "power",
                    title: "Launch at login",
                    subtitle: nil,
                    isOn: $launchAtLogin
                )
                .onChange(of: launchAtLogin) { _, on in setLaunch(on) }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.leading, 34)
                }
            }
        }
        .padding(14)
        .frame(width: 318)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func compactSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func settingIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
    }

    private func settingToggle(
        icon: String,
        title: String,
        subtitle: String?,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 10) {
            settingIcon(icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    private func settingActionRow<Actions: View>(
        icon: String,
        title: String,
        subtitle: String?,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(spacing: 10) {
            settingIcon(icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                actions()
            }
        }
    }

    private func settingStepper(
        icon: String,
        title: String,
        value: String,
        rangeText: String?,
        valueBinding: Binding<Int>,
        bounds: ClosedRange<Int>,
        step: Int = 1
    ) -> some View {
        HStack(spacing: 10) {
            settingIcon(icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                if let rangeText {
                    Text(rangeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Stepper("", value: valueBinding, in: bounds, step: step)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    private func setLaunch(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        } catch {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            launchAtLoginError = error.localizedDescription
        }
    }

    private func openBluetoothPrivacy() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth",
            "x-apple.systempreferences:com.apple.BluetoothSettings",
            "x-apple.systempreferences:com.apple.preference.security",
        ]
        for rawURL in urls {
            guard let url = URL(string: rawURL) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }
}
