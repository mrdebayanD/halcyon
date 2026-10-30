import Foundation
import SwiftData

/// Realistic sample nights so every screen can be explored before the first real one.
enum DemoData {
    @MainActor
    static func generate(nights: Int, context: ModelContext, need: Int) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        for k in stride(from: nights, through: 1, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -(k - 1), to: today) else { continue }
            let lightsOut = day.addingTimeInterval(-3600 * Double.random(in: 0.6...1.6)).minuteFloor
            let armed = lightsOut.addingTimeInterval(-Double(Int.random(in: 3...15)) * 60)
            let (samples, events) = night(armed: armed, lightsOut: lightsOut, length: Int.random(in: 400...510))
            let s = SleepSession(start: armed, end: armed, source: .demo)
            context.insert(s)
            SleepAnalytics.apply(s, samples: samples, events: events, lightsOut: lightsOut, context: context, need: need)
            try? context.save()
        }
    }

    static func night(armed: Date, lightsOut: Date, length: Int) -> ([MinuteSample], [NightEvent]) {
        let lead = Int(lightsOut.timeIntervalSince(armed) / 60)
        let latency = Int.random(in: 5...22)
        var stages: [SleepStage] = Array(repeating: .awake, count: lead + latency)
        var cycle = 0
        var wakeAt: Int?
        while stages.count < length - 6 {
            let deep = max(0, [40, 26, 14, 6, 2, 0][min(cycle, 5)] + Int.random(in: -6...6))
            let rem = [10, 18, 24, 28, 32, 34][min(cycle, 5)] + Int.random(in: -4...5)
            stages += Array(repeating: .light, count: Int.random(in: 10...20))
            stages += Array(repeating: .deep, count: deep)
            stages += Array(repeating: .light, count: Int.random(in: 10...20))
            stages += Array(repeating: .rem, count: max(4, rem))
            if wakeAt == nil && cycle == 2 && Bool.random() {
                wakeAt = stages.count
                stages += Array(repeating: .awake, count: Int.random(in: 4...9))
            }
            cycle += 1
        }
        stages = Array(stages.prefix(length - 5)) + Array(repeating: .awake, count: 5)

        let snorer = Double.random(in: 0...1) < 0.55
        var snoring = false
        let samples: [MinuteSample] = stages.enumerated().map { (i: Int, st: SleepStage) -> MinuteSample in
            if snorer && (st == .light || st == .deep) {
                if Double.random(in: 0...1) < 0.05 { snoring.toggle() }
            } else { snoring = false }
            let motion: Double = switch st {
            case .awake: .random(in: 4...20)
            case .light: Double.random(in: 0...1) < 0.1 ? .random(in: 2...6) : .random(in: 0...1)
            case .rem: .random(in: 0...0.6)
            case .deep: .random(in: 0...0.2)
            }
            return MinuteSample(time: armed.addingTimeInterval(Double(i) * 60), stage: st,
                                motion: motion, noiseDB: 32 + .random(in: -2...3) + (snoring ? 15 : 0),
                                snoreSeconds: snoring ? .random(in: 15...50) : 0)
        }

        func t(_ i: Int) -> Date { armed.addingTimeInterval(Double(i) * 60) }
        let onset = lead + latency
        var events: [NightEvent] = [
            NightEvent(kind: .phoneDown, start: t(max(0, lead - 2)), note: "Flat and charging"),
            NightEvent(kind: .lightsOut, start: lightsOut, note: "You tapped I'm going to sleep"),
            NightEvent(kind: .fellAsleep, start: t(onset), note: "\(latency) minutes after lights-out"),
        ]
        if let w = wakeAt {
            let len = stages[w...].prefix { $0 == .awake }.count
            events.append(NightEvent(kind: .awake, start: t(w), end: t(w + len), phoneUsed: true, note: "Phone picked up, then put back"))
        }
        var i = 0
        while i < samples.count {
            if samples[i].snoreSeconds > 0 {
                var j = i
                while j < samples.count && samples[j].snoreSeconds > 0 { j += 1 }
                if j - i >= 3 {
                    events.append(NightEvent(kind: .snoring, start: t(i), end: t(j), peakDB: 47 + .random(in: 0...8), note: "Loudest at \(Int.random(in: 46...56)) dB"))
                }
                i = j
            } else { i += 1 }
        }
        events.append(NightEvent(kind: .wokeUp, start: t(stages.count - 5), note: "In light sleep, inside your alarm window"))
        events.append(NightEvent(kind: .nightEnded, start: t(stages.count), note: "Phone in use for 15 minutes, listening stopped"))
        return (samples, events.sorted { $0.start < $1.start })
    }
}
