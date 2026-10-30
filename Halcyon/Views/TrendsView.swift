import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Query(sort: \SleepSession.end) private var all: [SleepSession]
    @AppStorage("sleepNeed") private var need = 480
    @State private var range = 14

    private var sessions: [SleepSession] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -range, to: .now) ?? .distantPast
        return all.filter { $0.end >= cutoff }
    }

    private struct StageEntry: Identifiable {
        let id = UUID()
        let day: Date
        let stage: String
        let hours: Double
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Range", selection: $range) {
                        Text("Week").tag(7)
                        Text("2 weeks").tag(14)
                        Text("Month").tag(30)
                        Text("3 months").tag(90)
                    }
                    .pickerStyle(.segmented)

                    if sessions.count < 2 {
                        ContentUnavailableView("Not enough nights yet", systemImage: "chart.bar.xaxis",
                                               description: Text("Trends appear after two nights."))
                            .padding(.top, 40)
                    } else {
                        tiles
                        scoreChart
                        stagesChart
                        windowChart
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color.groupedBG)
            .navigationTitle("Trends")
        }
    }

    private var tiles: some View {
        let scores = sessions.map { Double($0.score) }
        let sleep = sessions.map { Double($0.totalSleepMinutes) }
        let debt = Regularity.debtMinutes(nights: sessions, need: need)
        let sri = Regularity.sri(sessions: Array(sessions.suffix(7)))
        let bed = sessions.map { ($0.lightsOut ?? $0.start).minutesFromEvening }.median ?? 300
        let bedClock = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now)!.addingTimeInterval(bed * 60)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            tile("Average score", "\(Int(scores.mean))", "star.fill", .accentSleep)
            tile("Average sleep", hm(Int(sleep.mean)), "bed.double.fill", .regularTint)
            tile("Sleep debt, 14 nights", hm(debt), "hourglass", debt > 90 ? .snoreTint : .accentSleep)
            tile("Regularity", sri.map { "\(Int($0.rounded())) of 100" } ?? "Need 3 nights", "calendar", .dynamic(0x32ADE6, 0x64D2FF))
            tile("Usual bedtime", bedClock.shortTime, "moon.fill", .accentSleep)
            tile("Snoring per night", "\(Int(sessions.map { Double($0.snoreMinutes) }.mean)) min", "waveform", .snoreTint)
        }
    }

    private func tile(_ title: String, _ value: String, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(value).font(.rounded(22)).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.footnote).foregroundStyle(.secondary)
        }
        .card(padding: 14)
    }

    private var scoreChart: some View {
        let avg = sessions.map { Double($0.score) }.mean
        return VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Sleep score").font(.headline); Spacer(); Text("average \(Int(avg))").font(.footnote).foregroundStyle(.secondary) }
            Chart {
                ForEach(sessions) { s in
                    BarMark(x: .value("Night", s.end, unit: .day), y: .value("Score", s.score))
                        .foregroundStyle(Color.accentSleep.gradient)
                        .cornerRadius(4)
                }
                RuleMark(y: .value("Average", avg))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartYScale(domain: 0...100)
            .frame(height: 170)
        }
        .card()
    }

    private var stagesChart: some View {
        let entries = sessions.flatMap { s in
            [("Deep", s.deepMinutes), ("Core", s.lightMinutes), ("REM", s.remMinutes), ("Awake", s.awakeMinutes)]
                .map { StageEntry(day: s.end, stage: $0.0, hours: Double($0.1) / 60) }
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Time in each stage").font(.headline); Spacer(); Text("need \(hm(need))").font(.footnote).foregroundStyle(.secondary) }
            Chart {
                ForEach(entries) { e in
                    BarMark(x: .value("Night", e.day, unit: .day), y: .value("Hours", e.hours))
                        .foregroundStyle(by: .value("Stage", e.stage))
                }
                RuleMark(y: .value("Need", Double(need) / 60))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartForegroundStyleScale(["Deep": SleepStage.deep.color, "Core": SleepStage.light.color,
                                        "REM": SleepStage.rem.color, "Awake": SleepStage.awake.color])
            .chartLegend(position: .bottom)
            .frame(height: 200)
        }
        .card()
    }

    private var windowChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When you slept").font(.headline)
            Chart(sessions) { s in
                BarMark(x: .value("Night", s.end, unit: .day),
                        yStart: .value("Bed", (s.lightsOut ?? s.start).minutesFromEvening / 60),
                        yEnd: .value("Wake", s.end.minutesFromEvening / 60))
                    .foregroundStyle(Color.regularTint.gradient)
                    .cornerRadius(4)
            }
            .chartYScale(domain: .automatic(includesZero: false, reversed: true))
            .chartYAxis {
                AxisMarks(values: .stride(by: 2)) { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let h = v.as(Double.self) {
                            let clock = (18 + Int(h)) % 24
                            Text(clock == 0 ? "12 AM" : clock < 12 ? "\(clock) AM" : clock == 12 ? "12 PM" : "\(clock - 12) PM")
                        }
                    }
                }
            }
            .frame(height: 190)
        }
        .card()
    }
}
