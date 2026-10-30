import SwiftUI
import SwiftData
import Charts

struct NightReportView: View {
    @Bindable var session: SleepSession
    @Environment(\.modelContext) private var context
    @AppStorage("sleepNeed") private var need = 480
    @State private var selected: Date?

    var body: some View {
        let samples = session.samples
        let events = session.events
        let a = SleepAnalytics.analyze(session, context: context, need: need)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(a)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Sleep stages").font(.headline)
                        Spacer()
                        Text(session.hasMeasuredStages ? "Measured by Apple Watch" : "Estimated")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    StageChart(samples: samples, events: events, selected: $selected)
                    if let m = selectedMinute(samples) {
                        MinuteDetail(sample: m)
                    } else if let w = events.first(where: { $0.kind == .awake }) {
                        HStack(alignment: .top, spacing: 10) {
                            Text(w.start.shortTime).font(.footnote.weight(.semibold)).frame(width: 64, alignment: .leading)
                            Text("Awake for \(w.minutes) min\(w.phoneUsed ? " · phone picked up" : ""). Tracking carried on.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.groupedBG, in: RoundedRectangle(cornerRadius: 12))
                    }
                    legend
                }
                .card()

                stageList(a.metrics)

                if session.source != .appleWatch { breathingCard(samples: samples, events: events) }

                if !events.isEmpty {
                    Text("What happened").font(.title2.bold()).padding(.top, 8)
                    VStack(spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { i, e in
                            EventRow(event: e)
                            if i < events.count - 1 { Divider().padding(.leading, 76) }
                        }
                    }
                    .card(padding: 12)
                    Text("Clips stay on this iPhone and delete themselves after 30 days.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 6)
                }

                Text("How your score was built").font(.title2.bold()).padding(.top, 8)
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(a.score.parts) { p in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(p.name).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(Int(p.points)) of \(Int(p.max))").font(.subheadline).foregroundStyle(.secondary)
                            }
                            ProgressView(value: p.fraction).tint(p.kind.color)
                            Text(p.why).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .card()

                if samples.contains(where: { $0.heartRate != nil }) { heartCard(samples) }

                if !session.hasMeasuredStages {
                    Label("Wear your Apple Watch to bed to add measured stages, heart rate and HRV.", systemImage: "heart")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .card()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes").font(.headline)
                    TextField("Dreams, how you feel…", text: $session.note, axis: .vertical)
                        .lineLimit(2...6)
                }
                .card()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color.groupedBG)
        .navigationTitle(session.end.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let image = shareImage(a) {
                    ShareLink(item: image, preview: SharePreview("My night", image: image)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    // MARK: Pieces

    /// Listening coverage, snoring and possible breathing pauses.
    @ViewBuilder
    private func breathingCard(samples: [MinuteSample], events: [NightEvent]) -> some View {
        let listened = samples.filter { $0.noiseDB != nil }.count
        let inBed = max(1, samples.count)
        let snore = samples.filter { $0.snoreSeconds >= 3 }.count
        let pauses = events.filter { $0.kind == .breathingPause }.reduce(0) { $0 + ($1.count ?? 1) }
        let asleepHours = max(0.5, Double(samples.filter { $0.stage != .awake }.count) / 60)
        let perHour = Double(pauses) / asleepHours

        VStack(alignment: .leading, spacing: 12) {
            Text("Breathing and snoring").font(.headline)
            if listened == 0 {
                Label {
                    Text("Halcyon wasn't listening last night, so there's no snoring or breathing data. Start each night from the bedtime reminder or the Start button, and check that the microphone is allowed in Settings › \(AppInfo.name).")
                } icon: {
                    Image(systemName: "mic.slash").foregroundStyle(.orange)
                }
                .font(.subheadline)
            } else {
                let v = BreathingVerdict(session: session)
                verdictRow("Snored", v.snoreText, v.snored ? .snoreTint : .secondary, "waveform")
                verdictRow("Signs of sleep apnea", v.apneaText, v.apnea == .frequent ? .orange : .secondary, "lungs")
                if let advice = v.apneaAdvice {
                    Text(advice).font(.footnote.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                HStack(alignment: .top) {
                    stat("Listened", hm(listened), listened * 10 < inBed * 9 ? "of \(hm(inBed)) in bed" : nil)
                    stat("Snoring", snore == 0 ? "None" : hm(snore), nil)
                    stat("Possible pauses", "\(pauses)", pauses > 0 ? String(format: "%.1f an hour", perHour) : nil)
                }
                if listened * 10 < inBed * 9 {
                    Text("The microphone was off for part of the night, for example during a call, Siri or a headphone change. Halcyon restarts it on its own now.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Text("A possible pause is snoring that stops for 10 seconds or more and then comes back with a loud breath or snort, a pattern that can come with sleep apnea. Halcyon can't diagnose apnea. If you see pauses often, especially with daytime sleepiness, morning headaches or someone noticing you stop breathing, play the clips to a doctor and ask about a home sleep test.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    private func verdictRow(_ title: String, _ value: String, _ tint: Color, _ symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(tint == .secondary ? Color.primary : tint)
        }
        .font(.subheadline)
    }

    private func stat(_ title: String, _ value: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(value).font(.rounded(20))
            if let sub { Text(sub).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ a: NightAnalysis) -> some View {
        HStack(spacing: 14) {
            Text("\(a.score.total)")
                .font(.rounded(20))
                .frame(width: 56, height: 56)
                .background(Circle().stroke(Color.accentSleep, lineWidth: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(hm(session.totalSleepMinutes)) asleep").font(.title2.bold())
                Text("\((session.lightsOut ?? session.start).shortTime) – \(session.end.shortTime) · \(session.source.label)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(.snoreTint, "Snoring")
            legendItem(.talkTint, "Sleep talk")
            legendItem(.secondary, "Awake or cough")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) { Circle().fill(c).frame(width: 10, height: 10); Text(t) }
    }

    private func stageList(_ m: SleepMetrics) -> some View {
        VStack(spacing: 0) {
            ForEach([SleepStage.awake, .rem, .light, .deep]) { st in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3).fill(st.color).frame(width: 12, height: 12)
                    Text(st.label)
                    Spacer()
                    Text(hm(m.minutes(st))).fontWeight(.semibold).monospacedDigit()
                    Text(st == .awake
                         ? "\(Int(Double(m.minutes(st)) / Double(max(m.timeInBed, 1)) * 100))%"
                         : "\(Int(m.percentOfSleep(st).rounded()))%")
                        .foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
                }
                .frame(height: 50)
                if st != .deep { Divider() }
            }
        }
        .card(padding: 14)
    }

    private func heartCard(_ samples: [MinuteSample]) -> some View {
        let pts = samples.compactMap { s in s.heartRate.map { (s.time, $0) } }
        return VStack(alignment: .leading, spacing: 10) {
            Label("Heart rate", systemImage: "heart.fill").font(.headline).foregroundStyle(.pink)
            Chart(pts, id: \.0) { p in
                LineMark(x: .value("Time", p.0), y: .value("BPM", p.1))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.pink)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 130)
        }
        .card()
    }

    private func selectedMinute(_ samples: [MinuteSample]) -> MinuteSample? {
        guard let selected, let first = samples.first else { return nil }
        let i = Int(selected.timeIntervalSince(first.time) / 60)
        return samples.indices.contains(i) ? samples[i] : nil
    }

    @MainActor
    private func shareImage(_ a: NightAnalysis) -> Image? {
        let card = ShareCard(session: session, score: a.score).environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: card)
        r.scale = 3
        return r.uiImage.map { Image(uiImage: $0) }
    }
}

struct MinuteDetail: View {
    let sample: MinuteSample
    var body: some View {
        let items: [(String, String)?] = [
            sample.heartRate.map { ("Heart", "\(Int($0)) bpm") },
            sample.motion.map { ("Movement", String(format: "%.1f%%", $0)) },
            sample.noiseDB.map { ("Sound", "\(Int($0)) dB") },
            sample.snoreSeconds > 0 ? ("Snoring", "\(Int(sample.snoreSeconds)) s") : nil,
        ]
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(sample.time.shortTime).font(.footnote.weight(.semibold))
                Text(sample.stage.label).font(.caption).foregroundStyle(sample.stage.color)
            }
            ForEach(items.compactMap { $0 }, id: \.0) { item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.1).font(.footnote.weight(.medium)).monospacedDigit()
                    Text(item.0).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.groupedBG, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The image shared from a night's report.
struct ShareCard: View {
    let session: SleepSession
    let score: SleepScore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(session.end.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 18) {
                ScoreRing(score: score, size: 120, lineWidth: 10, animated: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(hm(session.totalSleepMinutes)).font(.rounded(30))
                    Text("asleep").foregroundStyle(.secondary)
                }
            }
            StageBar(deep: session.deepMinutes, light: session.lightMinutes, rem: session.remMinutes, awake: session.awakeMinutes)
            Text("Tracked on my iPhone with \(AppInfo.name)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 360)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        .foregroundStyle(.white)
    }
}
