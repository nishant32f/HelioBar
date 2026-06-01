import Foundation

public protocol HTTPFetching: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPFetching {}

public struct ZeppCredentials: Sendable, Equatable {
    public let appToken: String
    public let host: String     // regional API host, e.g. "api-mifit-us3.zepp.com"
    public init(appToken: String, host: String) {
        self.appToken = appToken
        self.host = host
    }
}

public enum ZeppCloudError: Error, Equatable {
    case http(Int)
    case decoding
    case invalidHost
    case noData          // request succeeded but contained no items / no score
}

public struct ZeppMetrics: Equatable, Sendable {
    public let stress: StressReading
    public let readiness: ReadinessReading
}

/// Reads stress + readiness from the Zepp/Huami mobile API's generic event
/// stream: `GET /v2/users/me/events?eventType=...&subType=...`.
///
/// Endpoint shapes are reverse-engineered from the community `zepp-health-cli`
/// project (api-mifit-*.zepp.com). The envelope `{"items":[{timestamp,value}]}`
/// is stable; the inner `value` shape varies, so `extractScore` searches common
/// keys and decodes string-encoded JSON. If your account returns different inner
/// keys, add them to `scoreKeys` below — `ZeppCloudClientTests` pins the contract.
public struct ZeppCloudClient: Sendable {
    private let http: HTTPFetching
    private let creds: ZeppCredentials
    private let now: @Sendable () -> Date

    public init(http: HTTPFetching,
                creds: ZeppCredentials,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http
        self.creds = creds
        self.now = now
    }

    public func fetchMetrics() async throws -> ZeppMetrics {
        async let stress = fetchStress()
        async let readiness = fetchReadiness()
        return try await ZeppMetrics(stress: stress, readiness: readiness)
    }

    func fetchStress() async throws -> StressReading {
        let value = try await latestEventValue(eventType: "Charge", subType: "stress_data")
        guard let score = Self.extractScore(value) else { throw ZeppCloudError.noData }
        return StressReading(value: score, label: Self.stressLabel(score))
    }

    func fetchReadiness() async throws -> ReadinessReading {
        let value = try await latestEventValue(eventType: "readiness", subType: "watch_score")
        guard let score = Self.extractScore(value) else { throw ZeppCloudError.noData }
        return ReadinessReading(value: score)
    }

    /// Fetches the event stream for a metric and returns the `value` of the
    /// most-recent item (by timestamp).
    func latestEventValue(eventType: String, subType: String) async throws -> Any {
        let (data, resp) = try await http.data(
            for: try makeRequest(eventType: eventType, subType: subType))
        if let http = resp as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw ZeppCloudError.http(http.statusCode)
        }
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = root["items"] as? [[String: Any]]
        else { throw ZeppCloudError.decoding }
        guard let newest = items.max(by: {
            ($0["timestamp"] as? Int ?? 0) < ($1["timestamp"] as? Int ?? 0)
        }), let value = newest["value"] else { throw ZeppCloudError.noData }
        return value
    }

    func makeRequest(eventType: String, subType: String) throws -> URLRequest {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = creds.host
        comps.path = "/v2/users/me/events"
        let toMs = Int(now().timeIntervalSince1970 * 1000)
        let fromMs = toMs - 3 * 24 * 60 * 60 * 1000   // last 3 days
        comps.queryItems = [
            URLQueryItem(name: "eventType", value: eventType),
            URLQueryItem(name: "subType", value: subType),
            URLQueryItem(name: "from", value: String(fromMs)),
            URLQueryItem(name: "to", value: String(toMs)),
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "reverse", value: "0"),
        ]
        guard let url = comps.url else { throw ZeppCloudError.invalidHost }
        var req = URLRequest(url: url)
        req.setValue(creds.appToken, forHTTPHeaderField: "apptoken")
        req.setValue("com.huami.midong", forHTTPHeaderField: "appname")
        req.setValue("2.0", forHTTPHeaderField: "v")
        req.setValue("en_US", forHTTPHeaderField: "lang")
        req.setValue(TimeZone.current.identifier, forHTTPHeaderField: "timezone")
        req.setValue("MiFit/6.0.0 (iPhone; iOS 16.0)", forHTTPHeaderField: "user-agent")
        return req
    }

    /// Inner `value` payloads vary; pull the first numeric score we recognise.
    private static let scoreKeys = ["score", "value", "stress", "readiness", "fatigue", "level"]

    static func extractScore(_ value: Any) -> Int? {
        if let n = value as? Int { return n }
        if let d = value as? Double { return Int(d.rounded()) }
        if let s = value as? String {
            if let n = Int(s) { return n }
            if let d = Double(s) { return Int(d.rounded()) }
            if let data = s.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) {
                return extractScore(obj)
            }
        }
        if let dict = value as? [String: Any] {
            for key in scoreKeys {
                if let v = dict[key], let n = extractScore(v) { return n }
            }
        }
        return nil
    }

    /// Zepp stress bands.
    static func stressLabel(_ score: Int) -> String {
        switch score {
        case ..<40:   return "Relaxed"
        case 40..<60: return "Normal"
        case 60..<80: return "Medium"
        default:      return "High"
        }
    }
}
