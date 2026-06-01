import XCTest
@testable import HelioCore

/// Routes responses by the `subType` query param so one client call (which makes
/// two requests — stress + readiness) gets the right body for each.
private struct RoutingHTTP: HTTPFetching {
    var bodies: [String: Data]      // keyed by subType
    var status: Int = 200
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let sub = comps?.queryItems?.first { $0.name == "subType" }?.value ?? ""
        let resp = HTTPURLResponse(url: request.url!, statusCode: status,
                                   httpVersion: nil, headerFields: nil)!
        return (bodies[sub] ?? Data(), resp)
    }
}

final class ZeppCloudClientTests: XCTestCase {
    private let creds = ZeppCredentials(appToken: "tok", host: "api.example.com")
    private let fixedNow: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }

    private func client(_ http: HTTPFetching) -> ZeppCloudClient {
        ZeppCloudClient(http: http, creds: creds, now: fixedNow)
    }

    func test_fetchesStressAndReadinessFromEventStream() async throws {
        let http = RoutingHTTP(bodies: [
            "stress_data": Data(#"{"items":[{"timestamp":10,"value":{"score":34}}]}"#.utf8),
            "watch_score": Data(#"{"items":[{"timestamp":10,"value":{"score":81}}]}"#.utf8),
        ])
        let metrics = try await client(http).fetchMetrics()
        XCTAssertEqual(metrics.stress, StressReading(value: 34, label: "Relaxed"))
        XCTAssertEqual(metrics.readiness, ReadinessReading(value: 81))
    }

    func test_picksNewestItemByTimestamp() async throws {
        let http = RoutingHTTP(bodies: [
            "stress_data": Data(#"""
            {"items":[{"timestamp":10,"value":{"score":20}},
                      {"timestamp":99,"value":{"score":70}}]}
            """#.utf8),
            "watch_score": Data(#"{"items":[{"timestamp":1,"value":{"score":50}}]}"#.utf8),
        ])
        let metrics = try await client(http).fetchMetrics()
        XCTAssertEqual(metrics.stress.value, 70)      // timestamp 99 wins
        XCTAssertEqual(metrics.stress.label, "Medium")
    }

    func test_extractsScoreFromStringEncodedValue() async throws {
        // Some payloads nest a JSON string inside `value`.
        let http = RoutingHTTP(bodies: [
            "stress_data": Data(#"{"items":[{"timestamp":1,"value":"{\"stress\":45}"}]}"#.utf8),
            "watch_score": Data(#"{"items":[{"timestamp":1,"value":{"score":60}}]}"#.utf8),
        ])
        let metrics = try await client(http).fetchMetrics()
        XCTAssertEqual(metrics.stress, StressReading(value: 45, label: "Normal"))
        XCTAssertEqual(metrics.readiness.value, 60)
    }

    func test_throwsOnNon2xx() async {
        let http = RoutingHTTP(bodies: ["stress_data": Data(), "watch_score": Data()],
                               status: 401)
        await assertThrows(client(http)) { XCTAssertEqual($0, .http(401)) }
    }

    func test_throwsNoDataWhenItemsEmpty() async {
        let http = RoutingHTTP(bodies: [
            "stress_data": Data(#"{"items":[]}"#.utf8),
            "watch_score": Data(#"{"items":[{"timestamp":1,"value":{"score":60}}]}"#.utf8),
        ])
        await assertThrows(client(http)) { XCTAssertEqual($0, .noData) }
    }

    func test_throwsDecodingOnGarbage() async {
        let http = RoutingHTTP(bodies: [
            "stress_data": Data("nope".utf8),
            "watch_score": Data(#"{"items":[{"timestamp":1,"value":{"score":60}}]}"#.utf8),
        ])
        await assertThrows(client(http)) { XCTAssertEqual($0, .decoding) }
    }

    func test_requestCarriesAppTokenPathAndSubType() throws {
        let client = client(RoutingHTTP(bodies: [:]))
        let req = try client.makeRequest(eventType: "Charge", subType: "stress_data")
        XCTAssertEqual(req.value(forHTTPHeaderField: "apptoken"), "tok")
        XCTAssertEqual(req.value(forHTTPHeaderField: "appname"), "com.huami.midong")
        XCTAssertEqual(req.url?.host, "api.example.com")
        XCTAssertEqual(req.url?.path, "/v2/users/me/events")
        let q = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(q.contains(URLQueryItem(name: "subType", value: "stress_data")))
        XCTAssertTrue(q.contains(URLQueryItem(name: "eventType", value: "Charge")))
    }

    func test_makeRequestThrowsOnInvalidHost() {
        let c = ZeppCloudClient(http: RoutingHTTP(bodies: [:]),
                                creds: ZeppCredentials(appToken: "t", host: "not a host"),
                                now: fixedNow)
        XCTAssertThrowsError(try c.makeRequest(eventType: "Charge", subType: "stress_data")) {
            XCTAssertEqual($0 as? ZeppCloudError, .invalidHost)
        }
    }

    // MARK: helper
    private func assertThrows(_ client: ZeppCloudClient,
                              _ check: (ZeppCloudError) -> Void,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await client.fetchMetrics()
            XCTFail("expected throw", file: file, line: line)
        } catch let e as ZeppCloudError {
            check(e)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}
