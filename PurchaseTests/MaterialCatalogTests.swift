import AVFAudio
import CoreHaptics
import FuzhouCore
import SwiftUI
import XCTest
@testable import FuzhouMahjong

@MainActor
final class MaterialCatalogTests: XCTestCase {
    func testContactHapticsVaryAcrossMaterials() throws {
        let materials = Set(TileStyle.allCases.map(\.material))
        let surfaces = Set(BoardStyle.allCases.map(\.surface))

        let contacts: [(TableImpact, Int)] = [(.draw, 1), (.discard, 2), (.shuffle, 4), (.sweep, 2),
                                              (.meld, 3), (.kong, 4)]
        for (impact, pulseCount) in contacts {
            var patterns: Set<[TableHapticPulse]> = []
            for tile in materials {
                for surface in surfaces {
                    let pulses = impact.pulses(for: TableFeedbackProfile(tile: tile, surface: surface))
                    XCTAssertEqual(pulses.count, pulseCount)
                    XCTAssertTrue(pulses.allSatisfy {
                        (0...1).contains($0.intensity) && (0...1).contains($0.sharpness) && $0.time >= 0
                    })
                    XCTAssertTrue(zip(pulses, pulses.dropFirst()).allSatisfy { $0.time < $1.time })
                    _ = try CHHapticPattern(events: pulses.map(\.event), parameters: [])
                    patterns.insert(pulses)
                }
            }
            XCTAssertEqual(patterns.count, 15)
        }
    }

    func testDrawIsSilentAndEachMeldUsesItsContactSound() {
        XCTAssertNil(TableImpact.draw.sound)
        XCTAssertEqual(TableImpact(meld: .chow).sound, .meld)
        XCTAssertEqual(TableImpact(meld: .pung).sound, .meld)
        XCTAssertEqual(TableImpact(meld: .openKong).sound, .kong)
        XCTAssertEqual(TableImpact(meld: .concealedKong).sound, .kong)
        XCTAssertEqual(TableImpact(meld: .addedKong).sound, .kong)
    }

    func testThirtyPlayablePairingsHaveArtworkAndFeedback() throws {
        let boards = BoardStyle.allCases.filter { $0 != .automatic }
        let tiles = TileStyle.allCases.filter { $0 != .automatic }
        XCTAssertEqual(boards.count, 5)
        XCTAssertEqual(tiles.count, 6)
        XCTAssertEqual(BoardStyle.automatic.resolved(for: .light), .snowWhite)
        XCTAssertEqual(BoardStyle.automatic.resolved(for: .dark), .jadeWalnut)
        XCTAssertEqual(TileStyle.automatic.resolved(for: .light), .porcelain)
        XCTAssertEqual(TileStyle.automatic.resolved(for: .dark), .classic)

        let audio = TableAudio()
        let classic = TableFeedbackProfile(tile: .classic, surface: .wool)
        let win = try XCTUnwrap(audio.recording(for: .win, profile: classic))
        let materialCues: [TableAudio.Cue] = [.discard, .shuffle, .meld, .kong]
        var materialSounds: [TableAudio.Cue: Set<Data>] = [:]

        for board in boards {
            XCTAssertNotNil(UIImage(named: board.railArtwork), board.rawValue)
            XCTAssertNotNil(UIImage(named: board.surface.artwork), board.rawValue)
            for tile in tiles {
                XCTAssertEqual(board.resolved(for: .light), board)
                XCTAssertEqual(tile.resolved(for: .dark), tile)
                XCTAssertNotNil(UIImage(named: tile.backArtwork), tile.rawValue)
                if let face = tile.faceBodyArtwork {
                    XCTAssertNotNil(UIImage(named: face), tile.rawValue)
                }

                let profile = TableFeedbackProfile(tile: tile.material, surface: board.surface)
                for cue in TableAudio.Cue.allCases {
                    let sample = try XCTUnwrap(audio.recording(for: cue, profile: profile))
                    let player = try AVAudioPlayer(data: sample)
                    XCTAssertGreaterThan(player.duration, 0)
                    if materialCues.contains(cue) {
                        let folder = "MaterialSounds/\(tile.material.rawValue)/\(board.surface.rawValue)"
                        let file = try XCTUnwrap(Bundle.main.url(forResource: cue.rawValue, withExtension: "wav",
                                                                 subdirectory: folder), folder)
                        XCTAssertEqual(sample, try Data(contentsOf: file), "\(folder)/\(cue.rawValue)")
                        materialSounds[cue, default: []].insert(sample)
                    }
                    if cue == .win { XCTAssertEqual(sample, win) }
                }
            }
        }

        for cue in materialCues {
            XCTAssertEqual(materialSounds[cue]?.count, 15, cue.rawValue)
        }
    }
}
