import SwiftUI
import HelioCore

/// Guided breathing with live HR biofeedback — watch your HR settle as you slow down.
struct BreathingView: View {
    let store: HealthStore
    @State private var inhaling = false
    @State private var startHR: Int?
    @State private var lowHR: Int?
    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            Text(inhaling ? "Inhale…" : "Exhale…")
                .font(.headline).foregroundStyle(.secondary)
            ZStack {
                Circle().fill(.blue.opacity(0.15))
                Circle().stroke(.blue, lineWidth: 2)
            }
            .frame(width: inhaling ? 180 : 90, height: inhaling ? 180 : 90)
            .animation(.easeInOut(duration: 4), value: inhaling)

            VStack(spacing: 2) {
                Text(store.liveHR.map { "\($0) bpm" } ?? "—")
                    .font(.system(size: 28, weight: .bold)).monospacedDigit()
                if let s = startHR, let l = lowHR {
                    Text("start \(s) · low \(l) · ↓\(Swift.max(0, s - l))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 260, height: 330)
        .padding()
        .onAppear { startHR = store.liveHR; lowHR = store.liveHR; inhaling = true }
        .onReceive(timer) { _ in inhaling.toggle() }
        .onChange(of: store.liveHR) { _, hr in
            guard let hr else { return }
            if startHR == nil { startHR = hr }
            lowHR = Swift.min(lowHR ?? hr, hr)
        }
    }
}
