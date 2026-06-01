import Foundation

public protocol HTTPFetching: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPFetching {}

public struct ZeppCredentials: Sendable, Equatable {
    public let appToken: String
    public let host: String     // regional API host, e.g. "api-mifit-us2.zepp.com"
    public init(appToken: String, host: String) {
        self.appToken = appToken
        self.host = host
    }
}

public enum ZeppCloudError: Error, Equatable {
    case http(Int)
    case decoding
}

public struct ZeppMetrics: Equatable, Sendable {
    public let stress: StressReading
    public let readiness: ReadinessReading
}

public struct ZeppCloudClient: Sendable {
    private let http: HTTPFetching
    private let creds: ZeppCredentials

    public init(http: HTTPFetching, creds: ZeppCredentials) {
        self.http = http
        self.creds = creds
    }

    public func fetchMetrics() async throws -> ZeppMetrics {
        let (data, resp) = try await http.data(for: Self.makeRequest(creds: creds))
        if let http = resp as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw ZeppCloudError.http(http.statusCode)
        }
        return try Self.decode(data)
    }

    /// NOTE: calibrate path/query against your own HAR capture.
    static func makeRequest(creds: ZeppCredentials) -> URLRequest {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = creds.host
        comps.path = "/users/me/health/summary"   // placeholder — adjust to real capture
        var req = URLRequest(url: comps.url!)
        req.setValue(creds.appToken, forHTTPHeaderField: "apptoken")
        return req
    }

    static func decode(_ data: Data) throws -> ZeppMetrics {
        struct Payload: Decodable {
            struct Stress: Decodable { let score: Int; let level: String }
            struct Readiness: Decodable { let score: Int }
            let stress: Stress
            let readiness: Readiness
        }
        guard let p = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw ZeppCloudError.decoding
        }
        return ZeppMetrics(
            stress: StressReading(value: p.stress.score, label: p.stress.level),
            readiness: ReadinessReading(value: p.readiness.score))
    }
}
