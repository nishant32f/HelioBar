import SwiftUI

@main
struct HelioBarApp: App {
    @State private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(
                store: model.store,
                onSettings: { openWindow(id: "settings"); activate() },
                onBreathe:  { openWindow(id: "breathing"); activate() })
                .task { model.start() }
        } label: {
            Text(barTitle).foregroundStyle(zoneColor)
        }
        .menuBarExtraStyle(.window)

        Window("HelioBar Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)

        Window("Breathe", id: "breathing") {
            BreathingView(store: model.store)
        }
        .windowResizability(.contentSize)
    }

    private func activate() { NSApplication.shared.activate(ignoringOtherApps: true) }

    private var barTitle: String {
        guard let hr = model.store.liveHR else { return "–" }
        switch model.store.hrTrend {
        case .rising:  return "\(hr) ↑"
        case .falling: return "\(hr) ↓"
        default:       return "\(hr)"
        }
    }

    private var zoneColor: Color {
        switch model.store.hrZone {
        case .elevated: return .orange
        case .high:     return .red
        default:        return .primary
        }
    }
}
