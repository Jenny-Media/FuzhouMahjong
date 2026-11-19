import CoreHaptics
import FuzhouCore
import UIKit

struct TableHapticPulse: Hashable {
    let time: TimeInterval
    let intensity: Float
    let sharpness: Float

    var event: CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        ], relativeTime: time)
    }
}

enum TableImpact: Equatable {
    case shuffle, sweep, draw, discard, meld, kong

    init(meld: MeldKind) {
        switch meld {
        case .chow, .pung: self = .meld
        case .openKong, .concealedKong, .addedKong: self = .kong
        }
    }

    var sound: TableAudio.Cue? {
        switch self {
        case .shuffle: .shuffle
        case .discard: .discard
        case .meld: .meld
        case .kong: .kong
        case .draw, .sweep: nil
        }
    }

    func pulses(for profile: TableFeedbackProfile) -> [TableHapticPulse] {
        let tile = profile.tile.hapticCharacter
        let surface = profile.surface.hapticContact

        func pulse(_ time: TimeInterval, strength: Float, edge: Float = 1,
                   surfaceContact: Float = 1) -> TableHapticPulse {
            TableHapticPulse(time: time,
                             intensity: min(1, strength * tile.strength * (1 - surface.cushion * surfaceContact)),
                             sharpness: min(1, edge * tile.sharpness * (1 - surface.softening * surfaceContact)))
        }

        switch self {
        case .draw:
            // The landing is mostly tile against tile, with a lighter influence from the table.
            return [pulse(0, strength: 0.49, surfaceContact: 0.58)]
        case .discard:
            return [
                pulse(0, strength: 0.88),
                pulse(surface.settleDelay, strength: surface.rebound, edge: 0.58)
            ]
        case .shuffle:
            return [
                pulse(0, strength: 0.57, surfaceContact: 0.76),
                pulse(0.039, strength: 0.28, edge: 0.67),
                pulse(0.086, strength: 0.39, edge: 0.89, surfaceContact: 0.76),
                pulse(0.104 + surface.settleDelay, strength: 0.23, edge: 0.64)
            ]
        case .sweep:
            return [
                pulse(0, strength: 0.30, edge: 0.76),
                pulse(0.022 + surface.settleDelay, strength: 0.20, edge: 0.60)
            ]
        case .meld:
            return [
                pulse(0, strength: 0.58, edge: 0.85),
                pulse(0.022, strength: 0.71),
                pulse(surface.settleDelay + 0.024, strength: 0.29, edge: 0.66)
            ]
        case .kong:
            return [
                pulse(0, strength: 0.51, edge: 0.85),
                pulse(0.024, strength: 0.70, edge: 0.83),
                pulse(0.049, strength: 0.88, edge: 0.92),
                pulse(surface.settleDelay + 0.051, strength: 0.36, edge: 0.66)
            ]
        }
    }

    fileprivate var fallbackWeight: CGFloat {
        switch self {
        case .shuffle: 0.72
        case .sweep: 0.37
        case .draw: 0.30
        case .discard: 0.68
        case .meld: 0.53
        case .kong: 0.77
        }
    }
}

private extension TableTileMaterial {
    var hapticCharacter: (strength: Float, sharpness: Float) {
        switch self {
        case .classic: (0.94, 0.64)
        case .porcelain: (0.77, 0.95)
        case .ivoryRedwood: (0.88, 0.32)
        case .paleJade: (1.10, 0.84)
        case .creamBakelite: (0.72, 0.46)
        }
    }

    var impact: (style: UIImpactFeedbackGenerator.FeedbackStyle, weight: CGFloat) {
        switch self {
        case .classic: (.medium, 1)
        case .porcelain: (.rigid, 0.84)
        case .ivoryRedwood: (.soft, 0.85)
        case .paleJade: (.rigid, 1.16)
        case .creamBakelite: (.light, 0.96)
        }
    }
}

private extension TablePlayingSurface {
    var hapticContact: (cushion: Float, softening: Float, settleDelay: TimeInterval, rebound: Float) {
        switch self {
        case .wool: (0.18, 0.26, 0.038, 0.32)
        case .suede: (0.34, 0.46, 0.052, 0.23)
        case .leather: (0.03, 0.06, 0.027, 0.43)
        }
    }

    var impactWeight: CGFloat {
        switch self {
        case .wool: 1
        case .suede: 0.76
        case .leather: 0.9
        }
    }
}

@MainActor
final class TableTouch {
    private var engine: CHHapticEngine?
    private var generators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    func play(_ impact: TableImpact, profile: TableFeedbackProfile) {
        if playCustom(impact.pulses(for: profile)) { return }

        let tile = profile.tile.impact
        let generator = impactGenerator(for: tile.style)
        generator.impactOccurred(intensity: min(1, impact.fallbackWeight * tile.weight * profile.surface.impactWeight))
        generator.prepare()
    }

    func prepare(for profile: TableFeedbackProfile) {
        impactGenerator(for: profile.tile.impact.style).prepare()
        _ = try? runningEngine()
    }

    func stop() {
        engine?.stop(completionHandler: nil)
        engine = nil
    }

    private func impactGenerator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        if let generator = generators[style] { return generator }
        let generator = UIImpactFeedbackGenerator(style: style)
        generators[style] = generator
        return generator
    }

    private func runningEngine() throws -> CHHapticEngine? {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        let engine: CHHapticEngine
        if let existing = self.engine {
            engine = existing
        } else {
            engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true
        }
        // Calling start also recovers after an idle shutdown or system interruption.
        try engine.start()
        self.engine = engine
        return engine
    }

    private func playCustom(_ pulses: [TableHapticPulse]) -> Bool {
        guard !pulses.isEmpty else { return false }
        do {
            guard let engine = try runningEngine() else { return false }
            let pattern = try CHHapticPattern(events: pulses.map(\.event), parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            stop()
            return false
        }
    }
}
