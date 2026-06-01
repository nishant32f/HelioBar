import Foundation

/// Heart-rate zone for menu bar tinting.
public enum HRZone: String, Sendable {
    case resting, elevated, high

    public static func zone(for bpm: Int) -> HRZone {
        switch bpm {
        case ..<90:      return .resting
        case 90..<130:   return .elevated
        default:         return .high
        }
    }
}

/// Per-source freshness for the UI to render honestly.
public enum SourceStatus: Equatable, Sendable {
    case idle               // never received data
    case live               // streaming / fresh
    case stale              // had data, now dropped/old
    case error(String)      // failure with message
}

public struct StressReading: Equatable, Sendable {
    public let value: Int       // 0-100
    public let label: String    // e.g. "Relaxed"
    public init(value: Int, label: String) {
        self.value = value
        self.label = label
    }
}

public struct ReadinessReading: Equatable, Sendable {
    public let value: Int       // 0-100
    public init(value: Int) { self.value = value }
}
