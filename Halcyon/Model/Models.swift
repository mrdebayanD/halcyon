import Foundation
import SwiftData

// MARK: - Sleep stages

/// Raw value doubles as the chart row (deep at the bottom, awake on top).
enum SleepStage: Int, Codable, CaseIterable, Identifiable {
    case deep = 0, light = 1, rem = 2, awake = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .deep: "Deep"
        case .light: "Core"
        case .rem: "REM"
        case .awake: "Awake"
        }
    }

    var isAsleep: Bool { self != .awake }
}

enum SessionSource: String, Codable {
    case iPhone, appleWatch, combined, demo, movement

    var label: String {
        switch self {
        case .iPhone: "iPhone only"
        case .appleWatch: "Apple Watch"
        case .combined: "Apple Watch + iPhone"
        case .demo: "Sample night"
        case .movement: "iPhone movement only"
        }
    }
}

// MARK: - Minute-level sample

struct MinuteSample: Codable, Hashable, Identifiable {
    var time: Date
    var stage: SleepStage
    var heartRate: Double?
    var hrv: Double?
    var respiratoryRate: Double?
    var spo2: Double?
    /// % of motion readings in this minute that showed movement (0–100).
    var motion: Double?
    /// Approximate room loudness in dB.
    var noiseDB: Double?
    var snoreSeconds: Double = 0
    var talkSeconds: Double = 0
    var coughs: Int = 0
    var pauses: Int = 0

    var id: Date { time }
}

// MARK: - Night events (the "What happened" timeline)

enum EventKind: String, Codable {
    case phoneDown, lightsOut, fellAsleep, snoring, breathingPause, talking, cough, awake, wokeUp, nightEnded

    var symbol: String {
        switch self {
        case .phoneDown: "iphone.gen3"
        case .lightsOut: "lightswitch.off"
        case .fellAsleep: "moon.fill"
        case .snoring: "waveform"
        case .breathingPause: "lungs"
        case .talking: "quote.bubble.fill"
        case .cough: "lungs.fill"
        case .awake: "eye.fill"
        case .wokeUp: "sun.max.fill"
        case .nightEnded: "checkmark"
        }
    }
}

struct NightEvent: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: EventKind
    var start: Date
    var end: Date?
    var peakDB: Double?
    var clipFile: String?
    var phoneUsed = false
    var note: String?
    /// How many times it happened, for grouped events such as breathing pauses.
    var count: Int?

    var minutes: Int { end.map { max(1, Int(($0.timeIntervalSince(start) / 60).rounded())) } ?? 0 }
}

// MARK: - Persisted session

@Model
final class SleepSession {
    @Attribute(.unique) var id: UUID
    var start: Date
    var end: Date
    var sourceRaw: String
    @Attribute(.externalStorage) var samplesBlob: Data
    @Attribute(.externalStorage) var eventsBlob: Data = Data()
    var lightsOut: Date?
    var score: Int
    var note: String
    var tags: [String]
    var alarmFiredAt: Date?
    var savedToHealth: Bool = false

    // Cached summary so lists and trends never decode every night.
    var totalSleepMinutes: Int
    var deepMinutes: Int
    var lightMinutes: Int
    var remMinutes: Int
    var awakeMinutes: Int
    var efficiency: Double
    var latencyMinutes: Int = 0
    var avgHeartRate: Double?
    var avgHRV: Double?
    var snoreMinutes: Int
    var breathingPauses: Int = 0
    /// Minutes the microphone was actually listening.
    var listenedMinutes: Int = 0

    init(start: Date, end: Date, source: SessionSource) {
        self.id = UUID()
        self.start = start
        self.end = end
        self.sourceRaw = source.rawValue
        self.samplesBlob = Data()
        self.score = 0
        self.note = ""
        self.tags = []
        self.totalSleepMinutes = 0
        self.deepMinutes = 0
        self.lightMinutes = 0
        self.remMinutes = 0
        self.awakeMinutes = 0
        self.efficiency = 0
        self.snoreMinutes = 0
    }

    var source: SessionSource {
        get { SessionSource(rawValue: sourceRaw) ?? .iPhone }
        set { sourceRaw = newValue.rawValue }
    }

    var samples: [MinuteSample] {
        get { (try? JSONDecoder().decode([MinuteSample].self, from: samplesBlob)) ?? [] }
        set { samplesBlob = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var events: [NightEvent] {
        get { (try? JSONDecoder().decode([NightEvent].self, from: eventsBlob)) ?? [] }
        set { eventsBlob = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var hasMeasuredStages: Bool { source == .appleWatch || source == .combined }
}

// MARK: - Helpers

extension Date {
    var minuteFloor: Date {
        Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }

    /// Minutes after 6 PM (11 PM = 300, 2 AM = 480) so bedtimes around midnight compare cleanly.
    var minutesFromEvening: Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: self)
        var m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) - 18 * 60
        if m < 0 { m += 1440 }
        return m
    }

    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}

extension Array where Element == Double {
    var mean: Double { isEmpty ? 0 : reduce(0, +) / Double(count) }
    var meanOrNil: Double? { isEmpty ? nil : mean }
    var median: Double? {
        guard !isEmpty else { return nil }
        let s = sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
    var standardDeviation: Double {
        guard count > 1 else { return 0 }
        let m = mean
        return (map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(count - 1)).squareRoot()
    }
    func rollingMean(_ window: Int) -> [Double] {
        guard window > 1, count >= window else { return self }
        var out: [Double] = []
        var sum = self[0..<window].reduce(0, +)
        out.append(sum / Double(window))
        for i in window..<count {
            sum += self[i] - self[i - window]
            out.append(sum / Double(window))
        }
        return out
    }
}

/// "7 h 12 m", "45 m".
func hm(_ minutes: Int) -> String {
    let m = max(0, minutes)
    return m >= 60 ? "\(m / 60) h \(m % 60) m" : "\(m) m"
}
