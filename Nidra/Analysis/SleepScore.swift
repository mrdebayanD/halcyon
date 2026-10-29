import Foundation

/// One of the five parts of the score.
struct ScorePart: Identifiable {
    enum Kind: String { case duration, unbroken, regularity, depth, onset }
    let kind: Kind
    let points: Double
    let max: Double
    let why: String
    var id: String { kind.rawValue }
    var name: String {
        switch kind {
        case .duration: "Duration"
        case .unbroken: "Unbroken"
        case .regularity: "Regularity"
        case .depth: "Depth"
        case .onset: "Falling asleep"
        }
    }
    var fraction: Double { max > 0 ? points / max : 0 }
}

struct SleepScore {
    let total: Int
    let parts: [ScorePart]
    var grade: String { SleepScore.grade(total) }

    static func grade(_ s: Int) -> String {
        switch s {
        case 90...: "Excellent"
        case 80..<90: "Great"
        case 70..<80: "Good"
        case 60..<70: "Fair"
        default: "Rough night"
        }
    }
}

/// Sleep Score v2: duration 35, unbroken 20, regularity 20, depth 15, falling asleep 10.
enum SleepScorer {
    /// Piecewise-linear interpolation through (x, y) points sorted by x.
    static func curve(_ x: Double, _ pts: [(Double, Double)]) -> Double {
        guard let f = pts.first, let l = pts.last else { return 0 }
        if x <= f.0 { return f.1 }
        if x >= l.0 { return l.1 }
        for i in 1..<pts.count where x <= pts[i].0 {
            let (x0, y0) = pts[i - 1], (x1, y1) = pts[i]
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
        }
        return l.1
    }

    static func score(_ m: SleepMetrics, latency: Int, need: Int, sri: Double?, bedtimeDeviation: Double?,
                      measuredStages: Bool) -> SleepScore {
        guard m.timeInBed > 0, m.totalSleep > 0 else { return SleepScore(total: 0, parts: []) }
        var parts: [ScorePart] = []

        // Duration (35)
        let ratio = Double(m.totalSleep) / Double(max(need, 1))
        let dur = curve(ratio, [(0.4, 0.1), (0.6, 0.4), (0.75, 0.62), (0.9, 0.86), (0.97, 1), (1.2, 1), (1.45, 0.8)])
        parts.append(ScorePart(kind: .duration, points: (dur * 35).rounded(), max: 35,
                               why: "\(hm(m.totalSleep)) against your \(hm(need)) need"))

        // Unbroken (20)
        let un = Swift.max(0, 1 - Double(m.waso) / 75 - Double(Swift.max(0, m.awakenings - 2)) * 0.06)
        parts.append(ScorePart(kind: .unbroken, points: (un * 20).rounded(), max: 20,
                               why: "\(m.awakenings) wake\(m.awakenings == 1 ? "" : "s"), \(m.waso) minutes awake after falling asleep"))

        // Regularity (20)
        if let sri {
            let r = curve(sri, [(20, 0.2), (50, 0.5), (70, 0.75), (85, 1)])
            parts.append(ScorePart(kind: .regularity, points: (r * 20).rounded(), max: 20,
                                   why: "Regularity \(Int(sri.rounded())) of 100 over the last week"))
        } else if let dev = bedtimeDeviation {
            let r = curve(dev, [(15, 1), (30, 0.85), (60, 0.6), (120, 0.25)])
            parts.append(ScorePart(kind: .regularity, points: (r * 20).rounded(), max: 20,
                                   why: "Bedtime \(Int(dev.rounded())) minutes from your usual"))
        } else {
            parts.append(ScorePart(kind: .regularity, points: 16, max: 20, why: "Needs a few more nights to judge"))
        }

        // Depth (15)
        if measuredStages {
            let deepP = m.percentOfSleep(.deep), remP = m.percentOfSleep(.rem)
            let d = deepP < 13 ? curve(deepP, [(0, 0), (6, 0.45), (13, 1)]) : curve(deepP, [(23, 1), (35, 0.75)])
            let r = remP < 18 ? curve(remP, [(0, 0), (9, 0.5), (18, 1)]) : curve(remP, [(25, 1), (38, 0.75)])
            parts.append(ScorePart(kind: .depth, points: ((d * 0.55 + r * 0.45) * 15).rounded(), max: 15,
                                   why: "Deep \(Int(deepP))%, REM \(Int(remP))% of sleep"))
        } else {
            let restless = Double(m.restlessMinutes) / Double(Swift.max(m.totalSleep, 1))
            let snore = Double(m.snoreMinutes) / Double(Swift.max(m.totalSleep, 1))
            let d = Swift.max(0, 1 - restless * 3 - snore * 1.5)
            parts.append(ScorePart(kind: .depth, points: (d * 15).rounded(), max: 15,
                                   why: d > 0.75 ? "Mostly still, steady breathing; stages estimated" : "Restless or snoring stretches; stages estimated"))
        }

        // Falling asleep (10)
        let lat = Double(latency)
        let o = lat < 5 ? 0.7 : curve(lat, [(5, 0.85), (10, 1), (20, 1), (30, 0.75), (60, 0.35), (90, 0.2)])
        let latWhy = latency < 5 ? "\(latency) minutes; very fast can mean you're short on sleep"
            : latency <= 20 ? "\(latency) minutes, right in the healthy range" : "\(latency) minutes to fall asleep"
        parts.append(ScorePart(kind: .onset, points: (o * 10).rounded(), max: 10, why: latWhy))

        let total = Int(parts.reduce(0) { $0 + $1.points })
        return SleepScore(total: total, parts: parts)
    }
}
