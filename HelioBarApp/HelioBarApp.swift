import AppKit
import SwiftUI
import HelioCore

@main
struct HelioBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { SettingsView() }
    }
}

/// AppKit-driven menu bar item. NSStatusItem survives sleep/wake reliably,
/// unlike SwiftUI's MenuBarExtra (which goes unresponsive after the Mac wakes).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var titleTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "HelioBarStatusItem"
        if let button = statusItem.button {
            button.title = "♥ –"
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(store: model.store,
                                      onSettings: { AppDelegate.openSettings() }))

        titleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateTitle() }
        }
        updateTitle()
    }

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        let store = model.store
        guard let hr = store.liveHR else {
            button.attributedTitle = NSAttributedString(string: "♥ –")
            return
        }
        let arrow: String
        switch store.hrTrend {
        case .rising:  arrow = " ↑"
        case .falling: arrow = " ↓"
        default:       arrow = ""
        }
        let color: NSColor
        switch store.hrZone {
        case .elevated: color = .systemOrange
        case .high:     color = .systemRed
        default:        color = .labelColor
        }
        button.attributedTitle = NSAttributedString(
            string: "♥ \(hr)\(arrow)",
            attributes: [
                .foregroundColor: color,
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            ])
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    static func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
