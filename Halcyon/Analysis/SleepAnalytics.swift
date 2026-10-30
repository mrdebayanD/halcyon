import Foundation
import SwiftData

/// Everything the report needs about one night, computed on demand.
struct NightAnalysis {
    let metrics: SleepMetrics
    let latency: Int
    let score: SleepScore
    let sri: Double?
}

enum SleepAnalytics {
    /// Stores samples and events on the session and refreshes its summary fields and score.
    static func apply(_ session: SleepSession, samples: [MinuteSample], events: [NightEvent],
                      lightsOut: Date?, context: ModelContext, need: Int) {
        let sorted = samples.sorted { $0.time < $1.time }
        session.samples = sorted
        session.events = events
        session.lightsOut = lightsOut
        let m = SleepMetrics(samples: sorted)
        session.start = m.bedStart
        session.end = m.bedEnd
        session.totalSleepMinutes = m.totalSleep
        session.deepMinutes = m.minutes(.deep)
        session.lightMinutes = m.minutes(.light)
        session.remMinutes = m.minutes(.rem)
        session.awakeMinutes = m.minutes(.awake)
        session.efficiency = m.efficiency
        session.avgHeartRate = m.avgHR
        session.avgHRV = m.avgHRV
        session.snoreMinutes = m.snoreMinutes
        session.breathingPauses = events.filter { $0.kind == .breathingPause }.reduce(0) { $0 + ($1.count ?? 1) }
        session.listenedMinutes = sorted.filter { $0.noiseDB != nil }.count
        let a = analyze(session, metrics: m, context: context, need: need)
        session.latencyMinutes = a.latency
        session.score = a.score.total
    }

    static func analyze(_ session: SleepSession, context: ModelContext, need: Int) -> NightAnalysis {
        analyze(session, metrics: SleepMetrics(samples: session.samples), context: context, need: need)
    }

    private static func analyze(_ session: SleepSession, metrics m: SleepMetrics, context: ModelContext, need: Int) -> NightAnalysis {
        let latency = latencyMinutes(session, metrics: m)
        let prev = previous(before: session.start, days: 7, context: context)
        let sri = Regularity.sri(sessions: prev + [session])
        let dev = bedtimeDeviation(session, previous: prev)
        let score = SleepScorer.score(m, latency: latency, need: need, sri: sri, bedtimeDeviation: dev,
                                      measuredStages: session.hasMeasuredStages)
        return NightAnalysis(metrics: m, latency: latency, score: score, sri: sri)
    }

    /// From lights-out (or putting the phone down) to the first minute asleep.
    static func latencyMinutes(_ s: SleepSession, metrics m: SleepMetrics) -> Int {
        guard let onset = m.sleepOnset else { return m.latency }
        let ref = s.lightsOut ?? s.events.first(where: { $0.kind == .phoneDown })?.start
        if let ref, ref <= onset { return Int(onset.timeIntervalSince(ref) / 60) }
        return m.latency
    }

    static func previous(before date: Date, days: Int, context: ModelContext) -> [SleepSession] {
        let since = date.addingTimeInterval(-Double(days) * 86_400)
        let d = FetchDescriptor<SleepSession>(predicate: #Predicate { $0.start < date && $0.start > since },
                                              sortBy: [SortDescriptor(\.start, order: .reverse)])
        return (try? context.fetch(d)) ?? []
    }

    static func bedtimeDeviation(_ s: SleepSession, previous: [SleepSession]) -> Double? {
        guard previous.count >= 3 else { return nil }
        let usual = previous.map { ($0.lightsOut ?? $0.start).minutesFromEvening }.median ?? 0
        return abs((s.lightsOut ?? s.start).minutesFromEvening - usual)
    }
}

enum Regularity {
    /// Sleep Regularity Index (Phillips et al. 2017): the chance of being in the same state
    /// at the same clock minute on consecutive days, scaled −100…100. Needs 3+ nights.
    static func sri(sessions: [SleepSession]) -> Double? {
        let cal = Calendar.current
        // Bucket each night into the "day" it ends on, from noon to noon.
        var days: [Date: [Bool]] = [:]
        for s in sessions {
            let anchor = cal.startOfDay(for: s.end.addingTimeInterval(-12 * 3600)).addingTimeInterval(12 * 3600)
            var arr = days[anchor] ?? [Bool](repeating: false, count: 1440)
            for sample in s.samples where sample.stage.isAsleep {
                let i = Int(sample.time.timeIntervalSince(anchor) / 60)
                if i >= 0 && i < 1440 { arr[i] = true }
            }
            days[anchor] = arr
        }
        let keys = days.keys.sorted()
        var same = 0, total = 0
        for (a, b) in zip(keys, keys.dropFirst()) where b.timeIntervalSince(a) < 1.5 * 86_400 {
            guard let x = days[a], let y = days[b] else { continue }
            for i in 0..<1440 { if x[i] == y[i] { same += 1 }; total += 1 }
        }
        guard total >= 2 * 1440 else { return nil }
        return -100 + 200 * Double(same) / Double(total)
    }

    /// Weighted shortfall over 14 nights; each night's weight halves every 4 nights back.
    static func debtMinutes(nights: [SleepSession], need: Int) -> Int {
        let recent = nights.sorted { $0.end > $1.end }.prefix(14)
        var debt = 0.0
        for (i, n) in recent.enumerated() {
            debt += pow(0.5, Double(i) / 4) * Double(need - n.totalSleepMinutes)
        }
        return max(0, Int(debt.rounded()))
    }

    /// Consecutive recent nights whose bedtime sat within 20 minutes of the median.
    static func steadyStreak(nights: [SleepSession]) -> Int {
        let recent = Array(nights.sorted { $0.end > $1.end }.prefix(14))
        guard recent.count >= 3, let usual = recent.map({ ($0.lightsOut ?? $0.start).minutesFromEvening }).median else { return 0 }
        var n = 0
        for s in recent {
            if abs((s.lightsOut ?? s.start).minutesFromEvening - usual) <= 20 { n += 1 } else { break }
        }
        return n
    }
}
