import SwiftUI
import Charts

// MARK: - Score ring split into its five parts

struct ScoreRing: View {
    let score: SleepScore
    var size: CGFloat = 132
    var lineWidth: CGFloat = 11
    var animated = true
    @State private var progress: Double
    @State private var shown: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(score: SleepScore, size: CGFloat = 132, lineWidth: CGFloat = 11, animated: Bool = true) {
        self.score = score
        self.size = size
        self.lineWidth = lineWidth
        self.animated = animated
        _progress = State(initialValue: animated ? 0 : 1)
        _shown = State(initialValue: animated ? 0 : score.total)
    }

    private struct Segment: Identifiable {
        let part: ScorePart
        let start: Double
        let length: Double
        var id: String { part.id }
    }

    private var segments: [Segment] {
        let gap = 0.012
        let usable = 1 - gap * Double(score.parts.count)
        var cursor = 0.0
        var out: [Segment] = []
        for p in score.parts {
            let len = usable * p.max / 100
            out.append(Segment(part: p, start: cursor, length: len))
            cursor += len + gap
        }
        return out
    }

    var body: some View {
        ZStack {
            ForEach(segments) { seg in
                Circle()
                    .trim(from: seg.start, to: seg.start + seg.length)
                    .stroke(seg.part.kind.color.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth))
                Circle()
                    .trim(from: seg.start, to: seg.start + seg.length * seg.part.fraction * progress)
                    .stroke(seg.part.kind.color, style: StrokeStyle(lineWidth: lineWidth))
            }
            .rotationEffect(.degrees(-90))
            .padding(lineWidth / 2)
            VStack(spacing: 0) {
                Text("\(shown)")
                    .font(.rounded(size * 0.3))
                    .contentTransition(.numericText(value: Double(shown)))
                Text(score.grade)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep score \(score.total) of 100, \(score.grade)")
        .onAppear { reveal() }
        .onChange(of: score.total) { _, _ in reveal() }
    }

    private func reveal() {
        guard animated else { return }
        if reduceMotion { progress = 1; shown = score.total; return }
        progress = 0
        shown = 0
        withAnimation(.easeOut(duration: 1.1)) { progress = 1 }
        withAnimation(.easeOut(duration: 0.9)) { shown = score.total }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
    }
}

struct ScoreLegend: View {
    let score: SleepScore
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(score.parts) { p in
                HStack(spacing: 8) {
                    Circle().fill(p.kind.color).frame(width: 8, height: 8)
                    Text(p.name).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text("\(Int(p.points))/\(Int(p.max))").fontWeight(.semibold).monospacedDigit()
                }
                .font(.footnote)
            }
        }
    }
}

// MARK: - Stage bar

struct StageBar: View {
    let deep: Int, light: Int, rem: Int, awake: Int
    var height: CGFloat = 10
    var body: some View {
        GeometryReader { geo in
            let total = CGFloat(max(1, deep + light + rem + awake))
            let items: [(SleepStage, Int)] = [(.awake, awake), (.rem, rem), (.light, light), (.deep, deep)]
            HStack(spacing: 2) {
                ForEach(items, id: \.0) { item in
                    if item.1 > 0 {
                        Rectangle().fill(item.0.color)
                            .frame(width: max(2, (geo.size.width - 6) * CGFloat(item.1) / total))
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

// MARK: - Stage chart with event pins

struct StageChart: View {
    let samples: [MinuteSample]
    let events: [NightEvent]
    @Binding var selected: Date?
    @State private var reveal: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var segments: [StageSegment] { StageSegment.build(from: samples) }
    private var pins: [NightEvent] { events.filter { [.snoring, .talking, .cough, .awake].contains($0.kind) } }

    var body: some View {
        Chart {
            ForEach(segments) { seg in
                RectangleMark(xStart: .value("Start", seg.start), xEnd: .value("End", seg.end),
                              yStart: .value("Low", Double(seg.stage.rawValue) - 0.36),
                              yEnd: .value("High", Double(seg.stage.rawValue) + 0.36))
                    .foregroundStyle(seg.stage.color)
                    .cornerRadius(4)
            }
            ForEach(pins) { e in
                PointMark(x: .value("Time", e.start), y: .value("Row", 4.25))
                    .symbolSize(70)
                    .foregroundStyle(e.kind == .awake ? Color.secondary : e.kind.tint)
            }
            if let selected {
                RuleMark(x: .value("Selected", selected))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: -0.6...4.7)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, 1.0, 2.0, 3.0]) { v in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel {
                    if let d = v.as(Double.self), let st = SleepStage(rawValue: Int(d.rounded())) {
                        Text(st.label).font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartXSelection(value: $selected)
        .frame(height: 190)
        .mask(alignment: .leading) {
            GeometryReader { geo in Rectangle().frame(width: geo.size.width * reveal) }
        }
        .onAppear {
            if reduceMotion { reveal = 1 } else { withAnimation(.easeInOut(duration: 1.2)) { reveal = 1 } }
        }
        .accessibilityLabel("Sleep stages through the night")
    }
}

// MARK: - Timeline row

struct EventRow: View {
    let event: NightEvent
    var body: some View {
        HStack(spacing: 12) {
            Text(event.start.shortTime)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Image(systemName: event.kind.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(event.kind.tint)
                .frame(width: 30, height: 30)
                .background(event.kind.tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                if let note = event.note { Text(note).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            if let clip = event.clipFile, ClipStore.exists(clip) {
                ClipButton(file: clip, tint: event.kind.tint)
            }
        }
        .padding(.vertical, 6)
    }

    private var title: String {
        switch event.kind {
        case .snoring, .awake: "\(event.kind.title) · \(event.minutes) min"
        default: event.kind.title
        }
    }
}

struct ClipButton: View {
    let file: String
    var tint: Color = .accentSleep
    @State private var player = ClipPlayer.shared

    var body: some View {
        Button {
            player.toggle(file)
        } label: {
            Image(systemName: player.playing == file ? "stop.fill" : "play.fill")
                .font(.footnote)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.14), in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.playing == file ? "Stop clip" : "Play clip")
    }
}

// MARK: - Dusk, the nightjar mascot

struct Dusk: View {
    enum Pose: String { case sleep = "DuskSleep", awake = "DuskAwake", nudge = "DuskNudge", proud = "DuskProud" }
    let pose: Pose
    var size: CGFloat = 120
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(pose.rawValue)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .scaleEffect(breathe ? (pose == .sleep ? 1.035 : 1.02) : 1, anchor: .bottom)
            .rotationEffect(.degrees(pose == .awake && breathe ? -2 : 0), anchor: .bottom)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: pose == .sleep ? 2.6 : 1.4).repeatForever(autoreverses: true)) { breathe = true }
            }
            .accessibilityLabel(label)
    }

    private var label: String {
        switch pose {
        case .sleep: "Dusk the nightjar, asleep"
        case .awake: "Dusk the nightjar, waving"
        case .nudge: "Dusk the nightjar, giving you a look"
        case .proud: "Dusk the nightjar, proud of you"
        }
    }
}
