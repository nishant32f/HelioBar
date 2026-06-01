import XCTest
@testable import HelioCore

final class ElevatedHRAlertEngineTests: XCTestCase {
    private func engine() -> ElevatedHRAlertEngine {
        ElevatedHRAlertEngine(config: .init(enabled: true, threshold: 100, duration: 180))
    }
    private let t0 = Date(timeIntervalSince1970: 0)

    func test_belowThresholdNeverFires() {
        let e = engine()
        XCTAssertFalse(e.evaluate(bpm: 90, now: t0))
        XCTAssertFalse(e.evaluate(bpm: 99, now: t0.addingTimeInterval(600)))
    }

    func test_firesOnceAfterDuration() {
        let e = engine()
        XCTAssertFalse(e.evaluate(bpm: 110, now: t0))                     // starts elevated
        XCTAssertFalse(e.evaluate(bpm: 110, now: t0.addingTimeInterval(120))) // not long enough
        XCTAssertTrue(e.evaluate(bpm: 110, now: t0.addingTimeInterval(180)))  // fires
        XCTAssertFalse(e.evaluate(bpm: 110, now: t0.addingTimeInterval(240))) // no re-fire
    }

    func test_dropBelowReArms() {
        let e = engine()
        _ = e.evaluate(bpm: 110, now: t0)
        XCTAssertTrue(e.evaluate(bpm: 110, now: t0.addingTimeInterval(180)))
        XCTAssertFalse(e.evaluate(bpm: 80, now: t0.addingTimeInterval(200)))   // drop -> re-arm
        XCTAssertFalse(e.evaluate(bpm: 110, now: t0.addingTimeInterval(210)))  // elevated again
        XCTAssertTrue(e.evaluate(bpm: 110, now: t0.addingTimeInterval(390)))   // fires again
    }

    func test_disabledNeverFires() {
        let e = ElevatedHRAlertEngine(config: .init(enabled: false, threshold: 100, duration: 1))
        XCTAssertFalse(e.evaluate(bpm: 150, now: t0))
        XCTAssertFalse(e.evaluate(bpm: 150, now: t0.addingTimeInterval(100)))
    }
}
