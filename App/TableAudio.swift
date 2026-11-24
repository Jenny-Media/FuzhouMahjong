import AVFAudio
import Foundation

enum TableTileMaterial: String, Sendable {
    case classic, porcelain
    case ivoryRedwood = "ivory-redwood"
    case paleJade = "pale-jade"
    case creamBakelite = "cream-bakelite"

    var tone: (body: Float, edge: Float, decay: Float) {
        switch self {
        case .classic: (1, 1, 0)
        case .porcelain: (0.72, 1.34, 2)
        case .ivoryRedwood: (1.24, 0.61, 4.5)
        case .paleJade: (1.06, 1.56, 0)
        case .creamBakelite: (0.82, 1.12, 10)
        }
    }
}

enum TablePlayingSurface: String, Sendable {
    case wool, suede, leather

    var artwork: String {
        switch self {
        case .wool: "FineWool"
        case .suede: "SmokeSuede"
        case .leather: "SaddleLeather"
        }
    }

    var damping: (edge: Float, decay: Float) {
        switch self {
        case .wool: (0, 0)
        case .suede: (0.45, 20)
        case .leather: (0.22, 8)
        }
    }
}

struct TableFeedbackProfile: Equatable, Sendable {
    let tile: TableTileMaterial
    let surface: TablePlayingSurface

    var isClassic: Bool { tile == .classic && surface == .wool }
    var recordingsFolder: String { "MaterialSounds/\(tile.rawValue)/\(surface.rawValue)" }
}

final class TableAudio: @unchecked Sendable {
    enum Cue: String, CaseIterable, Sendable {
        case shuffle, deal, discard, meld, kong, win

        var hasMaterialRecording: Bool {
            switch self {
            case .shuffle, .discard, .meld, .kong: true
            case .deal, .win: false
            }
        }

        var surfaceContact: Float {
            switch self {
            case .discard, .deal: 1
            case .shuffle: 0.7
            case .meld, .kong: 0.4
            case .win: 0
            }
        }
    }

    // The serial queue owns the players and keeps play, prepare, and stop in order.
    private let queue = DispatchQueue(label: "media.jenny.FuzhouMahjong.table-audio", qos: .userInitiated)
    private var players: [Cue: AVAudioPlayer] = [:]
    private var playing: Cue?
    private var preparedProfile: TableFeedbackProfile?

    func prepare(for profile: TableFeedbackProfile) {
        queue.async { self.preparePlayback(for: profile) }
    }

    private func preparePlayback(for profile: TableFeedbackProfile) {
        guard preparedProfile != profile else { return }
        stopPlayback()
        players.removeAll()
        preparedProfile = profile
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        for cue in Cue.allCases {
            guard let sample = recording(for: cue, profile: profile),
                  let player = try? AVAudioPlayer(data: sample) else { continue }
            player.prepareToPlay()
            players[cue] = player
        }
    }

    func recording(for cue: Cue, profile: TableFeedbackProfile) -> Data? {
        if cue.hasMaterialRecording,
           let file = Bundle.main.url(forResource: cue.rawValue, withExtension: "wav",
                                      subdirectory: profile.recordingsFolder),
           let sample = try? Data(contentsOf: file) {
            return sample
        }
        let fallback = cue == .kong ? Cue.meld : cue
        guard let file = Bundle.main.url(forResource: fallback.rawValue, withExtension: "wav") else { return nil }
        if cue != .win, !profile.isClassic, let tuned = tunedRecording(file, cue: cue, profile: profile) {
            return tuned
        }
        return try? Data(contentsOf: file)
    }

    func play(_ cue: Cue, profile: TableFeedbackProfile, volume: Float) {
        queue.async {
            self.preparePlayback(for: profile)
            guard let player = self.players[cue] else { return }
            if let playing = self.playing, playing != cue {
                // A quick discard can follow a claim before its short landing sound has finished.
                let followsClaim = cue == .discard && (playing == .meld || playing == .kong)
                if !followsClaim { self.players[playing]?.stop() }
            }
            player.volume = volume
            player.currentTime = 0
            if player.play() { self.playing = cue }
        }
    }

    func stop(_ cue: Cue) {
        queue.async { self.players[cue]?.stop() }
    }

    func stop() {
        queue.async { self.stopPlayback() }
    }

    private func stopPlayback() {
        for player in players.values { player.stop() }
        playing = nil
    }

    private func tunedRecording(_ url: URL, cue: Cue, profile: TableFeedbackProfile) -> Data? {
        guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
              file.processingFormat.channelCount == 1, file.length > 0, file.length <= 96_000,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil, let input = buffer.floatChannelData?[0] else { return nil }

        let sampleRate = Float(file.processingFormat.sampleRate)
        let bodyStep = 1 - exp(-2 * .pi * 950 / sampleRate)
        let edgeStep = 1 - exp(-2 * .pi * 3600 / sampleRate)
        let tone = profile.tile.tone
        let damping = profile.surface.damping
        let edge = tone.edge * (1 - damping.edge * cue.surfaceContact)
        let decay = cue == .shuffle ? 0 : tone.decay + damping.decay * cue.surfaceContact
        var body: Float = 0
        var mid: Float = 0
        var sourcePeak: Float = 0
        var tunedPeak: Float = 0
        var recording: [Float] = []
        recording.reserveCapacity(Int(buffer.frameLength))
        for index in 0..<Int(buffer.frameLength) {
            let sample = input[index]
            body += bodyStep * (sample - body)
            mid += edgeStep * (sample - mid)
            // Keep the onset audible while the surface softens the high end and landing tail.
            let envelope = exp(-decay * max(0, Float(index) / sampleRate - 0.014))
            let output = (body * tone.body + (mid - body) + (sample - mid) * edge) * envelope
            recording.append(output)
            sourcePeak = max(sourcePeak, abs(sample))
            tunedPeak = max(tunedPeak, abs(output))
        }
        let level = tunedPeak > 0 ? min(sourcePeak / tunedPeak, 1.7) : 1
        let pcm = recording.map { Int16(max(-1, min(1, $0 * level)) * Float(Int16.max)) }
        return Self.wave(pcm, sampleRate: UInt32(sampleRate))
    }

    private static func wave(_ samples: [Int16], sampleRate: UInt32) -> Data {
        let bytes = UInt32(samples.count * MemoryLayout<Int16>.size)
        var data = Data("RIFF".utf8)
        data.appendLittleEndian(36 + bytes)
        data.append(contentsOf: "WAVEfmt ".utf8)
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(sampleRate)
        data.appendLittleEndian(sampleRate * 2)
        data.appendLittleEndian(UInt16(2))
        data.appendLittleEndian(UInt16(16))
        data.append(contentsOf: "data".utf8)
        data.appendLittleEndian(bytes)
        for sample in samples { data.appendLittleEndian(sample) }
        return data
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
