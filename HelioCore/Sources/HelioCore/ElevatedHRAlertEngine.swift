import Foundation

/// Config for the elevated-HR alert.
public struct ElevatedHRConfig: Equatable, Sendable {
    public var enabled: Bool
    public var threshold: Int          // bpm
    public var duration: TimeInterval  // seconds the HR must stay elevated
    public init(enabled: Bool = false, threshold: Int = 100, duration: TimeInterval = 180) {
        self.enabled = enabled; self.threshold = threshold; self.duration = duration
    }
}

/// Decides when to fire an "elevated HR" alert: HR at/above `threshold`
/// continuously for `duration`. Fires once per elevated episode (until HR
/// drops back below threshold, which re-arms it).
public final class ElevatedHRAlertEngine {
    public var config: ElevatedHRConfig
    private var elevatedSince: Date?
    private var fired = false

    public init(config: ElevatedHRConfig = .init()) { self.config = config }

    /// Call on each HR sample. Returns true exactly once when the alert should fire.
    public func evaluate(bpm: Int, now: Date) -> Bool {
        guard config.enabled else { reset(); return false }
        if bpm >= config.threshold {
            if elevatedSince == nil { elevatedSince = now }
            if !fired, let since = elevatedSince, now.timeIntervalSince(since) >= config.duration {
                fired = true
                return true
            }
        } else {
            reset()
        }
        return false
    }

    private func reset() { elevatedSince = nil; fired = false }
}
