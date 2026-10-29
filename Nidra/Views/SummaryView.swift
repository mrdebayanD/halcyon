import SwiftUI
import SwiftData

struct SummaryView: View {
    @Environment(\.modelContext) private var context
    @Environment(NightEngine.self) private var engine
    @Query(sort: \SleepSession.end, order: .reverse) private var sessions: [SleepSession]
    @AppStorage("sleepNeed") private var need = 480

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if isEvening && !engine.isArmed { bedtimeCard }
                    if let last = sessions.first {
                        let a = SleepAnalytics.analyze(last, context: context, need: need)
                        let recent = Array(sessions.dropFirst().prefix(14))
                        NavigationLink(value: last) { HeroCard(session: last, analysis: a, usual: usualSleep(recent)) }
                            .buttonStyle(.plain)
                        let hs = Story.highlights(session: last, analysis: a, recent: recent, need: need)
                        if !hs.isEmpty {
                            Text("Highlights").font(.title2.bold()).padding(.top, 8)
                            ForEach(hs) { HighlightCard(highlight: $0) }
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color.groupedBG)
            .navigationDestination(for: SleepSession.self) { NightReportView(session: $0) }
        }
    }

    private var isEvening: Bool {
        let h = Calendar.current.component(.hour, from: .now)
        return h >= 19 || h < 3
    }

    private func usualSleep(_ recent: [SleepSession]) -> Int? {
        guard recent.count >= 3 else { return nil }
        return Int(recent.map { Double($0.totalSleepMinutes) }.median ?? 0)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(title).font(.largeTitle.bold())
        }
        .padding(.top, 8)
    }

    private var title: String {
        guard let last = sessions.first else { return "Welcome" }
        if Calendar.current.isDateInToday(last.end) { return "Last night" }
        return last.end.formatted(.dateTime.weekday(.wide)) + " night"
    }

    private var bedtimeCard: some View {
        HStack(spacing: 14) {
            Dusk(pose: .sleep, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready for bed?").font(.headline)
                Text("Start listening. It stops on its own in the morning.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Start") { Task { await engine.arm() } }
                .buttonStyle(.borderedProminent)
                .tint(.accentSleep)
        }
        .card()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Dusk(pose: .awake, size: 130)
                .frame(maxWidth: .infinity)
            Text("Hi, I'm Dusk").font(.title3.bold())
            Text("Tonight, tap the bedtime reminder and put your phone down. I'll keep watch and have your first report ready in the morning.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Start listening") { Task { await engine.arm() } }
                    .buttonStyle(.borderedProminent).tint(.accentSleep)
                Button("Try sample nights") { DemoData.generate(nights: 14, context: context, need: need) }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .card(padding: 20)
    }
}

struct HeroCard: View {
    let session: SleepSession
    let analysis: NightAnalysis
    let usual: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                ScoreRing(score: analysis.score)
                ScoreLegend(score: analysis.score)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Asleep").font(.footnote).foregroundStyle(.secondary)
                    Text(hm(session.totalSleepMinutes)).font(.rounded(22))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text("In bed").font(.footnote).foregroundStyle(.secondary)
                    Text("\((session.lightsOut ?? session.start).shortTime) – \(session.end.shortTime)")
                        .font(.headline).padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 6) {
                StageBar(deep: session.deepMinutes, light: session.lightMinutes, rem: session.remMinutes, awake: session.awakeMinutes)
                HStack {
                    Text("Awake \(hm(session.awakeMinutes))"); Spacer()
                    Text("REM \(hm(session.remMinutes))"); Spacer()
                    Text("Core \(hm(session.lightMinutes))"); Spacer()
                    Text("Deep \(hm(session.deepMinutes))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(Story.line(session: session, analysis: analysis, usualSleep: usual))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 18)
        .contentShape(Rectangle())
    }
}

struct HighlightCard: View {
    let highlight: Highlight

    private var tint: Color {
        switch highlight.kind {
        case .regular: .regularTint
        case .snoring: .snoreTint
        case .talking: .talkTint
        default: .accentSleep
        }
    }

    private var symbol: String {
        switch highlight.kind {
        case .regular: "calendar"
        case .snoring: "waveform"
        case .talking: "quote.bubble.fill"
        case .debt: "hourglass"
        case .short: "clock"
        case .latency: "moon.zzz"
        case .great: "star.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(highlight.title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            HStack(spacing: 12) {
                Text(highlight.body)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let clip = highlight.clip { ClipButton(file: clip, tint: tint) }
                if highlight.kind == .great || highlight.kind == .regular { Dusk(pose: .proud, size: 56) }
            }
        }
        .card()
    }
}
