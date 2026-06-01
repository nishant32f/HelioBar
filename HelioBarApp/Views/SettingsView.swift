import SwiftUI
import ServiceManagement
import HelioCore

struct SettingsView: View {
    let model: AppModel

    @State private var token = ""
    @State private var host = ""
    @State private var interval: Double
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var saved = false
    @State private var saveError: String?

    init(model: AppModel) {
        self.model = model
        _interval = State(initialValue: model.settings.refreshSeconds)
    }

    var body: some View {
        Form {
            Section("Zepp account") {
                TextField("apptoken", text: $token)
                TextField("API host (e.g. api-mifit-us2.zepp.com)", text: $host)
                Button("Save token") { saveToken() }
                if saved { Text("Saved ✓").foregroundStyle(.green).font(.caption) }
                if let saveError { Text(saveError).foregroundStyle(.red).font(.caption) }
            }
            Section("Cloud refresh") {
                Slider(value: $interval, in: 60...900, step: 60) {
                    Text("Every \(Int(interval/60)) min")
                }
                .onChange(of: interval) { _, new in
                    model.settings.refreshSeconds = new
                }
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunch(on) }
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            if let c = model.tokenStore.load() { token = c.appToken; host = c.host }
        }
        .onChange(of: token) { _, _ in saved = false }
        .onChange(of: host)  { _, _ in saved = false }
    }

    private func saveToken() {
        do {
            try model.tokenStore.save(ZeppCredentials(appToken: token, host: host))
            model.startCloudPolling()
            saved = true
            saveError = nil
        } catch {
            saved = false
            saveError = error.localizedDescription
        }
    }

    private func setLaunch(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { launchAtLogin = !on }   // revert on failure
    }
}
