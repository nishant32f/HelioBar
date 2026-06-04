# Repository Guidelines

## Project Structure & Module Organization

HelioBar is a native macOS menu bar app written in Swift. App code lives in `HelioBarApp/`: lifecycle code in `HelioBarApp.swift`, UI state in `AppModel.swift`, Bluetooth in `HeartRateMonitor.swift`, and SwiftUI views under `HelioBarApp/Views/`. App metadata and sandbox permissions are in `HelioBarApp/Resources/`.

Core logic is in the Swift package at `HelioCore/`, with sources in `HelioCore/Sources/HelioCore/` and tests in `HelioCore/Tests/HelioCoreTests/`. Root `Package.swift` builds the command-line-tools-compatible executable. `project.yml` defines the optional XcodeGen project. Utility scripts are in `scripts/`.

## Build, Test, and Development Commands

- `swift build -c release`: builds the app executable.
- `./scripts/install-and-run.sh`: builds, creates `~/Applications/HelioBar.app`, ad-hoc signs it, and launches it.
- `./scripts/uninstall.sh`: removes the installed app bundle.
- `cd HelioCore && swift test`: runs the logic test suite.
- `brew install xcodegen && xcodegen generate`: creates an Xcode project from `project.yml`.
- `xcodebuild -scheme HelioBar -configuration Release -derivedDataPath build build`: builds the Xcode project.

## Coding Style & Naming Conventions

Use standard Swift style: four-space indentation, `PascalCase` for types, and `camelCase` for properties, methods, and locals. Keep UI state in `AppModel` or `HelioCore` models. Prefer small SwiftUI views in `HelioBarApp/Views/`, and keep CoreBluetooth isolated in `HeartRateMonitor`.

No formatter or linter is configured. Keep imports minimal and avoid unrelated formatting churn.

## Testing Guidelines

Tests use XCTest through Swift Package Manager. Add tests for parsing, zone math, alert timing, and store behavior in `HelioCore/Tests/HelioCoreTests/`. Name tests with the existing `test_behaviorUnderCondition` pattern, for example `test_firesOnceAfterDuration`.

Run `cd HelioCore && swift test` before opening a PR. For UI or Bluetooth changes, also run `./scripts/install-and-run.sh` and verify launch, Bluetooth prompts, and menu bar behavior on macOS 14+.

## Commit & Pull Request Guidelines

History uses concise conventional commits, such as `feat: add command line tools install flow`, `fix: open Settings via self-managed NSWindow`, and `docs: add README`. Follow that lowercase type-prefix style: `feat:`, `fix:`, `docs:`, `test:`, or `chore:`.

Pull requests should include a short summary, testing performed, and user-visible changes. Link related issues when available. Include screenshots for menu content, settings, or visual changes. Mention Bluetooth or permission impacts because macOS permission state is tied to the installed app bundle path.

## Security & Configuration Tips

Do not add cloud integrations or account-based telemetry without explicit project direction; the app reads local BLE heart-rate broadcasts only. Keep sandbox entitlements minimal in `HelioBarApp/Resources/HelioBar.entitlements`, and preserve the stable install path used by permissions and launch-at-login registration.
