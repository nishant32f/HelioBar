import Foundation
import CoreBluetooth
import HelioCore

/// Connects to the strap's standard BLE Heart Rate broadcast and reports BPM.
/// Reports connection state so the UI can show live vs. reconnecting.
final class HeartRateMonitor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let onSample: @Sendable (HeartRateSample) -> Void
    private let onConnected: @Sendable (Bool) -> Void
    private let onUnavailable: @Sendable (String) -> Void
    private let onDeviceName: @Sendable (String?) -> Void
    private let onCapabilities: @Sendable ([DeviceCapability]) -> Void
    private let onBatteryLevel: @Sendable (Int) -> Void

    private let hrService = CBUUID(string: "180D")
    private let hrMeasurement = CBUUID(string: "2A37")
    private let batteryService = CBUUID(string: "180F")
    private let batteryLevel = CBUUID(string: "2A19")

    init(onSample: @escaping @Sendable (HeartRateSample) -> Void,
         onConnected: @escaping @Sendable (Bool) -> Void,
         onUnavailable: @escaping @Sendable (String) -> Void,
         onDeviceName: @escaping @Sendable (String?) -> Void,
         onCapabilities: @escaping @Sendable ([DeviceCapability]) -> Void,
         onBatteryLevel: @escaping @Sendable (Int) -> Void) {
        self.onSample = onSample
        self.onConnected = onConnected
        self.onUnavailable = onUnavailable
        self.onDeviceName = onDeviceName
        self.onCapabilities = onCapabilities
        self.onBatteryLevel = onBatteryLevel
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(withServices: [hrService])
        case .unauthorized:
            onUnavailable("Bluetooth permission denied")
        case .poweredOff:
            onUnavailable("Bluetooth is off")
        case .unsupported:
            onUnavailable("Bluetooth unavailable")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        self.peripheral = peripheral
        peripheral.delegate = self
        onDeviceName(peripheral.name)
        central.stopScan()
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onConnected(true)
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        onConnected(false)
        central.scanForPeripherals(withServices: [hrService])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        onConnected(false)
        central.scanForPeripherals(withServices: [hrService])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        publishCapabilities(for: peripheral)
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        publishCapabilities(for: peripheral)
        for char in service.characteristics ?? [] {
            if service.uuid == hrService && char.uuid == hrMeasurement {
                peripheral.setNotifyValue(true, for: char)
            }
            if service.uuid == batteryService && char.uuid == batteryLevel {
                peripheral.readValue(for: char)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value else { return }
        if characteristic.uuid == hrMeasurement,
           let sample = HeartRatePacket.parse(data) {
            onSample(sample)
        }
        if characteristic.uuid == batteryLevel,
           let level = data.first {
            onBatteryLevel(Int(level))
        }
    }

    private func publishCapabilities(for peripheral: CBPeripheral) {
        let capabilities = (peripheral.services ?? []).map { service in
            let characteristics = (service.characteristics ?? []).map { $0.uuid.uuidString }.sorted()
            return DeviceCapability(
                serviceUUID: service.uuid.uuidString,
                serviceName: Self.serviceName(for: service.uuid),
                characteristicUUIDs: characteristics,
                supportedMetrics: Self.metrics(for: service.uuid, characteristics: service.characteristics ?? [])
            )
        }
        onCapabilities(capabilities)
    }

    private static func metrics(for serviceUUID: CBUUID, characteristics: [CBCharacteristic]) -> [SupportedMetric] {
        var metrics: [SupportedMetric] = []
        if serviceUUID.uuidString == "180D" {
            metrics.append(.heartRate)
        }
        if serviceUUID.uuidString == "180F" {
            metrics.append(.battery)
        }
        if serviceUUID.uuidString == "180A" {
            metrics.append(.deviceInfo)
        }
        return metrics
    }

    private static func serviceName(for uuid: CBUUID) -> String {
        switch uuid.uuidString {
        case "180D": return "Heart Rate"
        case "180F": return "Battery"
        case "180A": return "Device Information"
        case "1800": return "Generic Access"
        case "1801": return "Generic Attribute"
        default: return uuid.uuidString
        }
    }
}
