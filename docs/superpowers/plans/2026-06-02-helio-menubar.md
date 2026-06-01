# HelioBar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS menu bar app showing live heart rate (BLE) from an Amazfit Helio Strap, plus stress and readiness (Zepp cloud) in a dropdown.

**Architecture:** Pure, I/O-free logic (models, BLE packet parser, central `HealthStore` state, cloud client) lives in a Swift Package `HelioCore`, unit-tested via `swift test`. A thin macOS app target (generated from text via XcodeGen) adds the CoreBluetooth manager, Keychain token storage, and the SwiftUI `MenuBarExtra` UI, all reading the single `HealthStore`.

**Tech Stack:** Swift 6, SwiftUI `MenuBarExtra`, Observation (`@Observable`), CoreBluetooth, `URLSession`, Security (Keychain), `SMAppService`, XcodeGen, XCTest.

**Deployment target:** macOS 14 (required by `@Observable` / Observation framework; `MenuBarExtra` needs 13+ so 14 satisfies both).

---

## Prerequisites

- [ ] **Step 0a: Install toolchain deps**

Run:
```bash
xcodegen --version || brew install xcodegen
swift --version   # expect Swift 6.x
```
Expected: both print versions.

- [ ] **Step 0b: Confirm repo state**

Run: `cd /Users/tirth/Desktop/Projects/HelioBar && git status`
Expected: clean tree, `docs/` present.

---

## File Structure

```
HelioBar/
  HelioCore/                         Swift package (CLI-testable logic)
    Package.swift
    Sources/HelioCore/
      Models.swift                   HRZone, SourceStatus, StressReading, ReadinessReading
      HeartRatePacket.swift          BLE 0x2A37 parser (pure)
      HealthStore.swift              @Observable single source of truth
      ZeppCloudClient.swift          HTTPFetching protocol + client + decode
      TokenStoring.swift             token store protocol + in-memory fake
    Tests/HelioCoreTests/
      HeartRatePacketTests.swift
      HealthStoreTests.swift
      ZeppCloudClientTests.swift
  HelioBarApp/                       macOS app target sources
    HelioBarApp.swift                @main App + MenuBarExtra
    AppModel.swift                   wires monitor + cloud poller into HealthStore
    HeartRateMonitor.swift           CoreBluetooth (manual-verified)
    KeychainTokenStore.swift         Security framework TokenStoring impl
    SettingsStore.swift              UserDefaults-backed prefs
    Views/
      MenuContentView.swift          dropdown
      SettingsView.swift             token entry, interval, launch-at-login
    Resources/
      Info.plist                     LSUIElement, NSBluetoothAlwaysUsageDescription
      HelioBar.entitlements          sandbox + bluetooth + network
  project.yml                        XcodeGen project definition
  docs/...                           spec + this plan + token-capture guide
```

---

## Phase 1 — Core package (TDD via `swift test`)

### Task 1: Package scaffold

**Files:**
- Create: `HelioCore/Package.swift`
- Create: `HelioCore/Sources/HelioCore/Placeholder.swift`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HelioCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HelioCore", targets: ["HelioCore"]),
    ],
    targets: [
        .target(name: "HelioCore"),
        .testTarget(name: "HelioCoreTests", dependencies: ["HelioCore"]),
    ]
)
```

- [ ] **Step 2: Add a placeholder so the target compiles**

`HelioCore/Sources/HelioCore/Placeholder.swift`:
```swift
// Intentionally empty; replaced by real types in later tasks.
```

- [ ] **Step 3: Verify the package builds**

Run: `cd HelioCore && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add HelioCore
git commit -m "chore: scaffold HelioCore swift package"
```

---

### Task 2: Models

**Files:**
- Create: `HelioCore/Sources/HelioCore/Models.swift`

- [ ] **Step 1: Write `Models.swift`**

```swift
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
```

- [ ] **Step 2: Delete the placeholder**

```bash
rm HelioCore/Sources/HelioCore/Placeholder.swift
```

- [ ] **Step 3: Build**

Run: `cd HelioCore && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add HelioCore
git commit -m "feat: add core health models and HR zones"
```

---

### Task 3: Heart-rate packet parser (TDD)

**Files:**
- Create: `HelioCore/Sources/HelioCore/HeartRatePacket.swift`
- Test: `HelioCore/Tests/HelioCoreTests/HeartRatePacketTests.swift`

- [ ] **Step 1: Write the failing tests**

`HelioCore/Tests/HelioCoreTests/HeartRatePacketTests.swift`:
```swift
import XCTest
@testable import HelioCore

final class HeartRatePacketTests: XCTestCase {
    func test_parses8BitBPM() {
        // flags=0x00 (8-bit), value=0x48 (72)
        XCTAssertEqual(HeartRatePacket.parse(Data([0x00, 0x48])), 72)
    }

    func test_parses16BitBPM() {
        // flags=0x01 (16-bit), value little-endian 0x012C (300)
        XCTAssertEqual(HeartRatePacket.parse(Data([0x01, 0x2C, 0x01])), 300)
    }

    func test_ignoresOtherFlagBits() {
        // flags=0x10 (some other bit set), still 8-bit, value 0x50 (80)
        XCTAssertEqual(HeartRatePacket.parse(Data([0x10, 0x50])), 80)
    }

    func test_returnsNilForEmpty() {
        XCTAssertNil(HeartRatePacket.parse(Data()))
    }

    func test_returnsNilWhenTruncated8Bit() {
        XCTAssertNil(HeartRatePacket.parse(Data([0x00])))
    }

    func test_returnsNilWhenTruncated16Bit() {
        XCTAssertNil(HeartRatePacket.parse(Data([0x01, 0x2C])))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd HelioCore && swift test --filter HeartRatePacketTests`
Expected: FAIL — `cannot find 'HeartRatePacket' in scope`.

- [ ] **Step 3: Write the implementation**

`HelioCore/Sources/HelioCore/HeartRatePacket.swift`:
```swift
import Foundation

/// Parses a BLE Heart Rate Measurement characteristic value (UUID 0x2A37).
/// Spec: first byte is flags; bit 0 = 0 → 8-bit BPM, bit 0 = 1 → 16-bit LE BPM.
public enum HeartRatePacket {
    public static func parse(_ data: Data) -> Int? {
        guard let flags = data.first else { return nil }
        let base = data.startIndex
        let is16Bit = (flags & 0x01) != 0
        if is16Bit {
            guard data.count >= 3 else { return nil }
            let lo = UInt16(data[base + 1])
            let hi = UInt16(data[base + 2])
            return Int(lo | (hi << 8))
        } else {
            guard data.count >= 2 else { return nil }
            return Int(data[base + 1])
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd HelioCore && swift test --filter HeartRatePacketTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add HelioCore
git commit -m "feat: parse BLE heart rate measurement packets"
```

---

### Task 4: HealthStore (TDD)

**Files:**
- Create: `HelioCore/Sources/HelioCore/HealthStore.swift`
- Test: `HelioCore/Tests/HelioCoreTests/HealthStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

`HelioCore/Tests/HelioCoreTests/HealthStoreTests.swift`:
```swift
import XCTest
@testable import HelioCore

@MainActor
final class HealthStoreTests: XCTestCase {
    func test_startsIdle() {
        let store = HealthStore()
        XCTAssertNil(store.liveHR)
        XCTAssertEqual(store.hrStatus, .idle)
        XCTAssertEqual(store.cloudStatus, .idle)
    }

    func test_updateHRSetsValueAndLive() {
        let store = HealthStore()
        store.updateHR(72)
        XCTAssertEqual(store.liveHR, 72)
        XCTAssertEqual(store.hrStatus, .live)
        XCTAssertEqual(store.hrZone, .resting)
    }

    func test_hrDisconnectedKeepsValueButGoesStale() {
        let store = HealthStore()
        store.updateHR(72)
        store.hrDisconnected()
        XCTAssertEqual(store.liveHR, 72)        // last value retained
        XCTAssertEqual(store.hrStatus, .stale)
    }

    func test_updateCloudSetsMetricsAndSync() {
        let store = HealthStore()
        let when = Date(timeIntervalSince1970: 1_000)
        store.updateCloud(stress: StressReading(value: 34, label: "Relaxed"),
                          readiness: ReadinessReading(value: 81),
                          at: when)
        XCTAssertEqual(store.stress, StressReading(value: 34, label: "Relaxed"))
        XCTAssertEqual(store.readiness, ReadinessReading(value: 81))
        XCTAssertEqual(store.lastSync, when)
        XCTAssertEqual(store.cloudStatus, .live)
    }

    func test_cloudFailureDoesNotTouchHR() {
        let store = HealthStore()
        store.updateHR(80)
        store.cloudFailed("401")
        XCTAssertEqual(store.liveHR, 80)               // HR untouched
        XCTAssertEqual(store.hrStatus, .live)
        XCTAssertEqual(store.cloudStatus, .error("401"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd HelioCore && swift test --filter HealthStoreTests`
Expected: FAIL — `cannot find 'HealthStore' in scope`.

- [ ] **Step 3: Write the implementation**

`HelioCore/Sources/HelioCore/HealthStore.swift`:
```swift
import Foundation
import Observation

/// Single source of truth the UI binds to. No I/O — sources push into it.
@MainActor
@Observable
public final class HealthStore {
    public var liveHR: Int?
    public var hrStatus: SourceStatus = .idle
    public var stress: StressReading?
    public var readiness: ReadinessReading?
    public var cloudStatus: SourceStatus = .idle
    public var lastSync: Date?

    public init() {}

    public func updateHR(_ bpm: Int) {
        liveHR = bpm
        hrStatus = .live
    }

    public func hrDisconnected() {
        hrStatus = .stale
    }

    public func updateCloud(stress: StressReading,
                            readiness: ReadinessReading,
                            at date: Date) {
        self.stress = stress
        self.readiness = readiness
        self.lastSync = date
        self.cloudStatus = .live
    }

    public func cloudFailed(_ message: String) {
        cloudStatus = .error(message)
    }

    public var hrZone: HRZone? {
        liveHR.map(HRZone.zone(for:))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd HelioCore && swift test --filter HealthStoreTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add HelioCore
git commit -m "feat: add HealthStore single source of truth"
```

---

### Task 5: ZeppCloudClient (TDD)

**Files:**
- Create: `HelioCore/Sources/HelioCore/ZeppCloudClient.swift`
- Test: `HelioCore/Tests/HelioCoreTests/ZeppCloudClientTests.swift`

> **Calibration note:** The Zepp/Huami endpoints are reverse-engineered and undocumented. This task ships a *defined normalized JSON shape* and parses it. After you have a real HAR capture, adjust `makeRequest` (path/query) and the `Payload` struct in `decode` to match the real response. The tests pin the parsing contract so changes stay safe.

- [ ] **Step 1: Write the failing tests**

`HelioCore/Tests/HelioCoreTests/ZeppCloudClientTests.swift`:
```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd HelioCore && swift test --filter ZeppCloudClientTests`
Expected: FAIL — `cannot find 'ZeppCloudClient' in scope`.

- [ ] **Step 3: Write the implementation**

`HelioCore/Sources/HelioCore/ZeppCloudClient.swift`:
```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd HelioCore && swift test --filter ZeppCloudClientTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add HelioCore
git commit -m "feat: add Zepp cloud client with injectable HTTP"
```

---

### Task 6: TokenStoring protocol + in-memory fake (TDD)

**Files:**
- Create: `HelioCore/Sources/HelioCore/TokenStoring.swift`
- Test: `HelioCore/Tests/HelioCoreTests/TokenStoringTests.swift`

- [ ] **Step 1: Write the failing tests**

`HelioCore/Tests/HelioCoreTests/TokenStoringTests.swift`:
```swift
import XCTest
@testable import HelioCore

final class TokenStoringTests: XCTestCase {
    func test_roundTrips() throws {
        let store = InMemoryTokenStore()
        try store.save(ZeppCredentials(appToken: "abc", host: "h"))
        XCTAssertEqual(store.load(), ZeppCredentials(appToken: "abc", host: "h"))
    }

    func test_clearRemoves() throws {
        let store = InMemoryTokenStore()
        try store.save(ZeppCredentials(appToken: "abc", host: "h"))
        try store.clear()
        XCTAssertNil(store.load())
    }

    func test_loadNilWhenEmpty() {
        XCTAssertNil(InMemoryTokenStore().load())
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd HelioCore && swift test --filter TokenStoringTests`
Expected: FAIL — `cannot find 'InMemoryTokenStore' in scope`.

- [ ] **Step 3: Write the implementation**

`HelioCore/Sources/HelioCore/TokenStoring.swift`:
```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd HelioCore && swift test --filter TokenStoringTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full core suite + commit**

Run: `cd HelioCore && swift test`
Expected: ALL PASS (18 tests across 4 files).

```bash
git add HelioCore
git commit -m "feat: add TokenStoring protocol and in-memory store"
```

---

## Phase 2 — macOS app target (XcodeGen + manual verification)

> BLE and SwiftUI UI are not meaningfully unit-testable from `swift test` (they need Bluetooth entitlement and a running app). These tasks provide complete code plus explicit **manual verification** steps and SwiftUI previews.

### Task 7: App scaffold (XcodeGen) that builds and shows an empty menu bar item

**Files:**
- Create: `project.yml`
- Create: `HelioBarApp/HelioBarApp.swift`
- Create: `HelioBarApp/Resources/Info.plist`
- Create: `HelioBarApp/Resources/HelioBar.entitlements`

- [ ] **Step 1: Write `project.yml`**

```yaml
name: HelioBar
options:
  bundleIdPrefix: com.helio
  deploymentTarget:
    macOS: "14.0"
packages:
  HelioCore:
    path: HelioCore
targets:
  HelioBar:
    type: application
    platform: macOS
    sources:
      - HelioBarApp
    dependencies:
      - package: HelioCore
    settings:
      base:
        INFOPLIST_FILE: HelioBarApp/Resources/Info.plist
        CODE_SIGN_ENTITLEMENTS: HelioBarApp/Resources/HelioBar.entitlements
        PRODUCT_BUNDLE_IDENTIFIER: com.helio.HelioBar
        CODE_SIGN_STYLE: Automatic
        ENABLE_HARDENED_RUNTIME: YES
        SWIFT_VERSION: "6.0"
```

- [ ] **Step 2: Write `Info.plist`**

`HelioBarApp/Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>HelioBar</string>
  <key>CFBundleIdentifier</key><string>com.helio.HelioBar</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>HelioBar reads your strap's live heart rate broadcast.</string>
</dict>
</plist>
```

- [ ] **Step 3: Write `HelioBar.entitlements`**

`HelioBarApp/Resources/HelioBar.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.device.bluetooth</key><true/>
  <key>com.apple.security.network.client</key><true/>
</dict>
</plist>
```

- [ ] **Step 4: Write a minimal `@main` app**

`HelioBarApp/HelioBarApp.swift`:
```swift
import SwiftUI

@main
struct HelioBarApp: App {
    var body: some Scene {
        MenuBarExtra("HelioBar", systemImage: "heart.fill") {
            Text("Hello from HelioBar")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 5: Generate the project and build**

Run:
```bash
cd /Users/tirth/Desktop/Projects/HelioBar
xcodegen generate
xcodebuild -scheme HelioBar -destination 'platform=macOS' -configuration Debug build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual verification**

Run: open the built app (path printed by xcodebuild, under DerivedData), e.g.
```bash
open "$(find ~/Library/Developer/Xcode/DerivedData -name HelioBar.app -path '*Debug*' | head -1)"
```
Expected: a heart icon appears in the menu bar; clicking shows "Hello from HelioBar" and Quit. No Dock icon (LSUIElement).

- [ ] **Step 7: Add generated project to gitignore and commit**

Append to `.gitignore`:
```
*.xcodeproj
```
Then:
```bash
git add project.yml HelioBarApp .gitignore
git commit -m "chore: scaffold HelioBar app target via XcodeGen"
```

---

### Task 8: KeychainTokenStore

**Files:**
- Create: `HelioBarApp/KeychainTokenStore.swift`

- [ ] **Step 1: Write the implementation**

`HelioBarApp/KeychainTokenStore.swift`:
```swift
import Foundation
import Security
import HelioCore

/// Stores the apptoken in the keychain; host in UserDefaults alongside.
struct KeychainTokenStore: TokenStoring {
    private let account = "zepp-apptoken"
    private let service = "com.helio.HelioBar"
    private let hostKey = "zepp-host"

    func save(_ creds: ZeppCredentials) throws {
        try clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(creds.appToken.utf8),
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.os(status) }
        UserDefaults.standard.set(creds.host, forKey: hostKey)
    }

    func load() -> ZeppCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              let host = UserDefaults.standard.string(forKey: hostKey)
        else { return nil }
        return ZeppCredentials(appToken: token, host: host)
    }

    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.os(status)
        }
        UserDefaults.standard.removeObject(forKey: hostKey)
    }

    enum KeychainError: Error { case os(OSStatus) }
}
```

- [ ] **Step 2: Build**

Run: `cd /Users/tirth/Desktop/Projects/HelioBar && xcodegen generate && xcodebuild -scheme HelioBar -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/KeychainTokenStore.swift
git commit -m "feat: keychain-backed token store"
```

---

### Task 9: HeartRateMonitor (CoreBluetooth)

**Files:**
- Create: `HelioBarApp/HeartRateMonitor.swift`

- [ ] **Step 1: Write the implementation**

`HelioBarApp/HeartRateMonitor.swift`:
```swift
import CoreBluetooth
import HelioCore

/// Connects to the strap's standard BLE Heart Rate broadcast and reports BPM.
/// Reports connection state so the UI can show live vs. reconnecting.
final class HeartRateMonitor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let onBPM: (Int) -> Void
    private let onConnected: (Bool) -> Void

    private let hrService = CBUUID(string: "180D")
    private let hrMeasurement = CBUUID(string: "2A37")

    init(onBPM: @escaping (Int) -> Void,
         onConnected: @escaping (Bool) -> Void) {
        self.onBPM = onBPM
        self.onConnected = onConnected
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [hrService])
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onConnected(true)
        peripheral.discoverServices([hrService])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        onConnected(false)
        central.scanForPeripherals(withServices: [hrService])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == hrService {
            peripheral.discoverCharacteristics([hrMeasurement], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        for char in service.characteristics ?? [] where char.uuid == hrMeasurement {
            peripheral.setNotifyValue(true, for: char)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value,
              let bpm = HeartRatePacket.parse(data) else { return }
        onBPM(bpm)
    }
}
```

- [ ] **Step 2: Build**

Run: `cd /Users/tirth/Desktop/Projects/HelioBar && xcodegen generate && xcodebuild -scheme HelioBar -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/HeartRateMonitor.swift
git commit -m "feat: CoreBluetooth heart rate monitor"
```

---

### Task 10: SettingsStore + AppModel (wiring)

**Files:**
- Create: `HelioBarApp/SettingsStore.swift`
- Create: `HelioBarApp/AppModel.swift`

- [ ] **Step 1: Write `SettingsStore.swift`**

`HelioBarApp/SettingsStore.swift`:
```swift
import Foundation

/// UserDefaults-backed prefs (cloud refresh interval).
struct SettingsStore {
    private let intervalKey = "cloudRefreshSeconds"

    var refreshSeconds: Double {
        get {
            let v = UserDefaults.standard.double(forKey: intervalKey)
            return v == 0 ? 300 : v          // default 5 min
        }
        nonmutating set {
            UserDefaults.standard.set(newValue, forKey: intervalKey)
        }
    }
}
```

- [ ] **Step 2: Write `AppModel.swift`**

`HelioBarApp/AppModel.swift`:
```swift
import Foundation
import HelioCore

/// Owns the live data sources and feeds the shared HealthStore.
@MainActor
@Observable
final class AppModel {
    let store = HealthStore()
    let tokenStore: TokenStoring = KeychainTokenStore()
    let settings = SettingsStore()

    private var monitor: HeartRateMonitor?
    private var pollTask: Task<Void, Never>?

    func start() {
        startBLE()
        startCloudPolling()
    }

    private func startBLE() {
        monitor = HeartRateMonitor(
            onBPM: { [weak self] bpm in
                Task { @MainActor in self?.store.updateHR(bpm) }
            },
            onConnected: { [weak self] connected in
                Task { @MainActor in
                    if !connected { self?.store.hrDisconnected() }
                }
            })
    }

    func startCloudPolling() {
        pollTask?.cancel()
        guard let creds = tokenStore.load() else {
            store.cloudFailed("No Zepp token")
            return
        }
        let client = ZeppCloudClient(http: URLSession.shared, creds: creds)
        let interval = settings.refreshSeconds
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce(client)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func pollOnce(_ client: ZeppCloudClient) async {
        do {
            let m = try await client.fetchMetrics()
            store.updateCloud(stress: m.stress, readiness: m.readiness, at: Date())
        } catch {
            store.cloudFailed("\(error)")
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `cd /Users/tirth/Desktop/Projects/HelioBar && xcodegen generate && xcodebuild -scheme HelioBar -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add HelioBarApp/SettingsStore.swift HelioBarApp/AppModel.swift
git commit -m "feat: wire BLE + cloud polling into HealthStore via AppModel"
```

---

### Task 11: Dropdown UI (MenuContentView) with all states

**Files:**
- Create: `HelioBarApp/Views/MenuContentView.swift`

- [ ] **Step 1: Write the view**

`HelioBarApp/Views/MenuContentView.swift`:
```swift
import SwiftUI
import HelioCore

struct MenuContentView: View {
    let store: HealthStore
    var onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            hrRow
            Divider()
            cloudRows
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 240)
    }

    private var hrRow: some View {
        HStack {
            Image(systemName: "heart.fill").foregroundStyle(.red)
            Text(store.liveHR.map { "\($0) bpm" } ?? "—")
                .font(.title3).bold()
                .opacity(store.hrStatus == .stale ? 0.5 : 1)
            Spacer()
            hrStatusBadge
        }
    }

    @ViewBuilder private var hrStatusBadge: some View {
        switch store.hrStatus {
        case .live:  Label("live", systemImage: "circle.fill")
                        .foregroundStyle(.green).labelStyle(.titleAndIcon).font(.caption)
        case .stale: Label("reconnecting", systemImage: "circle.fill")
                        .foregroundStyle(.secondary).font(.caption)
        case .idle:  Text("enable Heart Rate Push").font(.caption).foregroundStyle(.secondary)
        case .error(let m): Text(m).font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var cloudRows: some View {
        if case .error(let m) = store.cloudStatus {
            Button(action: onSettings) {
                Label("⚠ Re-connect Zepp (\(m))", systemImage: "exclamationmark.triangle")
                    .font(.caption)
            }.buttonStyle(.plain)
        } else {
            metricRow("Stress", store.stress.map { "\($0.value)  (\($0.label))" })
            metricRow("Readiness", store.readiness.map { "\($0.value)" })
        }
    }

    private func metricRow(_ name: String, _ value: String?) -> some View {
        HStack {
            Text(name).foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—")
        }.font(.callout)
    }

    private var footer: some View {
        HStack {
            Text(syncText).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Settings…", action: onSettings)
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    private var syncText: String {
        guard let last = store.lastSync else { return "not synced" }
        let mins = Int(Date().timeIntervalSince(last) / 60)
        return mins <= 0 ? "synced just now" : "synced \(mins)m ago"
    }
}

#Preview("live") {
    let s = HealthStore()
    s.updateHR(72)
    s.updateCloud(stress: .init(value: 34, label: "Relaxed"),
                  readiness: .init(value: 81), at: Date())
    return MenuContentView(store: s, onSettings: {})
}

#Preview("no token / dropped") {
    let s = HealthStore()
    s.hrDisconnected()
    s.cloudFailed("401")
    return MenuContentView(store: s, onSettings: {})
}
```

- [ ] **Step 2: Build**

Run: `cd /Users/tirth/Desktop/Projects/HelioBar && xcodegen generate && xcodebuild -scheme HelioBar -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual verification (previews)**

Open `MenuContentView.swift` in Xcode, open the Canvas (Editor ▸ Canvas). Confirm both previews render: "live" shows 72 bpm + green live + Stress/Readiness; "no token" shows dimmed "—", reconnecting, and the re-connect warning.

- [ ] **Step 4: Commit**

```bash
git add HelioBarApp/Views/MenuContentView.swift
git commit -m "feat: dropdown UI with all data states"
```

---

### Task 12: Settings UI (token entry, interval, launch-at-login)

**Files:**
- Create: `HelioBarApp/Views/SettingsView.swift`

- [ ] **Step 1: Write the view**

`HelioBarApp/Views/SettingsView.swift`:
```swift
import SwiftUI
import ServiceManagement
import HelioCore

struct SettingsView: View {
    let model: AppModel

    @State private var token = ""
    @State private var host = ""
    @State private var interval: Double
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var saved = false

    init(model: AppModel) {
        self.model = model
        _interval = State(initialValue: model.settings.refreshSeconds)
    }

    var body: some View {
        Form {
            Section("Zepp account") {
                TextField("apptoken", text: $token)
                TextField("API host (e.g. api-mifit-us2.zepp.com)", text: $host)
                Button("Save token") { saveToken() }
                if saved { Text("Saved ✓").foregroundStyle(.green).font(.caption) }
            }
            Section("Cloud refresh") {
                Slider(value: $interval, in: 60...900, step: 60) {
                    Text("Every \(Int(interval/60)) min")
                }
                .onChange(of: interval) { _, new in
                    model.settings.refreshSeconds = new
                }
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunch(on) }
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            if let c = model.tokenStore.load() { token = c.appToken; host = c.host }
        }
    }

    private func saveToken() {
        try? model.tokenStore.save(ZeppCredentials(appToken: token, host: host))
        model.startCloudPolling()    // re-arm with new creds
        saved = true
    }

    private func setLaunch(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { launchAtLogin = !on }   // revert on failure
    }
}
```

- [ ] **Step 2: Build**

Run: `cd /Users/tirth/Desktop/Projects/HelioBar && xcodegen generate && xcodebuild -scheme HelioBar -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/Views/SettingsView.swift
git commit -m "feat: settings UI for token, interval, launch-at-login"
```

---

### Task 13: Final app assembly

**Files:**
- Modify: `HelioBarApp/HelioBarApp.swift`

- [ ] **Step 1: Replace the app entry with the real wiring**

`HelioBarApp/HelioBarApp.swift`:
```swift
import SwiftUI

@main
struct HelioBarApp: App {
    @State private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: model.store) {
                openWindow(id: "settings")
            }
            .task { model.start() }
        } label: {
            Label(barTitle, systemImage: "heart.fill")
        }
        .menuBarExtraStyle(.window)

        Window("HelioBar Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }

    private var barTitle: String {
        model.store.liveHR.map { "\($0)" } ?? "–"
    }
}
```

- [ ] **Step 2: Build**

Run: `cd /Users/tirth/Desktop/Projects/HelioBar && xcodegen generate && xcodebuild -scheme HelioBar -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual end-to-end verification**

1. In the Zepp phone app: Device ▸ Helio Strap ▸ Health Monitoring ▸ enable **Heart Rate Push**.
2. Launch HelioBar (`open` the built `.app`). Approve the Bluetooth permission prompt.
3. Within ~30s the menu bar number should start updating with your live BPM; dropdown shows green "live".
4. Open Settings, paste your captured `apptoken` + host, Save. Within the refresh interval the dropdown should show Stress + Readiness and "synced …".
5. Toggle Launch at login; confirm it persists after relaunch.

Record results in the commit message.

- [ ] **Step 4: Commit**

```bash
git add HelioBarApp/HelioBarApp.swift
git commit -m "feat: assemble full HelioBar menu bar app"
```

---

### Task 14: Token-capture guide

**Files:**
- Create: `docs/token-capture.md`

- [ ] **Step 1: Write the guide**

`docs/token-capture.md`:
```markdown
# Capturing your Zepp apptoken

The Zepp cloud API has no password login, so HelioBar needs the `apptoken`
header the official app sends.

## Option A — HTTP Toolkit (no root)
1. Install HTTP Toolkit (free) on your computer.
2. Start "Intercept" for your phone (follow its Wi-Fi/cert steps).
3. Open the Zepp app, pull-to-refresh your data.
4. In HTTP Toolkit, find a request to a `*.zepp.com` / `*.huami.com` host.
5. Copy the `apptoken` request header value and the request **host**.
6. Paste both into HelioBar ▸ Settings.

## Option B — rooted Android
Read `apptoken` from:
`/data/data/com.huami.watch.hmwatchmanager/shared_prefs/hm_id_sdk_android.xml`

## Calibrating endpoints
The exact stress/readiness path in `ZeppCloudClient.makeRequest` and the JSON
shape in `decode` are placeholders. Compare a real captured response and adjust
both to match. Tests in `ZeppCloudClientTests` pin the parsing contract.
```

- [ ] **Step 2: Commit**

```bash
git add docs/token-capture.md
git commit -m "docs: how to capture the Zepp apptoken"
```

---

## Final verification

- [ ] Run the whole core suite: `cd HelioCore && swift test` → all pass.
- [ ] Build the app: `cd .. && xcodegen generate && xcodebuild -scheme HelioBar -destination 'platform=macOS' build` → BUILD SUCCEEDED.
- [ ] Manual end-to-end from Task 13, Step 3 confirmed on real hardware.

## Spec coverage map

- Live HR via BLE → Tasks 3, 9, 10, 13.
- Stress + readiness via cloud → Tasks 5, 10, 11.
- HealthStore single source of truth → Task 4.
- Menu bar UI + all degraded states → Tasks 11, 13.
- Token in Keychain + settings → Tasks 6, 8, 12.
- Permissions / LSUIElement / launch-at-login → Tasks 7, 12.
- Independent source failure → Tasks 4 (`cloudFailed` leaves HR), 11 (separate badges).
- Token-capture friction documented → Task 14.

**Out of v1 (per spec):** notch HUD, sleep/steps, history/charts, in-app login.
```
