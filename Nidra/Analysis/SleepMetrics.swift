import Foundation

/// Everything measurable about one night, derived from minute samples.
struct SleepMetrics {
    var bedStart: Date = .now
    var bedEnd: Date = .now
    var timeInBed = 0
    var totalSleep = 0
    var latency = 0
    var waso = 0
    var awakenings = 0
    var efficiency = 0.0
    var stageMinutes: [SleepStage: Int] = [:]
    var sleepOnset: Date?
    var finalWake: Date?
    var remPeriods = 0
    var longestBout = 0
    var timeToFirstDeep: Int?
    var timeToFirstREM: Int?

    var avgHR: Double?
    var minHR: Double?
    var hrDip: Double?
    var avgHRV: Double?
    var maxHRV: Double?
    var avgResp: Double?
    var minSpO2: Double?

    var avgNoise: Double?
    var peakNoise: Double?
    var snoreMinutes = 0
    var coughs = 0
    var restlessMinutes = 0

    var hasHeart: Bool { avgHR != nil }
    var hasHRV: Bool { avgHRV != nil }
    var hasPhoneSensors: Bool { avgNoise != nil || restlessMinutes > 0 }

    func minutes(_ s: SleepStage) -> Int { stageMinutes[s] ?? 0 }

    func percentOfSleep(_ s: SleepStage) -> Double {
        totalSleep > 0 ? Double(minutes(s)) / Double(totalSleep) * 100 : 0
    }

    init(samples raw: [MinuteSample]) {
        let s = raw.sorted { $0.time < $1.time }
        guard let first = s.first, let last = s.last else { return }

        bedStart = first.time
        bedEnd = last.time.addingTimeInterval(60)
        timeInBed = s.count
        for x in s { stageMinutes[x.stage, default: 0] += 1 }
        totalSleep = s.filter { $0.stage.isAsleep }.count
        efficiency = timeInBed > 0 ? Double(totalSleep) / Double(timeInBed) : 0

        if let on = s.firstIndex(where: { $0.stage.isAsleep }),
           let off = s.lastIndex(where: { $0.stage.isAsleep }) {
            latency = on
            sleepOnset = s[on].time
            finalWake = s[off].time.addingTimeInterval(60)

            var awakeRun = 0, bout = 0, remRun = 0
            for i in on...off {
                let st = s[i].stage
                if st == .awake {
                    waso += 1
                    awakeRun += 1
                    longestBout = max(longestBout, bout)
                    bout = 0
                } else {
                    if awakeRun >= 2 { awakenings += 1 }
                    awakeRun = 0
                    bout += 1
                }
                if st == .rem {
                    remRun += 1
                    if remRun == 3 { remPeriods += 1 }
                } else {
                    remRun = 0
                }
            }
            longestBout = max(longestBout, bout)
            if let d = s[on...off].firstIndex(where: { $0.stage == .deep }) { timeToFirstDeep = d - on }
            if let r = s[on...off].firstIndex(where: { $0.stage == .rem }) { timeToFirstREM = r - on }
        }

        let asleep = s.filter { $0.stage.isAsleep }

        let hr = asleep.compactMap(\.heartRate)
        if !hr.isEmpty {
            avgHR = hr.mean
            let smooth = hr.rollingMean(min(5, hr.count))
            minHR = smooth.min()
            let early = Array(hr.prefix(max(3, hr.count / 8))).mean
            if let m = minHR, early > 0 { hrDip = max(0, (early - m) / early * 100) }
        }

        let hrv = asleep.compactMap(\.hrv)
        avgHRV = hrv.meanOrNil
        maxHRV = hrv.max()
        avgResp = asleep.compactMap(\.respiratoryRate).meanOrNil
        minSpO2 = s.compactMap(\.spo2).min()

        let noise = s.compactMap(\.noiseDB)
        avgNoise = noise.meanOrNil
        peakNoise = noise.max()
        snoreMinutes = s.filter { $0.snoreSeconds >= 3 }.count
        coughs = s.reduce(0) { $0 + $1.coughs }
        restlessMinutes = asleep.filter { ($0.motion ?? 0) > 4 }.count
    }
}

/// Merges minutes into contiguous stage blocks for drawing.
struct StageSegment: Identifiable {
    let stage: SleepStage
    let start: Date
    let end: Date
    var id: Date { start }
    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }

    static func build(from samples: [MinuteSample]) -> [StageSegment] {
        var out: [StageSegment] = []
        var curStage: SleepStage?
        var curStart: Date = .now
        var lastTime: Date = .now
        for s in samples {
            if s.stage != curStage {
                if let c = curStage { out.append(StageSegment(stage: c, start: curStart, end: s.time)) }
                curStage = s.stage
                curStart = s.time
            }
            lastTime = s.time
        }
        if let c = curStage { out.append(StageSegment(stage: c, start: curStart, end: lastTime.addingTimeInterval(60))) }
        return out
    }
}
