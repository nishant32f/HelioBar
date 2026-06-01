import Foundation

public protocol TokenStoring: Sendable {
    func save(_ creds: ZeppCredentials) throws
    func load() -> ZeppCredentials?
    func clear() throws
}

/// Test/double implementation. The app uses KeychainTokenStore.
public final class InMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private var creds: ZeppCredentials?
    public init() {}
    public func save(_ creds: ZeppCredentials) throws { self.creds = creds }
    public func load() -> ZeppCredentials? { creds }
    public func clear() throws { creds = nil }
}
