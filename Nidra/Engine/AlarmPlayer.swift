import AVFoundation

/// Plays a soft, synthesised chime that fades in over 45 seconds.
final class AlarmPlayer {
    private var player: AVAudioPlayer?

    func start() {
        if player == nil {
            player = try? AVAudioPlayer(data: Self.makeChime())
            player?.numberOfLoops = -1
            player?.prepareToPlay()
        }
        player?.volume = 0.05
        player?.play()
        player?.setVolume(1.0, fadeDuration: 45)
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
    }

    /// A rising C-major arpeggio with soft bell harmonics, as an in-memory WAV.
    static func makeChime(sampleRate: Double = 44_100) -> Data {
        let duration = 4.0
        let count = Int(sampleRate * duration)
        var pcm = [Int16](repeating: 0, count: count)
        let notes: [(freq: Double, at: Double)] = [(523.25, 0), (659.25, 0.35), (783.99, 0.7), (1046.5, 1.05)]
        for i in 0..<count {
            let t = Double(i) / sampleRate
            var v = 0.0
            for note in notes where t >= note.at {
                let dt = t - note.at
                let env = exp(-dt * 2.2) * min(1, dt * 200)
                v += sin(2 * .pi * note.freq * dt) * env * 0.22
                v += sin(2 * .pi * note.freq * 2.01 * dt) * env * 0.05
            }
            pcm[i] = Int16(max(-1, min(1, v)) * 32_000)
        }

        var data = Data()
        func put<T: FixedWidthInteger>(_ v: T) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        let bytes = UInt32(count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36) + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16))
        put(UInt16(1)); put(UInt16(1))
        put(UInt32(sampleRate)); put(UInt32(sampleRate * 2))
        put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); put(bytes)
        pcm.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return data
    }
}
