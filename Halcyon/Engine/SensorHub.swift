import Foundation
import CoreMotion
import AVFoundation
import SoundAnalysis
import UIKit

/// One minute of raw phone-sensor aggregates.
struct PhoneMinute {
    var time: Date
    var activity = 0
    var motionSamples = 0
    var flatSamples = 0
    var dbSum = 0.0
    var dbCount = 0
    var peakDB = 0.0
    var snoreSeconds = 0.0
    var talkSeconds = 0.0
    var coughs = 0
    var pauses = 0
    var charging = false

    var meanDB: Double? { dbCount > 0 ? dbSum / Double(dbCount) : nil }
    var motionPercent: Double { motionSamples > 0 ? Double(activity) / Double(motionSamples) * 100 : 0 }
    var flatFraction: Double { motionSamples > 0 ? Double(flatSamples) / Double(motionSamples) : 0 }
}

/// A live reading pushed to the night engine every couple of seconds.
struct SensorTick {
    var date: Date
    /// Phone lying face up or face down.
    var flat: Bool
    /// No movement in the last few seconds.
    var still: Bool
    /// Being held or moved: tilted off flat, or moving a lot.
    var handled: Bool
    var charging: Bool
    var db: Double
}

enum SoundLabel: String { case snoring, talking, cough, pause }

/// Owns the motion sensor and microphone for the night. Everything is analysed on the
/// device; only short event clips are ever written, and only when clips are enabled.
final class SensorHub {
    var onTick: ((SensorTick) -> Void)?
    var onMinute: ((PhoneMinute) -> Void)?
    var onSound: ((SoundLabel, Date, Double) -> Void)?
    var onClipSaved: ((SoundLabel, Date, String) -> Void)?
    /// A possible breathing pause: snoring stopped for `gap` seconds, then came back loudly.
    var onPause: ((Date, Double) -> Void)?
    /// Called when the mic had to be restarted (call, Siri, alarm, headphones).
    var onAudioRestart: (() -> Void)?

    private(set) var micActive = false
    private(set) var running = false

    private let motion = CMMotionManager()
    private let engine = AVAudioEngine()
    private var analyzer: SNAudioStreamAnalyzer?
    private var observer: SoundObserver?
    private let clips = ClipRecorder()
    private let work = DispatchQueue(label: "sleep.sensors")
    private let analysisQueue = DispatchQueue(label: "sleep.sound-analysis")
    private let motionQueue = OperationQueue()
    private var minuteTimer: DispatchSourceTimer?
    private var wantsMic = false
    private var lastRestart = Date.distantPast
    private var audioObservers: [NSObjectProtocol] = []
    // Breathing-pause detection state (work queue only).
    private var lastSnore: Date?
    private var boutHits = 0
    private var gapDBSum = 0.0
    private var gapDBCount = 0
    private var tickTimer: DispatchSourceTimer?

    // Owned by `work`.
    private var current = PhoneMinute(time: .now)
    private var recentMotion: [Bool] = []      // last ~4 s of "moving?" flags (10 Hz)
    private var recentFlat: [Bool] = []
    private var lastDB = 0.0

    var clipsEnabled = true

    init() {
        motionQueue.maxConcurrentOperationCount = 1
        motionQueue.underlyingQueue = work
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    /// Must be called while the app is in the foreground: iOS only lets an on-screen app start the mic.
    func start(useMicrophone: Bool) throws {
        guard !running else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)

        work.sync {
            current = PhoneMinute(time: Date().minuteFloor)
            recentMotion = []
            recentFlat = []
        }
        startMotion()
        wantsMic = useMicrophone
        if useMicrophone { startAudio() } else { startSilentKeepAlive() }
        observeAudioSession()
        startTimers()
        running = true
    }

    func stop() {
        guard running else { return }
        minuteTimer?.cancel(); minuteTimer = nil
        tickTimer?.cancel(); tickTimer = nil
        motion.stopDeviceMotionUpdates()
        audioObservers.forEach { NotificationCenter.default.removeObserver($0) }
        audioObservers = []
        wantsMic = false
        if micActive { engine.inputNode.removeTap(onBus: 0) }
        if engine.isRunning { engine.stop() }
        analyzer?.removeAllRequests()
        analyzer = nil
        observer = nil
        clips.cancel()
        micActive = false
        running = false
        work.sync {
            if current.motionSamples > 0 || current.dbCount > 0 { onMinute?(current) }
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Motion

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 0.1
        motion.startDeviceMotionUpdates(to: motionQueue) { [weak self] data, _ in
            guard let self, let d = data else { return }
            let a = d.userAcceleration
            let accel = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            let rot = d.rotationRate
            let spin = (rot.x * rot.x + rot.y * rot.y + rot.z * rot.z).squareRoot()
            let moving = accel > 0.015 || spin > 0.08
            let flat = abs(d.gravity.z) > 0.9
            self.current.motionSamples += 1
            if moving { self.current.activity += 1 }
            if flat { self.current.flatSamples += 1 }
            self.recentMotion.append(moving)
            self.recentFlat.append(flat)
            if self.recentMotion.count > 40 { self.recentMotion.removeFirst(self.recentMotion.count - 40) }
            if self.recentFlat.count > 40 { self.recentFlat.removeFirst(self.recentFlat.count - 40) }
        }
    }

    // MARK: Audio

    private func startAudio() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { startSilentKeepAlive(); return }

        let analyzer = SNAudioStreamAnalyzer(format: format)
        let observer = SoundObserver { [weak self] label, seconds in
            guard let self else { return }
            let now = Date()
            self.work.async {
                switch label {
                case .snoring:
                    self.current.snoreSeconds += seconds
                    self.checkForPause(at: now)
                case .talking: self.current.talkSeconds += seconds
                case .cough: self.current.coughs += 1
                case .pause: break
                }
                let db = self.lastDB
                DispatchQueue.main.async { self.onSound?(label, now, db) }
            }
            if self.clipsEnabled {
                self.clips.trigger(label: label) { [weak self] file in
                    DispatchQueue.main.async { self?.onClipSaved?(label, now, file) }
                }
            }
        }
        if let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) {
            request.windowDuration = CMTimeMakeWithSeconds(1.5, preferredTimescale: 48_000)
            request.overlapFactor = 0.5
            try? analyzer.add(request, withObserver: observer)
        }
        self.analyzer = analyzer
        self.observer = observer
        clips.prepare(format: format)

        input.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, when in
            guard let self else { return }
            let db = Self.decibels(buffer)
            self.clips.feed(buffer)
            self.analysisQueue.async { analyzer.analyze(buffer, atAudioFramePosition: when.sampleTime) }
            self.work.async {
                self.lastDB = db
                self.gapDBSum += db
                self.gapDBCount += 1
                self.current.dbSum += db
                self.current.dbCount += 1
                self.current.peakDB = max(self.current.peakDB, db)
            }
        }
        do {
            engine.prepare()
            try engine.start()
            micActive = true
        } catch {
            startSilentKeepAlive()
        }
    }

    /// Snoring that stops for 10–90 s and then comes back with a burst at least 6 dB louder than
    /// the quiet in between is the pattern an obstructive apnea or hypopnea tends to leave
    /// (silence, then a gasp or snort). Only counted inside a sustained bout of snoring.
    private func checkForPause(at now: Date) {
        if let last = lastSnore {
            let gap = now.timeIntervalSince(last)
            if gap > 90 { boutHits = 0 }
            if gap >= 10, gap <= 90, boutHits >= 6, gapDBCount > 0 {
                let quiet = gapDBSum / Double(gapDBCount)
                if lastDB - quiet >= 6 {
                    current.pauses += 1
                    DispatchQueue.main.async { self.onPause?(now, gap) }
                    if clipsEnabled {
                        clips.trigger(label: .pause, preRoll: min(gap + 4, 24)) { [weak self] file in
                            DispatchQueue.main.async { self?.onClipSaved?(.pause, now, file) }
                        }
                    }
                }
            }
        }
        boutHits += 1
        lastSnore = now
        gapDBSum = 0
        gapDBCount = 0
    }

    // MARK: Keeping the mic alive

    private func observeAudioSession() {
        let nc = NotificationCenter.default
        let s = AVAudioSession.sharedInstance()
        audioObservers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: s, queue: .main) { [weak self] n in
            guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            self?.restartAudio()
        })
        audioObservers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: s, queue: .main) { [weak self] _ in
            self?.restartAudio()
        })
        audioObservers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restartAudio()
        })
    }

    /// Restarts the microphone after an interruption or a route change. iOS lets an app that was
    /// already recording in the background resume, so this works with the screen locked.
    private func restartAudio() {
        guard running, wantsMic, Date().timeIntervalSince(lastRestart) > 2 else { return }
        lastRestart = Date()
        if micActive { engine.inputNode.removeTap(onBus: 0) }
        if engine.isRunning { engine.stop() }
        analyzer?.removeAllRequests()
        micActive = false
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement,
                                 options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try? session.setActive(true)
        startAudio()
        onAudioRestart?()
    }

    /// Without the mic, a silent output keeps the app alive in the background.
    private func startSilentKeepAlive() {
        engine.mainMixerNode.outputVolume = 0
        engine.prepare()
        try? engine.start()
    }

    /// RMS → dBFS → rough dB SPL (iPhone mics sit near −100 dBFS at silence).
    private static func decibels(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let ch = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        let rms = (sum / Float(n)).squareRoot()
        return Double(max(0, 20 * log10(max(rms, 1e-7)) + 100))
    }

    // MARK: Timers

    private func startTimers() {
        let m = DispatchSource.makeTimerSource(queue: work)
        let next = Date().minuteFloor.addingTimeInterval(60).timeIntervalSinceNow
        m.schedule(deadline: .now() + max(1, next), repeating: 60, leeway: .seconds(1))
        m.setEventHandler { [weak self] in
            guard let self else { return }
            var finished = self.current
            finished.charging = Self.isCharging
            self.current = PhoneMinute(time: Date().minuteFloor)
            DispatchQueue.main.async { self.onMinute?(finished) }
        }
        m.resume()
        minuteTimer = m

        let t = DispatchSource.makeTimerSource(queue: work)
        t.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(200))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let movingShare = self.recentMotion.isEmpty ? 0 : Double(self.recentMotion.filter { $0 }.count) / Double(self.recentMotion.count)
            let flatShare = self.recentFlat.isEmpty ? 1 : Double(self.recentFlat.filter { $0 }.count) / Double(self.recentFlat.count)
            let tick = SensorTick(date: Date(),
                                  flat: flatShare > 0.8,
                                  still: movingShare < 0.05,
                                  handled: flatShare < 0.5 || movingShare > 0.35,
                                  charging: Self.isCharging,
                                  db: self.lastDB)
            DispatchQueue.main.async { self.onTick?(tick) }
        }
        t.resume()
        tickTimer = t
    }

    private static var isCharging: Bool {
        let s = UIDevice.current.batteryState
        return s == .charging || s == .full
    }
}

/// Receives Apple's on-device sound classifier results.
final class SoundObserver: NSObject, SNResultsObserving {
    private let handler: (SoundLabel, Double) -> Void
    init(handler: @escaping (SoundLabel, Double) -> Void) { self.handler = handler }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let r = result as? SNClassificationResult else { return }
        let d = r.timeRange.duration.seconds
        let seconds = d.isFinite && d > 0 ? d / 2 : 0.75   // 50% overlap
        func conf(_ id: String) -> Double { r.classification(forIdentifier: id)?.confidence ?? 0 }
        if conf("snoring") > 0.35 {
            handler(.snoring, seconds)
        } else if max(conf("speech"), conf("whispering"), conf("laughter")) > 0.6 {
            handler(.talking, seconds)
        } else if conf("cough") > 0.6 {
            handler(.cough, seconds)
        }
    }
}
