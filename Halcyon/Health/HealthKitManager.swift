import Foundation
import HealthKit
import SwiftData

/// Reads Apple Watch sleep and vitals, and (optionally) writes each night's stages back to Health.
final class HealthKitManager {
    static let shared = HealthKitManager()
    let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [HKCategoryType(.sleepAnalysis), HKQuantityType(.heartRate), HKQuantityType(.heartRateVariabilitySDNN),
         HKQuantityType(.respiratoryRate), HKQuantityType(.oxygenSaturation)]
    }

    func requestAuthorization(write: Bool) async throws {
        guard isAvailable else { throw HealthError.unavailable }
        let share: Set<HKSampleType> = write ? [HKCategoryType(.sleepAnalysis)] : []
        try await store.requestAuthorization(toShare: share, read: readTypes)
    }

    enum HealthError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Apple Health isn't available on this device." }
    }

    // MARK: Write

    /// Saves the night as Health sleep stages. Returns true on success.
    func save(night samples: [MinuteSample]) async -> Bool {
        guard isAvailable, !samples.isEmpty else { return false }
        do { try await requestAuthorization(write: true) } catch { return false }
        typealias V = HKCategoryValueSleepAnalysis
        let type = HKCategoryType(.sleepAnalysis)
        var out: [HKCategorySample] = []
        var runStart = samples[0].time
        var runStage = samples[0].stage
        func flush(until end: Date) {
            let v: V = switch runStage {
            case .deep: .asleepDeep
            case .rem: .asleepREM
            case .light: .asleepCore
            case .awake: .awake
            }
            out.append(HKCategorySample(type: type, value: v.rawValue, start: runStart, end: end))
        }
        for s in samples.dropFirst() where s.stage != runStage {
            flush(until: s.time)
            runStart = s.time
            runStage = s.stage
        }
        flush(until: samples[samples.count - 1].time.addingTimeInterval(60))
        do {
            try await store.save(out)
            return true
        } catch {
            return false
        }
    }

    // MARK: Read

    /// A minute-by-minute night from Health between `from` and `to`, or nil if there's no sleep.
    func night(from: Date, to: Date) async throws -> [MinuteSample]? {
        let pred = HKQuery.predicateForSamples(withStart: from, end: to)
        let desc = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: pred)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let own = Bundle.main.bundleIdentifier
        let all = try await desc.result(for: store).filter { $0.sourceRevision.source.bundleIdentifier != own }
        guard !all.isEmpty else { return nil }

        typealias V = HKCategoryValueSleepAnalysis
        let staged: Set<Int> = [V.asleepCore.rawValue, V.asleepDeep.rawValue, V.asleepREM.rawValue]
        var use = all
        if all.contains(where: { staged.contains($0.value) }) {
            let sources = Set(all.filter { staged.contains($0.value) }.map { $0.sourceRevision.source.bundleIdentifier })
            use = all.filter { sources.contains($0.sourceRevision.source.bundleIdentifier) && $0.value != V.inBed.rawValue }
        }

        var clusters: [[HKCategorySample]] = []
        for s in use.sorted(by: { $0.startDate < $1.startDate }) {
            if let lastEnd = clusters.last?.map(\.endDate).max(), s.startDate.timeIntervalSince(lastEnd) < 3600 {
                clusters[clusters.count - 1].append(s)
            } else {
                clusters.append([s])
            }
        }
        func span(_ c: [HKCategorySample]) -> TimeInterval {
            guard let a = c.map(\.startDate).min(), let b = c.map(\.endDate).max() else { return 0 }
            return b.timeIntervalSince(a)
        }
        guard let main = clusters.max(by: { span($0) < span($1) }),
              let startRaw = main.map(\.startDate).min(),
              let end = main.map(\.endDate).max() else { return nil }

        let start = startRaw.minuteFloor
        let n = Int(end.timeIntervalSince(start) / 60)
        guard n >= 30 else { return nil }

        func rank(_ v: Int) -> Int {
            switch v {
            case V.inBed.rawValue: 0
            case V.asleepUnspecified.rawValue: 1
            case V.awake.rawValue: 2
            default: 3
            }
        }
        func stage(_ v: Int) -> SleepStage {
            switch v {
            case V.asleepDeep.rawValue: .deep
            case V.asleepREM.rawValue: .rem
            case V.asleepCore.rawValue, V.asleepUnspecified.rawValue: .light
            default: .awake
            }
        }

        var stages = [SleepStage?](repeating: nil, count: n)
        for s in main.sorted(by: { rank($0.value) < rank($1.value) }) {
            let a = max(0, Int(s.startDate.timeIntervalSince(start) / 60))
            let b = min(n, Int((s.endDate.timeIntervalSince(start) / 60).rounded(.up)))
            guard a < b else { continue }
            for i in a..<b { stages[i] = stage(s.value) }
        }

        var samples = (0..<n).map { i in
            MinuteSample(time: start.addingTimeInterval(Double(i) * 60), stage: stages[i] ?? .awake)
        }

        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hr = (try? await quantities(.heartRate, unit: bpm, from: start, to: end)) ?? []
        let hrv = (try? await quantities(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: start, to: end)) ?? []
        let resp = (try? await quantities(.respiratoryRate, unit: bpm, from: start, to: end)) ?? []
        let spo2 = (try? await quantities(.oxygenSaturation, unit: .percent(), from: start, to: end)) ?? []

        func bucket(_ pts: [(Date, Double)], scale: Double = 1) -> [Int: Double] {
            var sum: [Int: Double] = [:], cnt: [Int: Double] = [:]
            for (d, v) in pts {
                let i = Int(d.timeIntervalSince(start) / 60)
                guard i >= 0 && i < n else { continue }
                sum[i, default: 0] += v * scale
                cnt[i, default: 0] += 1
            }
            return sum.reduce(into: [:]) { $0[$1.key] = $1.value / (cnt[$1.key] ?? 1) }
        }
        let hrB = bucket(hr), hrvB = bucket(hrv), respB = bucket(resp), spoB = bucket(spo2, scale: 100)
        for i in 0..<n {
            samples[i].heartRate = hrB[i]
            samples[i].hrv = hrvB[i]
            samples[i].respiratoryRate = respB[i]
            samples[i].spo2 = spoB[i]
        }
        return samples
    }

    private func quantities(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async throws -> [(Date, Double)] {
        let desc = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id),
                                         predicate: HKQuery.predicateForSamples(withStart: from, end: to))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        return try await desc.result(for: store).map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
    }
}

@MainActor
enum HealthImporter {
    /// Imports the last `days` nights from Apple Watch. A night also tracked by the iPhone is merged:
    /// Watch stages and vitals, iPhone events and sounds.
    @discardableResult
    static func importRecentNights(days: Int, context: ModelContext, need: Int) async throws -> Int {
        let hk = HealthKitManager.shared
        try await hk.requestAuthorization(write: false)
        let cal = Calendar.current
        var imported = 0
        for offset in 0..<days {
            guard let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: .now)) else { continue }
            guard let night = try await hk.night(from: day.addingTimeInterval(-6 * 3600), to: day.addingTimeInterval(14 * 3600)),
                  let nStart = night.first?.time, let nEnd = night.last?.time else { continue }

            let existing = (try? context.fetch(FetchDescriptor<SleepSession>())) ?? []
            if existing.contains(where: { ($0.source == .appleWatch || $0.source == .combined) && $0.start < nEnd && $0.end > nStart }) {
                continue
            }
            if let phone = existing.first(where: { $0.source == .iPhone && $0.start < nEnd && $0.end > nStart }) {
                phone.source = .combined
                SleepAnalytics.apply(phone, samples: merge(watch: night, phone: phone.samples), events: phone.events,
                                     lightsOut: phone.lightsOut, context: context, need: need)
            } else {
                let s = SleepSession(start: nStart, end: nEnd, source: .appleWatch)
                context.insert(s)
                SleepAnalytics.apply(s, samples: night, events: [], lightsOut: nil, context: context, need: need)
            }
            try? context.save()
            imported += 1
        }
        return imported
    }

    static func merge(watch: [MinuteSample], phone: [MinuteSample]) -> [MinuteSample] {
        let byMinute = Dictionary(phone.map { ($0.time.minuteFloor, $0) }, uniquingKeysWith: { a, _ in a })
        return watch.map { w in
            var m = w
            if let p = byMinute[w.time.minuteFloor] {
                m.motion = p.motion
                m.noiseDB = p.noiseDB
                m.snoreSeconds = p.snoreSeconds
                m.talkSeconds = p.talkSeconds
                m.coughs = p.coughs
            }
            return m
        }
    }
}
