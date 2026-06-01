import XCTest
@testable import HelioCore

private struct FakeHTTP: HTTPFetching {
    let result: Result<(Data, URLResponse), Error>
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try result.get()
    }
}

private func response(_ url: URL, _ code: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
}

final class ZeppCloudClientTests: XCTestCase {
    private let creds = ZeppCredentials(appToken: "tok", host: "api.example.com")

    func test_decodesMetricsFrom200() async throws {
        let json = Data("""
        {"stress":{"score":34,"level":"Relaxed"},"readiness":{"score":81}}
        """.utf8)
        let url = URL(string: "https://api.example.com")!
        let client = ZeppCloudClient(
            http: FakeHTTP(result: .success((json, response(url, 200)))),
            creds: creds)

        let metrics = try await client.fetchMetrics()

        XCTAssertEqual(metrics.stress, StressReading(value: 34, label: "Relaxed"))
        XCTAssertEqual(metrics.readiness, ReadinessReading(value: 81))
    }

    func test_throwsOnNon2xx() async {
        let url = URL(string: "https://api.example.com")!
        let client = ZeppCloudClient(
            http: FakeHTTP(result: .success((Data(), response(url, 401)))),
            creds: creds)

        do {
            _ = try await client.fetchMetrics()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? ZeppCloudError, .http(401))
        }
    }

    func test_throwsOnBadJSON() async {
        let url = URL(string: "https://api.example.com")!
        let client = ZeppCloudClient(
            http: FakeHTTP(result: .success((Data("nope".utf8), response(url, 200)))),
            creds: creds)

        do {
            _ = try await client.fetchMetrics()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? ZeppCloudError, .decoding)
        }
    }

    func test_requestCarriesAppTokenHeader() {
        let req = ZeppCloudClient.makeRequest(creds: creds)
        XCTAssertEqual(req.value(forHTTPHeaderField: "apptoken"), "tok")
        XCTAssertEqual(req.url?.host, "api.example.com")
    }
}
