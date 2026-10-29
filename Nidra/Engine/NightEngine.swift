import Foundation
import AVFoundation
import ActivityKit
import SwiftData
import UIKit

/// Decides the whole night by itself once armed:
/// waiting → asleep ⇄ brief wake → morning end → report.
@Observable
@MainActor
final class NightEngine {
    static let shared = NightEngine()

    enum Phase: String { case idle, waiting, asleep, awake, alarm }
    enum EndReason { case morningUse, userWokeUp, paused, alarmDismissed, hardStop }

    private(set) var phase: Phase = .idle
    private(set) var armedAt: Date?
    private(set) var lightsOut: Date?
    private(set) var asleepSince: Date?
    private(set) var liveDB: Double = 0
    private(set) var micActive = false
    private(set) var alarmTarget: Date?
    private(set) var alarmWindowStart: Date?
    /// Set when a night was saved, so the UI can open its report.
    var justFinished: UUID?
    var lastMessage: String?

    var isArmed: Bool { phase != .idle }

    @ObservationIgnored var container: ModelContainer?
    @ObservationIgnored var appIsActive = true

    @ObservationIgnored private let sensors = SensorHub()
    @ObservationIgnored private let alarm = AlarmPlayer()
    @ObservationIgnored private var minutes: [PhoneMinute] = []
    @ObservationIgnored private var uses: [PhoneUse] = []
    @ObservationIgnored private var sounds: [SoundHit] = []
    @ObservationIgnored private var handledSince: Date?
    @ObservationIgnored private var settledSince: Date?
    @ObservationIgnored private var firstAsleep: Date?
    @ObservationIgnored private var nudgesSent = 0
    @ObservationIgnored private var lastNudge: Date?
    @ObservationIgnored private var quietUntil: Date = .distantPast
    @ObservationIgnored private var alarmFiredAt: Date?
    @ObservationIgnored private var activity: Activity<ListeningAttributes>?
    @ObservationIgnored private let defaults = UserDefaults.standard

    private init() {
        sensors.onTick = { [weak self] t in MainActor.assumeIsolated { self?.tick(t) } }
        sensors.onMinute = { [weak self] m in MainActor.assumeIsolated { self?.minute(m) } }
        sensors.onSound = { [weak self] label, time, db in MainActor.assumeIsolated { self?.sounds.append(SoundHit(label: label, time: time, db: db)) } }
        sensors.onPause = { [weak self] time, gap in MainActor.assumeIsolated {
            guard let self else { return }
            self.sounds.append(SoundHit(label: .pause, time: time, db: self.liveDB, gap: gap))
        } }
        sensors.onAudioRestart = { [weak self] in MainActor.assumeIsolated { self?.micActive = self?.sensors.micActive ?? false } }
        sensors.onClipSaved = { [weak self] label, time, file in MainActor.assumeIsolated {
            guard let self else { return }
            if let i = self.sounds.lastIndex(where: { $0.label == label && abs($0.time.timeIntervalSince(time)) < 5 }) {
                self.sounds[i].clip = file
            } else {
                self.sounds.append(SoundHit(label: label, time: time, db: self.liveDB, clip: file))
            }
        } }
    }

    // MARK: Settings

    private var sleepNeed: Int { defaults.object(forKey: "sleepNeed") as? Int ?? 480 }
    private var nudgesOn: Bool { defaults.object(forKey: "nudges") as? Bool ?? true }
    private var noticeOn: Bool { defaults.object(forKey: "listeningNotice") as? Bool ?? true }
    private var stayArmed: Bool { defaults.object(forKey: "stayArmed") as? Bool ?? false }
    private var alarmOn: Bool { defaults.object(forKey: "alarmEnabled") as? Bool ?? true }
    private var alarmSeconds: Double { defaults.object(forKey: "alarmSeconds") as? Double ?? 7 * 3600 }
    private var alarmWindow: Int { defaults.object(forKey: "alarmWindow") as? Int ?? 30 }
    private var clipsOn: Bool { defaults.object(forKey: "clipsEnabled") as? Bool ?? true }
    private var saveToHealth: Bool { defaults.object(forKey: "saveToHealth") as? Bool ?? false }

    // MARK: Arming (needs the app on screen)

    func arm() async {
        guard phase == .idle else { return }
        let mic = await AVAudioApplication.requestRecordPermission()
        await Notifier.requestPermission()
        sensors.clipsEnabled = clipsOn
        do {
            try sensors.start(useMicrophone: mic)
        } catch {
            lastMessage = "Couldn't start listening: \(error.localizedDescription)"
            return
        }
        micActive = sensors.micActive
        resetNight()
        armedAt = Date()
        phase = .waiting
        if !mic { lastMessage = "Microphone is off, so only movement is tracked. Turn it on in Settings › \(AppInfo.name)." }

        if alarmOn {
            var t = Calendar.current.startOfDay(for: .now).addingTimeInterval(alarmSeconds)
            if t < Date().addingTimeInterval(30 * 60) { t = t.addingTimeInterval(86_400) }
            alarmTarget = t
            alarmWindowStart = t.addingTimeInterval(-Double(alarmWindow) * 60)
            Notifier.scheduleAlarmBackup(at: t)
        }
        startActivity()
    }

    func goingToSleep() {
        if phase == .idle {
            // From the Lock Screen while not armed we can't start the mic; just remember the time.
            lastMessage = "Open \(AppInfo.name) to start listening."
            return
        }
        lightsOut = Date()
        nudgesSent = 0
        quietUntil = .distantPast
        updateActivity()
    }

    func snoozeNudges() { quietUntil = Date().addingTimeInterval(15 * 60) }
    func upForAReason() { quietUntil = Date().addingTimeInterval(60 * 60) }

    // MARK: Live readings

    private func tick(_ t: SensorTick) {
        guard phase != .idle else { return }
        liveDB = t.db
        let now = t.date

        if t.handled {
            if handledSince == nil { handledSince = now }
            settledSince = nil
        } else {
            if let hs = handledSince {
                if now.timeIntervalSince(hs) >= 8 { uses.append(PhoneUse(start: hs, end: now)) }
                handledSince = nil
            }
            if t.flat && t.still { settledSince = settledSince ?? now } else if !t.still { settledSince = nil }
        }

        let settled = settledSince.map { now.timeIntervalSince($0) } ?? 0
        let held = handledSince.map { now.timeIntervalSince($0) } ?? 0

        switch phase {
        case .waiting:
            // Phone flat and still for over a minute, and it's plausibly bedtime → start counting toward sleep.
            let plausible = lightsOut != nil || t.charging || inUsualSleepWindow(now)
            if plausible && settled >= 10 * 60, let s = settledSince {
                phase = .asleep
                asleepSince = s
                firstAsleep = firstAsleep ?? s
                updateActivity()
            }
        case .asleep:
            if held >= 20 { phase = .awake; updateActivity() }
        case .awake:
            if settled >= 2 * 60 { phase = .asleep; asleepSince = settledSince; updateActivity() }
        case .alarm, .idle:
            break
        }

        // Morning: 15 minutes of real use after a proper night ends it, timed from when the use began.
        if let hs = handledSince, held >= 15 * 60, let fa = firstAsleep,
           now.timeIntervalSince(fa) >= 3 * 3600 || nearWakeTime(now) {
            endNight(at: hs, reason: .morningUse)
            return
        }

        // Late-night nudge: phone in hand for 3+ minutes after lights-out, at most twice a night.
        if nudgesOn, let lo = lightsOut, let hs = handledSince, held >= 180,
           nudgesSent < 2, now > quietUntil, !nearWakeTime(now),
           lastNudge.map({ now.timeIntervalSince($0) > 20 * 60 }) ?? true {
            Notifier.sendNudge(minutesSinceLightsOut: Int(now.timeIntervalSince(lo) / 60), index: nudgesSent + Int(hs.timeIntervalSince1970) % 3)
            nudgesSent += 1
            lastNudge = now
        }

        // Safety stop.
        if let a = armedAt, now.timeIntervalSince(a) > 16 * 3600 {
            endNight(reason: .hardStop)
        }
    }

    private func minute(_ m: PhoneMinute) {
        guard phase != .idle else { return }
        minutes.append(m)
        evaluateAlarm()
    }

    // MARK: Smart alarm

    private func evaluateAlarm() {
        guard phase != .alarm, phase != .idle, let target = alarmTarget, let ws = alarmWindowStart else { return }
        let now = Date()
        if now >= target { fireAlarm(); return }
        guard now >= ws, firstAsleep != nil else { return }
        let stirring = minutes.suffix(2).contains { $0.motionPercent > 3 }
        let estimate = PhoneStageEstimator.estimate(Array(minutes.suffix(40))).last
        if stirring || phase == .awake || estimate == .awake || estimate == .light { fireAlarm() }
    }

    private func fireAlarm() {
        phase = .alarm
        alarmFiredAt = Date()
        alarm.start()
        Notifier.cancelAlarmBackup()
        updateActivity()
    }

    func snoozeAlarm(minutes: Int = 9) {
        alarm.stop()
        let t = Date().addingTimeInterval(Double(minutes) * 60)
        alarmTarget = t
        alarmWindowStart = t
        phase = .awake
        Notifier.scheduleAlarmBackup(at: t)
        updateActivity()
    }

    // MARK: Ending

    /// Ends tracking and saves the night. `at` lets the morning rule back-date the end to when phone use began.
    func endNight(at: Date = Date(), reason: EndReason) {
        guard phase != .idle else { return }
        alarm.stop()
        Notifier.cancelAlarmBackup()
        if let hs = handledSince { uses.append(PhoneUse(start: hs, end: max(hs, at))) }

        let note: String = switch reason {
        case .morningUse: "Phone in use for 15 minutes, listening stopped"
        case .userWokeUp, .alarmDismissed: "You tapped I'm up"
        case .paused: "Paused for the night"
        case .hardStop: "Stopped after 16 hours"
        }
        let out = NightBuilder.build(minutes: minutes, uses: uses, sounds: sounds,
                                     lightsOut: lightsOut, endedAt: at, endNote: note)
        let asleep = out.samples.filter { $0.stage.isAsleep }.count

        if !stayArmed { sensors.stop() }
        endActivity()
        let savedID = asleep >= 20 ? save(out) : nil
        if savedID == nil {
            deleteClips()
            if reason != .paused { lastMessage = "Not enough sleep was recorded to make a report." }
        }
        ClipStore.prune()
        resetNight()
        phase = stayArmed && sensors.running ? .waiting : .idle
        if phase == .waiting { armedAt = Date(); startActivity() }
        micActive = sensors.micActive
        justFinished = savedID
    }

    func pauseForTonight() { endNight(reason: .paused) }

    func discardTonight() {
        guard phase != .idle else { return }
        alarm.stop()
        Notifier.cancelAlarmBackup()
        sensors.stop()
        endActivity()
        deleteClips()
        resetNight()
        phase = .idle
        micActive = false
    }

    private func save(_ out: NightBuilder.Output) -> UUID? {
        guard let ctx = container?.mainContext, let first = out.samples.first, let last = out.samples.last else { return nil }
        let s = SleepSession(start: first.time, end: last.time.addingTimeInterval(60), source: .iPhone)
        s.alarmFiredAt = alarmFiredAt
        ctx.insert(s)
        SleepAnalytics.apply(s, samples: out.samples, events: out.events, lightsOut: out.lightsOut, context: ctx, need: sleepNeed)
        try? ctx.save()
        if saveToHealth {
            let samples = out.samples
            Task { if await HealthKitManager.shared.save(night: samples) { s.savedToHealth = true; try? ctx.save() } }
        }
        if !appIsActive { Notifier.nightReady(score: s.score, asleep: s.totalSleepMinutes) }
        return s.id
    }

    private func deleteClips() {
        for c in sounds.compactMap(\.clip) { try? FileManager.default.removeItem(at: ClipStore.url(c)) }
    }

    private func resetNight() {
        minutes = []
        uses = []
        sounds = []
        handledSince = nil
        settledSince = nil
        firstAsleep = nil
        asleepSince = nil
        lightsOut = nil
        nudgesSent = 0
        lastNudge = nil
        quietUntil = .distantPast
        alarmFiredAt = nil
        alarmTarget = nil
        alarmWindowStart = nil
        armedAt = nil
    }

    // MARK: Habit windows (learned from past nights)

    private func recentStarts() -> [Double] {
        guard let ctx = container?.mainContext else { return [] }
        var d = FetchDescriptor<SleepSession>(sortBy: [SortDescriptor(\.start, order: .reverse)])
        d.fetchLimit = 14
        return ((try? ctx.fetch(d)) ?? []).map { ($0.lightsOut ?? $0.start).minutesFromEvening }
    }

    private func inUsualSleepWindow(_ date: Date) -> Bool {
        let m = date.minutesFromEvening
        if let usual = recentStarts().median { return abs(m - usual) <= 150 }
        return m >= 180 && m <= 600          // 9 PM – 4 AM before we know you
    }

    private func nearWakeTime(_ date: Date) -> Bool {
        if let ws = alarmWindowStart, date >= ws.addingTimeInterval(-3600) { return true }
        let h = Calendar.current.component(.hour, from: date)
        return h >= 5 && h < 12 && (firstAsleep.map { date.timeIntervalSince($0) > 4 * 3600 } ?? false)
    }

    // MARK: Live Activity

    private func startActivity() {
        guard noticeOn, ActivityAuthorizationInfo().areActivitiesEnabled, activity == nil else { return }
        let attrs = ListeningAttributes(startedAt: armedAt ?? Date(), alarmStart: alarmWindowStart, alarmEnd: alarmTarget)
        let state = ListeningAttributes.ContentState(phase: phase.rawValue, lightsOut: lightsOut, since: Date())
        activity = try? Activity.request(attributes: attrs, content: .init(state: state, staleDate: nil))
    }

    private func updateActivity() {
        guard let activity else { return }
        let state = ListeningAttributes.ContentState(phase: phase.rawValue, lightsOut: lightsOut, since: Date())
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    private func endActivity() {
        guard let a = activity else { return }
        activity = nil
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }
}
