import SwiftUI
import HelioCore

/// Guided breathing with live HR biofeedback — shown inline in the dropdown.
struct BreathingView: View {
    let store: HealthStore
    var onClose: () -> Void

    @State private var inhaling = false
    @State private var startHR: Int?
    @State private var lowHR: Int?
    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Breathe")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .liquidGlassButton()
                .help("Done")
                .accessibilityLabel("Done")
            }

            Text(inhaling ? "Inhale…" : "Exhale…")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .fill(.blue.opacity(0.18))
                    .blur(radius: 0.5)
                Circle()
                    .stroke(.white.opacity(0.58), lineWidth: 1)
                Circle()
                    .stroke(.blue.opacity(0.85), lineWidth: 2)
            }
            .frame(width: inhaling ? 150 : 80, height: inhaling ? 150 : 80)
            .liquidGlassInset(cornerRadius: 80)
            .animation(.easeInOut(duration: 4), value: inhaling)
            .frame(height: 160)   // reserve space so the popover doesn't jump

            VStack(spacing: 2) {
                Text(store.liveHR.map { "\($0) bpm" } ?? "—")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if let s = startHR, let l = lowHR {
                    Text("Start \(s) · Low \(l) · ↓\(Swift.max(0, s - l))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .liquidGlassInset(cornerRadius: 14)
        }
        .onAppear { startHR = store.liveHR; lowHR = store.liveHR; inhaling = true }
        .onReceive(timer) { _ in inhaling.toggle() }
        .onChange(of: store.liveHR) { _, hr in
            guard let hr else { return }
            if startHR == nil { startHR = hr }
            lowHR = Swift.min(lowHR ?? hr, hr)
        }
    }
}
