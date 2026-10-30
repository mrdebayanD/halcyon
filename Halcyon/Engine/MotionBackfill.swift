import Foundation
import CoreMotion
import SwiftData

/// When a night wasn't started, rebuilds it in the morning from the iPhone's own motion history.
///
/// iOS keeps about a week of motion activity (stationary, walking, driving…) even while
/// Halcyon isn't running. A long stretch of the phone lying still overnight is a good sign of
/// when you were in bed. Without the microphone there are no stages, snoring or breathing data.
@MainActor
enum MotionBackfill {
    private static let manager = CMMotionActivityManager()
    private static var running = false

    static func run(context: ModelContext) {
        guard !running, CMMotionActivityManager.isActivityAvailable(),
              CMMotionActivityManager.authorizationStatus() != .denied,
              CMMotionActivityManager.authorizationStatus() != .restricted,
              !NightEngine.shared.isArmed else { return }
        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)
        guard hour >= 5 && hour < 16,
              let windowStart = cal.date(bySettingHour: 20, minute: 0, second: 0, of: now.addingTimeInterval(-86_400)) else { return }

        // Already have a night for this window (recorded, imported or backfilled)?
        let existing = FetchDescriptor<SleepSession>(predicate: #Predicate { $0.end > windowStart })
        if let n = try? context.fetchCount(existing), n > 0 { return }

        running = true
        manager.queryActivityStarting(from: windowStart, to: now, to: .main) { activities, _ in
            MainActor.assumeIsolated {
                running = false
                guard let activities, !activities.isEmpty else { return }
                build(activities, from: windowStart, to: now, context: context)
            }
        }
    }

    private static func build(_ acts: [CMMotionActivity], from start: Date, to now: Date, context: ModelContext) {
        let sorted = acts.sorted { $0.startDate < $1.startDate }
        let first = start.minuteFloor
        let count = Int(now.timeIntervalSince(first) / 60)
        guard count > 0 else { return }

        // Still or not, minute by minute: each activity holds until the next one begins.
        var still = [Bool](repeating: false, count: count)
        var j = 0
        for i in 0..<count {
            let t = first.addingTimeInterval(Double(i) * 60 + 30)
            while j + 1 < sorted.count && sorted[j + 1].startDate <= t { j += 1 }
            let a = sorted[j]
            still[i] = a.startDate <= t && a.stationary && !a.walking && !a.running && !a.automotive && !a.cycling
        }

        // Longest run of stillness, bridging pickups of up to 10 minutes (a quick time check).
        var best: (Int, Int)? = nil
        var runStart: Int? = nil
        var lastStill = -100
        for i in 0..<count {
            if still[i] {
                if runStart == nil || i - lastStill > 10 { runStart = i }
                lastStill = i
                if let s = runStart, (best == nil || i - s > best!.1 - best!.0) { best = (s, i) }
            }
        }
        guard let b = best, b.1 - b.0 >= 180 else { return }                // at least 3 hours
        let s = b.0, e = b.1
        guard now.timeIntervalSince(first.addingTimeInterval(Double(e) * 60)) > 20 * 60 else { return } // still in bed

        // Allow ~10 minutes to fall asleep; minutes the phone moved count as awake.
        let onset = min(e, s + 10)
        let samples: [MinuteSample] = (s...e).map { i in
            let t = first.addingTimeInterval(Double(i) * 60)
            let asleep = i >= onset && still[i]
            return MinuteSample(time: t, stage: asleep ? .light : .awake, motion: still[i] ? 0 : 60)
        }
        let bed = first.addingTimeInterval(Double(s) * 60)
        let up = first.addingTimeInterval(Double(e + 1) * 60)
        let events = [
            NightEvent(kind: .phoneDown, start: bed, note: "Halcyon wasn't listening, so this night was rebuilt from your iPhone's movement"),
            NightEvent(kind: .fellAsleep, start: first.addingTimeInterval(Double(onset) * 60), note: "Estimated"),
            NightEvent(kind: .wokeUp, start: up, note: "Phone started moving again"),
        ]

        let session = SleepSession(start: bed, end: up, source: .movement)
        session.note = ""
        context.insert(session)
        let need = UserDefaults.standard.object(forKey: "sleepNeed") as? Int ?? 480
        SleepAnalytics.apply(session, samples: samples, events: events, lightsOut: nil, context: context, need: need)
        try? context.save()
    }
}
