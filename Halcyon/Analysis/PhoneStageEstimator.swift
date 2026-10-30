import Foundation

/// Estimates sleep stages from iPhone-only signals (bed motion + room sound).
///
/// 1. Sleep/wake: a Cole–Kripke style weighted window over per-minute activity,
///    followed by Webster rescoring rules (the classic actigraphy pipeline).
/// 2. Stages within sleep: stillness combined with an ultradian (~95 min) cycle prior —
///    deep sleep is favoured early in the night, REM late in each cycle and late in the night.
///
/// This is an estimate. With an Apple Watch, Halcyon uses Apple's measured stages instead.
enum PhoneStageEstimator {
    static func estimate(_ minutes: [PhoneMinute]) -> [SleepStage] {
        let n = minutes.count
        guard n > 0 else { return [] }

        // Activity normalised to a 600-reading (10 Hz) minute.
        let a: [Double] = minutes.map { m in
            m.motionSamples > 0 ? Double(m.activity) * 600 / Double(m.motionSamples) : 0
        }

        // 1. Cole–Kripke weighted window
        let weights: [(Int, Double)] = [(-4, 106), (-3, 54), (-2, 58), (-1, 76), (0, 230), (1, 74), (2, 67)]
        var wake = [Bool](repeating: false, count: n)
        for i in 0..<n {
            var d = 0.0
            for (o, w) in weights {
                let j = i + o
                if j >= 0 && j < n { d += w * a[j] }
            }
            d *= 0.00006
            if let db = minutes[i].meanDB, db > 58 { d += 0.25 }   // sustained loud sound (talking, TV)
            if minutes[i].snoreSeconds > 10 { d -= 0.6 }           // snoring = asleep
            wake[i] = d >= 1
        }

        // Webster rescoring: after ≥4 wake minutes the next sleep minute is wake;
        // after ≥10, the next 3 are wake.
        var rescored = wake
        var run = 0
        for i in 0..<n {
            if wake[i] {
                run += 1
            } else {
                if run >= 10 {
                    for k in i..<min(n, i + 3) { rescored[k] = true }
                } else if run >= 4 {
                    rescored[i] = true
                }
                run = 0
            }
        }
        // Sleep bouts ≤ 6 min surrounded by ≥ 10 min of wake on both sides are wake.
        var idx = 0
        while idx < n {
            if !rescored[idx] {
                var j = idx
                while j < n && !rescored[j] { j += 1 }
                let len = j - idx
                let before = countWake(rescored, from: idx - 1, step: -1)
                let after = countWake(rescored, from: j, step: 1)
                if len <= 6 && before >= 10 && after >= 10 {
                    for k in idx..<j { rescored[k] = true }
                }
                idx = j
            } else {
                idx += 1
            }
        }

        // Sleep onset: first minute that begins ≥ 8 of 10 sleep minutes, never before minute 5
        // (the phone can't see you lying still but awake).
        var onset: Int?
        for i in 5..<max(5, n) {
            let hi = min(n, i + 10)
            let sleepCount = (i..<hi).filter { !rescored[$0] }.count
            if !rescored[i] && sleepCount >= min(8, hi - i) { onset = i; break }
        }
        guard let onset else { return [SleepStage](repeating: .awake, count: n) }
        let lastSleep = (0..<n).last(where: { !rescored[$0] }) ?? onset
        let span = Double(max(lastSleep - onset, 1))

        // 2. Stage within sleep
        var stages = [SleepStage](repeating: .awake, count: n)
        for i in onset..<n where !rescored[i] {
            let lo = max(0, i - 5), hi = min(n - 1, i + 5)
            let r = a[lo...hi].reduce(0, +) / Double(hi - lo + 1)
            let still = exp(-r / 4.0)
            let t = Double(i - onset)
            let phase = t.truncatingRemainder(dividingBy: 95) / 95
            let frac = t / span
            let quiet = (minutes[i].meanDB ?? 35) < 45 ? 1.0 : 0.85
            let deepP = still * quiet * bump(phase, center: 0.35, width: 0.15) * max(0.15, 1.15 - frac * 1.1)
            let remP = still * bump(phase, center: 0.85, width: 0.16) * (0.45 + frac * 0.7) * (t > 60 ? 1 : 0)
            if deepP > 0.5 {
                stages[i] = .deep
            } else if remP > 0.42 {
                stages[i] = .rem
            } else {
                stages[i] = .light
            }
        }
        return smooth(stages)
    }

    private static func countWake(_ w: [Bool], from start: Int, step: Int) -> Int {
        var c = 0, k = start
        while k >= 0 && k < w.count && w[k] { c += 1; k += step }
        return c
    }

    /// Circular gaussian bump on [0,1).
    private static func bump(_ x: Double, center c: Double, width w: Double) -> Double {
        let d0 = abs(x - c)
        let d = min(d0, 1 - d0)
        return exp(-(d * d) / (2 * w * w))
    }

    /// Absorb sleep-stage runs shorter than 3 minutes into the previous stage.
    private static func smooth(_ s: [SleepStage]) -> [SleepStage] {
        var out = s
        var i = 0
        while i < out.count {
            var j = i
            while j < out.count && out[j] == out[i] { j += 1 }
            if out[i] != .awake && j - i < 3 && i > 0 && out[i - 1] != .awake {
                for k in i..<j { out[k] = out[i - 1] }
            }
            i = j
        }
        return out
    }
}
