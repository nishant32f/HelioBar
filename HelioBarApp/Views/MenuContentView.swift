import SwiftUI
import HelioCore

struct MenuContentView: View {
    let store: HealthStore
    var onSettings: () -> Void
    @State private var breathing = false

    var body: some View {
        LiquidGlassContainer {
            VStack(alignment: .leading, spacing: 9) {
                if breathing {
                    BreathingView(store: store) { breathing = false }
                } else {
                    hrRow
                    HeartRateChart(points: store.recentPoints, maxHR: store.maxHR)
                        .frame(height: 78)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .liquidGlassInset(cornerRadius: 12)
                    statsRow
                    zoneBar
                    footer
                }
            }
            .padding(12)
            .frame(width: 276)
        }
    }

    private var hrRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill").foregroundStyle(.red)
            Text(store.liveHR.map { "\($0) bpm" } ?? "—")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .opacity(store.hrStatus == .stale ? 0.5 : 1)
            if let p = store.percentMax {
                Text("\(p)%").font(.caption).foregroundStyle(.secondary)
            }
            if let t = store.hrTrend { trendIcon(t) }
            Spacer()
            badge
        }
    }

    @ViewBuilder private func trendIcon(_ t: HealthStore.Trend) -> some View {
        switch t {
        case .rising:  Image(systemName: "arrow.up.right").foregroundStyle(.orange)
        case .falling: Image(systemName: "arrow.down.right").foregroundStyle(.blue)
        case .steady:  Image(systemName: "arrow.right").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var badge: some View {
        switch store.hrStatus {
        case .live:
            Label("Live", systemImage: "circle.fill").foregroundStyle(.green).font(.caption)
        case .stale:
            Label("Reconnecting", systemImage: "circle.fill").foregroundStyle(.secondary).font(.caption)
        case .idle:
            Text("Enable heart rate push").font(.caption).foregroundStyle(.secondary)
        case .error(let m):
            Text(m).font(.caption).foregroundStyle(.orange)
        }
    }

    private var statsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recentStatsLabel)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                stat("Min", store.recentMin)
                stat("Avg", store.recentAvg)
                stat("Max", store.recentMax)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func stat(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value.map(String.init) ?? "—")
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(statColor(value))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var zoneBar: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach([HRZone.resting, .elevated, .high], id: \.self) { z in
                    Rectangle()
                        .fill(zoneColor(z))
                        .frame(width: max(0, geo.size.width * store.zoneFraction(z)))
                }
            }
        }
        .frame(height: 7)
        .clipShape(Capsule())
        .opacity(store.zoneCounts.isEmpty ? 0.15 : 1)
        .shadow(color: zoneShadow.opacity(0.35), radius: 8, y: 2)
    }

    private func zoneColor(_ z: HRZone) -> Color {
        switch z { case .resting: return .green; case .elevated: return .orange; case .high: return .red }
    }

    private func statColor(_ value: Int?) -> Color {
        guard let value else { return .secondary }
        return zoneColor(HRZone.zone(for: value, maxHR: store.maxHR))
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }

    private var recentStatsLabel: String {
        "Last \(durationLabel(HealthStore.recentWindow))"
    }

    private var footer: some View {
        HStack(spacing: 8) {
            iconButton("Reset", systemImage: "arrow.counterclockwise") { store.resetSession() }
            iconButton("Breathe", systemImage: "wind") { breathing = true }
            Spacer()
            iconButton("Settings", systemImage: "gearshape", action: onSettings)
            iconButton("Quit", systemImage: "power", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var zoneShadow: Color {
        switch store.hrZone {
        case .resting: return .green
        case .elevated: return .orange
        case .high: return .red
        case nil: return .secondary
        }
    }

    private func iconButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .liquidGlassButton()
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Compact heart-rate chart with axes, labels, and the latest sample marker.
private struct HeartRateChart: View {
    let points: [HeartRatePoint]
    let maxHR: Int
    private let axisMin = 60.0
    private let timeWindow = HealthStore.recentWindow

    var body: some View {
        GeometryReader { geo in
            let values = points.map(\.bpm)
            if values.count >= 2 {
                let lo = axisMin
                let hi = axisUpperBound(for: values)
                let range = Swift.max(hi - lo, 1)
                let yAxisWidth: CGFloat = 22
                let xAxisHeight: CGFloat = 16
                let topInset: CGFloat = 4
                let rightInset: CGFloat = 5
                let plotWidth = Swift.max(1, geo.size.width - yAxisWidth - rightInset)
                let plotHeight = Swift.max(1, geo.size.height - topInset - xAxisHeight)
                let ticks = axisTicks(upperBound: hi)
                let latestTimestamp = points.last?.timestamp ?? Date()
                let windowStart = latestTimestamp.addingTimeInterval(-timeWindow)
                let plotRect = CGRect(x: yAxisWidth, y: topInset, width: plotWidth, height: plotHeight)

                ZStack(alignment: .topLeading) {
                    plotSurface(in: plotRect)

                    ForEach(zoneBands(upperBound: hi), id: \.zone) { band in
                        let top = yFor(band.upper, lo: lo, range: range, topInset: topInset, plotHeight: plotHeight)
                        let bottom = yFor(band.lower, lo: lo, range: range, topInset: topInset, plotHeight: plotHeight)
                        Rectangle()
                            .fill(zoneColor(band.zone).opacity(0.09))
                            .frame(width: plotWidth, height: Swift.max(0, bottom - top))
                            .position(x: yAxisWidth + plotWidth / 2, y: top + (bottom - top) / 2)
                    }

                    ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                        let y = yFor(tick, lo: lo, range: range, topInset: topInset, plotHeight: plotHeight)
                        Path { p in
                            p.move(to: CGPoint(x: yAxisWidth, y: y))
                            p.addLine(to: CGPoint(x: yAxisWidth + plotWidth, y: y))
                        }
                        .stroke(.secondary.opacity(0.16), lineWidth: 0.6)

                        Text("\(Int(tick.rounded()))")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: yAxisWidth - 3, alignment: .trailing)
                            .position(x: (yAxisWidth - 3) / 2, y: y)
                    }

                    Path { p in
                        p.move(to: CGPoint(x: yAxisWidth, y: topInset))
                        p.addLine(to: CGPoint(x: yAxisWidth, y: topInset + plotHeight))
                        p.addLine(to: CGPoint(x: yAxisWidth + plotWidth, y: topInset + plotHeight))
                    }
                    .stroke(.secondary.opacity(0.32), lineWidth: 0.8)

                    ForEach(segmentIndices, id: \.self) { index in
                        segmentPath(
                            from: points[index - 1],
                            to: points[index],
                            lo: lo,
                            range: range,
                            windowStart: windowStart,
                            originX: yAxisWidth,
                            topInset: topInset,
                            plotWidth: plotWidth,
                            plotHeight: plotHeight
                        )
                        .stroke(
                            zoneColor(for: points[index].bpm),
                            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: zoneColor(for: points[index].bpm).opacity(0.42), radius: 3)
                    }

                    ForEach(highPointIndices, id: \.self) { index in
                        let sample = points[index]
                        Circle()
                            .fill(.red)
                            .frame(width: 3.5, height: 3.5)
                            .shadow(color: .red.opacity(0.55), radius: 3)
                            .position(
                                x: xFor(sample.timestamp, windowStart: windowStart, originX: yAxisWidth, plotWidth: plotWidth),
                                y: yFor(Double(sample.bpm), lo: lo, range: range, topInset: topInset, plotHeight: plotHeight)
                            )
                    }

                    if let last = points.last {
                        let x = xFor(
                            last.timestamp,
                            windowStart: windowStart,
                            originX: yAxisWidth,
                            plotWidth: plotWidth
                        )
                        let y = yFor(Double(last.bpm), lo: lo, range: range, topInset: topInset, plotHeight: plotHeight)
                        let color = zoneColor(for: last.bpm)
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                            .shadow(color: color.opacity(0.65), radius: 5)
                            .position(x: x, y: y)
                    }

                    Text("BPM")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .position(x: yAxisWidth / 2, y: geo.size.height - 5)

                    Text("-5m")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.secondary)
                        .position(x: yAxisWidth + 16, y: geo.size.height - 5)

                    Text("Now")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .position(x: yAxisWidth + plotWidth - 11, y: geo.size.height - 5)
                }
            } else {
                emptyChart
            }
        }
    }

    private var segmentIndices: [Int] {
        points.count > 1 ? Array(1..<points.count) : []
    }

    private var highPointIndices: [Int] {
        points.indices.filter { HRZone.zone(for: points[$0].bpm, maxHR: maxHR) == .high }
    }

    private func zoneBands(upperBound: Double) -> [ZoneBand] {
        let restingUpper = Double(maxHR) * 0.60
        let elevatedUpper = Double(maxHR) * 0.80
        return [
            ZoneBand(zone: .resting, lower: axisMin, upper: Swift.min(upperBound, restingUpper)),
            ZoneBand(zone: .elevated, lower: Swift.max(axisMin, restingUpper), upper: Swift.min(upperBound, elevatedUpper)),
            ZoneBand(zone: .high, lower: Swift.max(axisMin, elevatedUpper), upper: upperBound),
        ].filter { $0.upper > $0.lower }
    }

    private func axisUpperBound(for values: [Int]) -> Double {
        let maxValue = values.max() ?? Int(axisMin)
        switch maxValue {
        case ...90: return 90
        case ...120: return 120
        case ...150: return 150
        default: return 180
        }
    }

    private func axisTicks(upperBound: Double) -> [Double] {
        switch upperBound {
        case 90:
            return [90, 75, 60]
        case 120:
            return [120, 105, 90, 75, 60]
        case 150:
            return [150, 120, 90, 60]
        default:
            return [180, 150, 120, 90, 60]
        }
    }

    private struct ZoneBand {
        let zone: HRZone
        let lower: Double
        let upper: Double
    }

    private func plotSurface(in rect: CGRect) -> some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.12), .white.opacity(0.03), .black.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    private var emptyChart: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 18) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(.secondary.opacity(0.12))
                        .frame(height: 0.6)
                }
            }
            Text("Collecting samples")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func xFor(
        _ timestamp: Date,
        windowStart: Date,
        originX: CGFloat,
        plotWidth: CGFloat
    ) -> CGFloat {
        let elapsed = timestamp.timeIntervalSince(windowStart)
        let fraction = Swift.max(0, Swift.min(1, elapsed / timeWindow))
        return originX + plotWidth * CGFloat(fraction)
    }

    private func yFor(
        _ value: Double,
        lo: Double,
        range: Double,
        topInset: CGFloat,
        plotHeight: CGFloat
    ) -> CGFloat {
        let fraction = Swift.max(0, Swift.min(1, (value - lo) / range))
        return topInset + plotHeight * CGFloat(1 - fraction)
    }

    private func zoneColor(for bpm: Int) -> Color {
        zoneColor(HRZone.zone(for: bpm, maxHR: maxHR))
    }

    private func zoneColor(_ zone: HRZone) -> Color {
        switch zone {
        case .resting: return .green
        case .elevated: return .orange
        case .high: return .red
        }
    }

    private func linePath(
        points: [HeartRatePoint],
        lo: Double,
        range: Double,
        windowStart: Date,
        originX: CGFloat,
        topInset: CGFloat,
        plotWidth: CGFloat,
        plotHeight: CGFloat
    ) -> Path {
        Path { p in
            for (i, sample) in points.enumerated() {
                let plotPoint = CGPoint(
                    x: xFor(sample.timestamp, windowStart: windowStart, originX: originX, plotWidth: plotWidth),
                    y: yFor(Double(sample.bpm), lo: lo, range: range, topInset: topInset, plotHeight: plotHeight)
                )
                if i == 0 { p.move(to: plotPoint) }
                else { p.addLine(to: plotPoint) }
            }
        }
    }

    private func segmentPath(
        from start: HeartRatePoint,
        to end: HeartRatePoint,
        lo: Double,
        range: Double,
        windowStart: Date,
        originX: CGFloat,
        topInset: CGFloat,
        plotWidth: CGFloat,
        plotHeight: CGFloat
    ) -> Path {
        Path { path in
            path.move(
                to: CGPoint(
                    x: xFor(start.timestamp, windowStart: windowStart, originX: originX, plotWidth: plotWidth),
                    y: yFor(Double(start.bpm), lo: lo, range: range, topInset: topInset, plotHeight: plotHeight)
                )
            )
            path.addLine(
                to: CGPoint(
                    x: xFor(end.timestamp, windowStart: windowStart, originX: originX, plotWidth: plotWidth),
                    y: yFor(Double(end.bpm), lo: lo, range: range, topInset: topInset, plotHeight: plotHeight)
                )
            )
        }
    }

}

struct LiquidGlassContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .liquidGlassSurface(cornerRadius: 22)
            .padding(1)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                    .background {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.white.opacity(0.04))
                    }
            }
            .padding(6)
    }
}

extension View {
    @ViewBuilder
    func liquidGlassSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(.white.opacity(0.08)), in: shape)
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
    }

    @ViewBuilder
    func liquidGlassInset(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(.clear.interactive(), in: shape)
        } else {
            self
                .background(.thinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 1))
        }
    }

    @ViewBuilder
    func liquidGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self
                .buttonStyle(.borderless)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
        }
    }
}

#if !SWIFT_PACKAGE
#Preview("live") {
    let s = HealthStore()
    let start = Date()
    [62,65,70,68,72,80,95,110,90,75,72,71].enumerated().forEach { index, bpm in
        s.updateHR(bpm, at: start.addingTimeInterval(Double(index * 5)))
    }
    return MenuContentView(store: s, onSettings: {})
}

#Preview("idle") {
    MenuContentView(store: HealthStore(), onSettings: {})
}
#endif
