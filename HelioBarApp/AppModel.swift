import Foundation
import UserNotifications
import HelioCore

/// Owns the BLE monitor, applies user prefs, and fires elevated-HR alerts.
@MainActor
@Observable
final class AppModel {
    let store = HealthStore()
    private var monitor: HeartRateMonitor?
    private let alertEngine = ElevatedHRAlertEngine()
    private var started = false
    private var requestedNotificationPermission = false

    func start() {
        guard !started else { return }
        started = true
        if !requestedNotificationPermission {
            requestedNotificationPermission = true
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        startBluetoothMonitor()
    }

    func retryBluetooth() {
        monitor = nil
        store.hrStatus = .idle
        startBluetoothMonitor()
    }

    private func startBluetoothMonitor() {
        monitor = HeartRateMonitor(
            onSample: { [weak self] sample in
                Task { @MainActor in self?.handle(sample: sample) }
            },
            onConnected: { [weak self] connected in
                Task { @MainActor in if !connected { self?.store.hrDisconnected() } }
            },
            onUnavailable: { [weak self] message in
                Task { @MainActor in self?.store.hrFailed(message) }
            },
            onDeviceName: { [weak self] name in
                Task { @MainActor in self?.store.updateDevice(name: name) }
            },
            onCapabilities: { [weak self] capabilities in
                Task { @MainActor in self?.store.updateCapabilities(capabilities) }
            },
            onBatteryLevel: { [weak self] level in
                Task { @MainActor in self?.store.updateBatteryLevel(level) }
            })
    }

    private func handle(sample: HeartRateSample) {
        applyPrefs()
        store.updateHR(sample.bpm)
        if !sample.rrIntervals.isEmpty {
            store.markRRIntervalsAvailable()
        }
        if alertEngine.evaluate(bpm: sample.bpm, now: Date()) { fireAlert(sample.bpm) }
    }

    private func applyPrefs() {
        let d = UserDefaults.standard
        let age = (d.object(forKey: "age") as? Int) ?? 30
        store.maxHR = Swift.max(120, 220 - age)
        alertEngine.config = ElevatedHRConfig(
            enabled: d.bool(forKey: "alertEnabled"),
            threshold: (d.object(forKey: "alertThreshold") as? Int) ?? 100,
            duration: TimeInterval(((d.object(forKey: "alertDurationMin") as? Int) ?? 3) * 60))
    }

    private func fireAlert(_ bpm: Int) {
        let c = UNMutableNotificationContent()
        c.title = "Heart rate elevated"
        c.body = "\(bpm) bpm for a while — take a breath."
        c.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}
