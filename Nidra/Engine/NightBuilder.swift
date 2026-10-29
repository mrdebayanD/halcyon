import Foundation

struct PhoneUse: Codable, Hashable {
    var start: Date
    var end: Date
}

struct SoundHit {
    var label: SoundLabel
    var time: Date
    var db: Double
    var clip: String?
    /// For a breathing pause: how long the quiet lasted, in seconds.
    var gap: Double = 0
}

/// Turns a night of raw phone minutes into stages + a "What happened" timeline.
enum NightBuilder {
    struct Output {
        var samples: [MinuteSample]
        var events: [NightEvent]
        var lightsOut: Date?
    }

    static func build(minutes raw: [PhoneMinute], uses: [PhoneUse], sounds: [SoundHit],
                      lightsOut: Date?, endedAt: Date, endNote: String) -> Output {
        let minutes = raw.filter { $0.time < endedAt }.sorted { $0.time < $1.time }
        guard !minutes.isEmpty else { return Output(samples: [], events: [], lightsOut: lightsOut) }

        var stages = PhoneStageEstimator.estimate(minutes)

        // Hard rules the estimator can't know: the phone in your hand means you're awake,
        // and nothing before lights-out counts as sleep.
        for (i, m) in minutes.enumerated() {
            let mEnd = m.time.addingTimeInterval(60)
            if uses.contains(where: { $0.start < mEnd && $0.end > m.time }) { stages[i] = .awake }
            if let lo = lightsOut, mEnd <= lo { stages[i] = .awake }
        }
        // A sleep run shorter than 5 minutes between wakes is noise.
        stages = dropShortSleep(stages, minLength: 5)

        let samples = zip(minutes, stages).map { m, st in
            MinuteSample(time: m.time, stage: st,
                         motion: m.motionSamples > 0 ? m.motionPercent : nil,
                         noiseDB: m.meanDB, snoreSeconds: m.snoreSeconds,
                         talkSeconds: m.talkSeconds, coughs: m.coughs, pauses: m.pauses)
        }

        var events: [NightEvent] = []
        let onsetIndex = stages.firstIndex(where: { $0.isAsleep })
        let lastSleepIndex = stages.lastIndex(where: { $0.isAsleep })

        // Phone down: the end of the last phone use before falling asleep.
        if let on = onsetIndex {
            let onsetTime = minutes[on].time
            if let lastUse = uses.filter({ $0.end <= onsetTime }).max(by: { $0.end < $1.end }) {
                events.append(NightEvent(kind: .phoneDown, start: lastUse.end, note: minutes.first?.charging == true ? "Flat and charging" : "Put down"))
            }
        }
        if let lo = lightsOut {
            events.append(NightEvent(kind: .lightsOut, start: lo, note: "You tapped I'm going to sleep"))
        }
        if let on = onsetIndex {
            let ref = lightsOut ?? events.first(where: { $0.kind == .phoneDown })?.start ?? minutes[0].time
            let lat = max(0, Int(minutes[on].time.timeIntervalSince(ref) / 60))
            events.append(NightEvent(kind: .fellAsleep, start: minutes[on].time,
                                     note: "\(lat) minute\(lat == 1 ? "" : "s") after \(lightsOut != nil ? "lights-out" : "putting the phone down")"))
        }

        // Awake periods between falling asleep and the final wake.
        if let on = onsetIndex, let off = lastSleepIndex, on < off {
            var i = on
            while i <= off {
                if stages[i] == .awake {
                    var j = i
                    while j <= off && stages[j] == .awake { j += 1 }
                    if j - i >= 2 {
                        let s = minutes[i].time, e = minutes[min(j, minutes.count - 1)].time
                        let usedPhone = uses.contains { $0.start < e && $0.end > s }
                        events.append(NightEvent(kind: .awake, start: s, end: e, phoneUsed: usedPhone,
                                                 note: usedPhone ? "Phone picked up, then put back" : "Restless, no phone"))
                    }
                    i = j
                } else { i += 1 }
            }
        }

        // Snoring: minutes with ≥3 s of snoring, merged across gaps of up to 2 minutes,
        // kept when the run holds at least 10 s of snoring in total.
        var runs: [(Int, Int)] = []
        for (i, m) in minutes.enumerated() where m.snoreSeconds >= 3 {
            if let last = runs.last, i - last.1 <= 3 { runs[runs.count - 1].1 = i } else { runs.append((i, i)) }
        }
        for r in runs where minutes[r.0...r.1].map(\.snoreSeconds).reduce(0, +) >= 10 {
            let s = minutes[r.0].time, e = minutes[r.1].time.addingTimeInterval(60)
            let peak = minutes[r.0...r.1].map(\.peakDB).max() ?? 0
            let clip = sounds.first { $0.label == .snoring && $0.clip != nil && $0.time >= s.addingTimeInterval(-60) && $0.time <= e }?.clip
            events.append(NightEvent(kind: .snoring, start: s, end: e, peakDB: peak, clipFile: clip,
                                     note: "Loudest at \(Int(peak)) dB"))
        }

        // Talking and coughs from classifier hits, grouped within 90 s, only while in bed after onset.
        let afterOnset = onsetIndex.map { minutes[$0].time } ?? .distantFuture
        for label in [SoundLabel.talking, .cough] {
            let hits = sounds.filter { $0.label == label && $0.time >= afterOnset }.sorted { $0.time < $1.time }
            var groups: [[SoundHit]] = []
            for h in hits {
                if let g = groups.last, let l = g.last, h.time.timeIntervalSince(l.time) < 90 { groups[groups.count - 1].append(h) }
                else { groups.append([h]) }
            }
            for g in groups {
                guard let first = g.first, let last = g.last else { continue }
                if label == .talking {
                    let secs = max(2, Int(last.time.timeIntervalSince(first.time)) + 2)
                    events.append(NightEvent(kind: .talking, start: first.time, end: last.time, clipFile: g.compactMap(\.clip).first,
                                             note: "About \(secs) seconds"))
                } else {
                    events.append(NightEvent(kind: .cough, start: first.time, clipFile: g.compactMap(\.clip).first,
                                             note: g.count == 1 ? "Once" : "\(g.count) times"))
                }
            }
        }

        // Possible breathing pauses, grouped when they come within 10 minutes of each other.
        let pauses = sounds.filter { $0.label == .pause }.sorted { $0.time < $1.time }
        var pauseGroups: [[SoundHit]] = []
        for p in pauses {
            if let g = pauseGroups.last, let l = g.last, p.time.timeIntervalSince(l.time) < 600 { pauseGroups[pauseGroups.count - 1].append(p) }
            else { pauseGroups.append([p]) }
        }
        for g in pauseGroups {
            guard let first = g.first, let last = g.last else { continue }
            let longest = Int(g.map(\.gap).max() ?? 0)
            events.append(NightEvent(kind: .breathingPause, start: first.time.addingTimeInterval(-first.gap), end: last.time,
                                     clipFile: g.compactMap(\.clip).first,
                                     note: g.count == 1 ? "Snoring stopped for \(longest) s, then a loud breath"
                                                        : "\(g.count) times, longest quiet \(longest) s",
                                     count: g.count))
        }

        if let off = lastSleepIndex {
            events.append(NightEvent(kind: .wokeUp, start: minutes[off].time.addingTimeInterval(60), note: "Last stretch of sleep ended"))
        }
        events.append(NightEvent(kind: .nightEnded, start: endedAt, note: endNote))

        return Output(samples: samples, events: events.sorted { $0.start < $1.start }, lightsOut: lightsOut)
    }

    private static func dropShortSleep(_ s: [SleepStage], minLength: Int) -> [SleepStage] {
        var out = s
        var i = 0
        while i < out.count {
            if out[i].isAsleep {
                var j = i
                while j < out.count && out[j].isAsleep { j += 1 }
                if j - i < minLength { for k in i..<j { out[k] = .awake } }
                i = j
            } else { i += 1 }
        }
        return out
    }
}
