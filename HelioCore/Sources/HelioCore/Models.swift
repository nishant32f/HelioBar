import Foundation

/// Heart-rate zone for menu bar tinting.
public enum HRZone: String, Sendable {
    case resting, elevated, high

    /// Zone by fraction of max HR: <60% resting, 60–80% elevated, ≥80% high.
    public static func zone(for bpm: Int, maxHR: Int) -> HRZone {
        let pct = Double(bpm) / Double(Swift.max(maxHR, 1))
        switch pct {
        case ..<0.60:      return .resting
        case 0.60..<0.80:  return .elevated
        default:           return .high
        }
    }
}

/// Heart-rate source freshness for honest UI rendering.
public enum SourceStatus: Equatable, Sendable {
    case idle               // never received data
    case live               // streaming
    case stale              // had data, now dropped
    case error(String)      // failure with message
}

public struct HeartRatePoint: Equatable, Sendable {
    public let bpm: Int
    public let timestamp: Date

    public init(bpm: Int, timestamp: Date) {
        self.bpm = bpm
        self.timestamp = timestamp
    }
}
