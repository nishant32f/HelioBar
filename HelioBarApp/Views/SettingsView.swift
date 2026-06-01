import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("age") private var age = 30
    @AppStorage("alertEnabled") private var alertEnabled = false
    @AppStorage("alertThreshold") private var alertThreshold = 100
    @AppStorage("alertDurationMin") private var alertDurationMin = 3
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        Form {
            Section("You") {
                Stepper("Age: \(age)", value: $age, in: 10...100)
                Text("Max HR ≈ \(220 - age) bpm · zones scale to this")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Elevated-HR alert") {
                Toggle("Notify when HR stays high", isOn: $alertEnabled)
                Stepper("Above \(alertThreshold) bpm", value: $alertThreshold, in: 80...200, step: 5)
                Stepper("For \(alertDurationMin) min", value: $alertDurationMin, in: 1...30)
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunch(on) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 330, height: 380)
    }

    private func setLaunch(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
        } catch { launchAtLogin = !on }
    }
}
