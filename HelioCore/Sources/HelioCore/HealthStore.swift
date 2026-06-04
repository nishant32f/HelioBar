import Foundation
import Observation

/// Single source of truth the UI binds to. Fed by the BLE heart-rate monitor.
@MainActor
@Observable
public final class HealthStore {
    public static let recentWindow: TimeInterval = 5 * 60

    public var liveHR: Int?
    public var hrStatus: SourceStatus = .idle
    public var maxHR: Int = 190

    // Session analytics
    public private(set) var recent: [Int] = []          // recent values for trend and tests
    public private(set) var recentPoints: [HeartRatePoint] = []
    public private(set) var sessionMin: Int?
    public private(set) var sessionMax: Int?
    public private(set) var zoneCounts: [HRZone: Int] = [:]
    private var sessionSum = 0
    private var sessionCount = 0
    private let recentCap = 1_200

    public init() {}

    public func updateHR(_ bpm: Int, at timestamp: Date = Date()) {
        liveHR = bpm
        hrStatus = .live
        recent.append(bpm)
        recentPoints.append(HeartRatePoint(bpm: bpm, timestamp: timestamp))
        pruneRecentSamples(now: timestamp)
        sessionMin = Swift.min(sessionMin ?? bpm, bpm)
        sessionMax = Swift.max(sessionMax ?? bpm, bpm)
        sessionSum += bpm
        sessionCount += 1
        zoneCounts[HRZone.zone(for: bpm, maxHR: maxHR), default: 0] += 1
    }

    public func hrDisconnected() { hrStatus = .stale }
    public func hrFailed(_ message: String) { hrStatus = .error(message) }

    public func resetSession() {
        recent = []; recentPoints = []; sessionMin = nil; sessionMax = nil
        sessionSum = 0; sessionCount = 0; zoneCounts = [:]
    }

    public var hrZone: HRZone? { liveHR.map { HRZone.zone(for: $0, maxHR: maxHR) } }

    /// Current HR as a percentage of max HR.
    public var percentMax: Int? {
        liveHR.map { Int((Double($0) / Double(Swift.max(maxHR, 1)) * 100).rounded()) }
    }

    public var sessionAvg: Int? {
        sessionCount == 0 ? nil : Int((Double(sessionSum) / Double(sessionCount)).rounded())
    }

    public var recentMin: Int? { recent.min() }
    public var recentMax: Int? { recent.max() }

    public var recentAvg: Int? {
        recent.isEmpty ? nil : Int((Double(recent.reduce(0, +)) / Double(recent.count)).rounded())
    }

    public var recentDuration: TimeInterval {
        guard let first = recentPoints.first?.timestamp,
              let last = recentPoints.last?.timestamp else { return 0 }
        return Swift.max(0, last.timeIntervalSince(first))
    }

    public enum Trend: Sendable { case rising, falling, steady }
    public var hrTrend: Trend? {
        guard recent.count >= 6, let last = recent.last else { return nil }
        let window = recent.suffix(6)
        let avg = Double(window.reduce(0, +)) / Double(window.count)
        if Double(last) > avg + 2 { return .rising }
        if Double(last) < avg - 2 { return .falling }
        return .steady
    }

    /// Fraction (0...1) of session samples spent in the given zone.
    public func zoneFraction(_ zone: HRZone) -> Double {
        let total = zoneCounts.values.reduce(0, +)
        return total == 0 ? 0 : Double(zoneCounts[zone] ?? 0) / Double(total)
    }

    private func pruneRecentSamples(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.recentWindow)
        while let first = recentPoints.first, first.timestamp < cutoff {
            recentPoints.removeFirst()
            if !recent.isEmpty { recent.removeFirst() }
        }
        if recent.count > recentCap {
            let overflow = recent.count - recentCap
            recent.removeFirst(overflow)
            recentPoints.removeFirst(Swift.min(overflow, recentPoints.count))
        }
    }
}
