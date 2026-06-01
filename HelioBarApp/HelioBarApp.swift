import SwiftUI

@main
struct HelioBarApp: App {
    @State private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: model.store) {
                openWindow(id: "settings")
            }
            .task { model.start() }
        } label: {
            Label(barTitle, systemImage: "heart.fill")
        }
        .menuBarExtraStyle(.window)

        Window("HelioBar Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }

    private var barTitle: String {
        model.store.liveHR.map { "\($0)" } ?? "–"
    }
}
