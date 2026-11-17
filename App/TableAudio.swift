import AVFAudio

@MainActor
final class TableAudio {
    enum Cue: String, CaseIterable {
        case shuffle, deal, draw, discard, meld, win
    }

    private var players: [Cue: AVAudioPlayer] = [:]
    private var playing: AVAudioPlayer?

    func prepare() {
        guard players.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        for cue in Cue.allCases {
            guard let file = Bundle.main.url(forResource: cue.rawValue, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: file) else { continue }
            players[cue] = player
        }
    }

    func play(_ cue: Cue, volume: Float) {
        prepare()
        guard let player = players[cue] else { return }
        if let playing, playing !== player { playing.stop() }
        player.volume = volume
        player.currentTime = 0
        if player.play() { playing = player }
    }

    func stop(_ cue: Cue) {
        players[cue]?.stop()
    }

    func stop() {
        for player in players.values { player.stop() }
        playing = nil
    }
}
