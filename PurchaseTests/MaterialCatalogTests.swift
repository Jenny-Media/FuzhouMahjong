import AVFAudio
import CoreHaptics
import FuzhouCore
import SwiftUI
import XCTest
@testable import FuzhouMahjong

@MainActor
final class MaterialCatalogTests: XCTestCase {
    func testContactHapticsVaryAcrossMaterials() throws {
        let materials = Set(TileMaterialStyle.allCases.map(\.material))
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

    func testMaterialPairingsHaveArtworkAndFeedback() throws {
        let boards = BoardStyle.allCases.filter { $0 != .automatic }
        let tiles = TileMaterialStyle.allCases.filter { $0 != .automatic }
        XCTAssertEqual(boards.count, 5)
        XCTAssertEqual(tiles.count, 9)
        XCTAssertEqual(BoardStyle.automatic.resolved(for: .light), .snowWhite)
        XCTAssertEqual(BoardStyle.automatic.resolved(for: .dark), .jadeWalnut)
        XCTAssertEqual(TileMaterialStyle.automatic.resolved(for: .light), .porcelain)
        XCTAssertEqual(TileMaterialStyle.automatic.resolved(for: .dark), .classic)
        XCTAssertEqual(TileMaterialStyle(storedValue: "modern"), .porcelain)
        XCTAssertEqual(TileMaterialStyle.redwood.material, .ivoryRedwood)

        let audio = TableAudio()
        let classic = TableFeedbackProfile(tile: .classic, surface: .wool)
        let win = try XCTUnwrap(audio.recording(for: .win, profile: classic))
        let materialCues: [TableAudio.Cue] = [.discard, .shuffle, .meld, .kong]
        var materialSounds: [TableAudio.Cue: Set<Data>] = [:]

        for board in boards {
            XCTAssertNotNil(UIImage(named: board.railArtwork), board.rawValue)
            XCTAssertNotNil(UIImage(named: board.surface.artwork), board.rawValue)
            for tile in tiles {
                XCTAssertEqual(TileMaterialStyle(storedValue: tile.rawValue), tile)
                XCTAssertEqual(board.resolved(for: .light), board)
                XCTAssertEqual(tile.resolved(for: .dark), tile)
                XCTAssertNotNil(UIImage(named: tile.backArtwork), tile.rawValue)
                XCTAssertNotNil(UIImage(named: tile.frontArtwork), tile.rawValue)

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

    func testEachTileFaceStyleProvidesEveryMarking() throws {
        let kinds = Set(Tile.fullSet.map(\.kind))
        XCTAssertEqual(kinds.count, 42)
        for style in TileFaceStyle.allCases {
            for kind in kinds {
                let marking = try XCTUnwrap(TileMarkings.image(for: kind, style: style)?.cgImage,
                                            "\(style.rawValue): \(kind.spokenName)")
                XCTAssertEqual(marking.width, 192)
                XCTAssertEqual(marking.height, 268)
            }
        }
    }

    func testOneCircleMarkingsStayRound() throws {
        for style in TileFaceStyle.allCases {
            let context = try markingBitmap(for: TileKind(.circles, 1), style: style)
            let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            var bounds = CGRect.null
            for y in 0..<context.height {
                for x in 0..<context.width where pixels[(y * context.width + x) * 4 + 3] > 180 {
                    bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
            XCTAssertFalse(bounds.isNull, style.rawValue)
            XCTAssertEqual(bounds.width, bounds.height, accuracy: 4, style.rawValue)
        }
    }

    func testCharacterNumeralsStayClearOfWan() throws {
        let nearbyPixels = (-4...4).flatMap { y in
            (-4...4).filter { $0 * $0 + y * y < 25 }.map { (x: $0, y: y) }
        }
        for style in TileFaceStyle.allCases {
            for rank in 1...9 {
                let context = try markingBitmap(for: TileKind(.characters, rank), style: style)
                let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
                let width = context.width
                var numeralPixels: [Int] = []
                var wanPixels: Set<Int> = []
                for index in 0..<(width * context.height) {
                    let pixel = pixels.advanced(by: index * 4)
                    guard pixel[3] > 80 else { continue }
                    let red = Int(pixel[0]), green = Int(pixel[1]), blue = Int(pixel[2])
                    if blue > max(red, green) + 15 { numeralPixels.append(index) }
                    if red > max(blue, green) + 15 { wanPixels.insert(index) }
                }
                let face = "\(style.rawValue) rank \(rank)"
                XCTAssertFalse(numeralPixels.isEmpty, face)
                XCTAssertFalse(wanPixels.isEmpty, face)
                let crowded = numeralPixels.contains { index in
                    nearbyPixels.contains { offset in
                        let column = index % width + offset.x
                        let row = index / width + offset.y
                        return (0..<width).contains(column) && wanPixels.contains(row * width + column)
                    }
                }
                XCTAssertFalse(crowded, "\(face) has less than five pixels between the numeral and 萬")
            }
        }
    }

    private func markingBitmap(for kind: TileKind, style: TileFaceStyle) throws -> CGContext {
        let marking = try XCTUnwrap(TileMarkings.image(for: kind, style: style)?.cgImage)
        let context = try XCTUnwrap(CGContext(
            data: nil, width: marking.width, height: marking.height, bitsPerComponent: 8,
            bytesPerRow: marking.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.draw(marking, in: CGRect(x: 0, y: 0, width: marking.width, height: marking.height))
        return context
    }
}
