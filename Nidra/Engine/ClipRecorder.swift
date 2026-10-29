import Foundation
import AVFoundation

/// Keeps the last few seconds of audio in memory and, when a sound event fires,
/// saves a short clip (pre-roll + a few seconds after) to the app's own storage.
/// Clips older than 30 days are deleted by `ClipStore.prune()`.
final class ClipRecorder {
    private let q = DispatchQueue(label: "sleep.clips")
    private var format: AVAudioFormat?
    private var ring: [AVAudioPCMBuffer] = []
    private var ringFrames: AVAudioFrameCount = 0
    private var writing: (file: AVAudioFile, name: String, framesLeft: AVAudioFrameCount, done: (String) -> Void)?
    private var lastClip: [SoundLabel: Date] = [:]
    private var clipsTonight = 0

    private let preRoll: Double = 4
    /// Audio kept in memory so a breathing-pause clip can include the silence before it.
    private let ringSeconds: Double = 25
    private let postRoll: Double = 5
    private let maxClipsPerNight = 40
    private let cooldown: TimeInterval = 120

    func prepare(format: AVAudioFormat) {
        q.async {
            self.format = format
            self.ring = []
            self.ringFrames = 0
            self.clipsTonight = 0
            self.lastClip = [:]
        }
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let copy = buffer.copy() as? AVAudioPCMBuffer else { return }
        q.async {
            guard let format = self.format else { return }
            self.ring.append(copy)
            self.ringFrames += copy.frameLength
            let keep = AVAudioFrameCount(format.sampleRate * self.ringSeconds)
            while self.ringFrames > keep, let first = self.ring.first {
                self.ringFrames -= first.frameLength
                self.ring.removeFirst()
            }
            if var w = self.writing {
                try? w.file.write(from: copy)
                w.framesLeft = w.framesLeft > copy.frameLength ? w.framesLeft - copy.frameLength : 0
                if w.framesLeft == 0 {
                    let done = w.done, name = w.name
                    self.writing = nil          // closes the file
                    done(name)
                } else {
                    self.writing = w
                }
            }
        }
    }

    func trigger(label: SoundLabel, preRoll seconds: Double? = nil, done: @escaping (String) -> Void) {
        q.async {
            guard self.writing == nil, let format = self.format,
                  self.clipsTonight < self.maxClipsPerNight else { return }
            let cool = label == .pause ? 45 : self.cooldown
            if let last = self.lastClip[label], Date().timeIntervalSince(last) < cool { return }
            let name = "\(label.rawValue)-\(UUID().uuidString).m4a"
            let url = ClipStore.folder.appendingPathComponent(name)
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                           AVSampleRateKey: format.sampleRate,
                                           AVNumberOfChannelsKey: 1,
                                           AVEncoderBitRateKey: 48_000]
            guard let file = try? AVAudioFile(forWriting: url, settings: settings,
                                              commonFormat: .pcmFormatFloat32, interleaved: false) else { return }
            // Write only the last `preRoll` seconds of the ring.
            let want = AVAudioFrameCount(format.sampleRate * (seconds ?? self.preRoll))
            var total: AVAudioFrameCount = 0
            var start = self.ring.count
            while start > 0, total < want {
                start -= 1
                total += self.ring[start].frameLength
            }
            for b in self.ring[start...] { try? file.write(from: b) }
            self.writing = (file, name, AVAudioFrameCount(format.sampleRate * self.postRoll), done)
            self.lastClip[label] = Date()
            self.clipsTonight += 1
        }
    }

    func cancel() {
        q.async {
            self.writing = nil
            self.ring = []
            self.ringFrames = 0
        }
    }
}

enum ClipStore {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(_ name: String) -> URL { folder.appendingPathComponent(name) }

    static func exists(_ name: String?) -> Bool {
        guard let name else { return false }
        return FileManager.default.fileExists(atPath: url(name).path)
    }

    /// Deletes clips older than 30 days.
    static func prune(days: Int = 30) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey]) else { return }
        for f in files {
            let created = (try? f.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if created < cutoff { try? fm.removeItem(at: f) }
        }
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: folder)
    }
}

/// Plays one clip at a time.
@Observable
final class ClipPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = ClipPlayer()
    private(set) var playing: String?
    @ObservationIgnored private var player: AVAudioPlayer?

    func toggle(_ name: String) {
        if playing == name { stop(); return }
        stop()
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord {     // never disturb a night that is being tracked
            try? session.setCategory(.playback)
            try? session.setActive(true)
        }
        guard let p = try? AVAudioPlayer(contentsOf: ClipStore.url(name)) else { return }
        p.delegate = self
        p.play()
        player = p
        playing = name
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        playing = nil
    }
}
