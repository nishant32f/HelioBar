# HelioBar Feature Expansion Plan

## Goal

Add useful Helio Strap metrics without weakening the app's local-first posture.
The app should stay sandboxed, avoid cloud credentials by default, and show only
metrics that are either observed from BLE or clearly labeled as imported.

## Capability Discovery Baseline

The app now discovers all BLE services and characteristics after connecting to
the Heart Rate service. The menu shows:

- Connected device name.
- Battery level when the standard Battery service is exposed.
- Supported metric chips for heart rate, RR intervals, battery, and device info.
- A compact service summary with characteristic counts.

This tells us what the strap actually exposes to macOS before we plan deeper
features around unsupported assumptions.

## Feature Tracks

### Track 1: Local BLE Features

These keep the app simple and private.

- Battery level: read standard BLE Battery Service `180F` / Battery Level `2A19`
  when present.
- RR interval detection: mark RR available only after a Heart Rate Measurement
  packet includes RR interval data.
- HRV estimate: if RR is present, compute rolling RMSSD and show it as
  "Local HRV". If RR is absent, keep the UI disabled and explain "not broadcast".
- Heart-rate recovery: add a recovery session that records BPM drop over three
  minutes after a high-HR period or a manual "Start recovery" action.
- Resting HR estimate: compute a local estimate from low-variance, low-HR windows
  and label it "estimated" unless imported from Zepp/Apple Health.

### Track 2: Local UX Features

- CSV/JSON export for session samples, zones, battery readings, and recovery
  sessions.
- Menubar compact modes: BPM only, BPM + trend, BPM + battery.
- Alert refinements: separate high-HR, low-battery, reconnect, and recovery
  completion notifications.
- Bluetooth troubleshooting view: show whether Heart Rate Push is live, whether
  Battery was seen, and when the last sample arrived.

### Track 3: Imported Health Features

These need an explicit import path and should not be presented as direct BLE.

- Sleep duration, stages, and sleep score.
- HRV from sleep summaries.
- Resting HR from daily summaries.
- SpO2 / blood oxygen.
- Stress.
- PAI.
- BioCharge / Body Battery.
- Exertion / training load.

Preferred import order:

1. Apple Health read-only import if Zepp syncs the metric there.
2. Manual CSV/JSON import if Zepp exports it.
3. Zepp API/cloud only with explicit user approval, clear credential handling,
   and a separate security review.

## UI Proposal

### Menu Header

- Keep the live BPM as the primary line.
- Add a tiny device subline only when useful: device name, battery, connection
  status.
- Keep zone color and trend arrow in the menubar title.

### Main Menu Body

- Chart remains the main visual.
- Add a compact "Capabilities" strip below the zone bar:
  - Red heart: live HR.
  - Pink ECG: RR intervals.
  - Green battery: battery service.
  - Blue info: device information service.
- Use disabled chips for capabilities not yet observed instead of hiding them.

### New Tabs

Use segmented controls once there is enough data:

- Live: BPM chart, zones, recent stats.
- Recovery: three-minute heart-rate recovery run and history.
- Insights: resting estimate, HRV if available, imported health metrics.
- Device: BLE capability table, battery, troubleshooting, export.

### Settings

- Add "Menubar display" segmented control.
- Add import source toggles only after an import path exists.
- Keep Launch at Login and Bluetooth controls in Settings.

## Safety Rules

- Do not add network entitlement unless a Zepp/cloud integration is approved.
- Do not store Zepp credentials without a dedicated Keychain implementation.
- Keep app sandbox and Bluetooth entitlement signing in the install script.
- Label inferred metrics as estimated.
- Label imported metrics by source.

## Next Implementation Order

1. Finish BLE capability UI and verify on the actual strap.
2. Add battery history if Battery service is present.
3. Add HR recovery mode because it only needs live BPM.
4. Add RR/HRV only if RR packets are actually seen.
5. Add export.
6. Decide whether Apple Health import is worth adding.
