import FuzhouCore
import SwiftUI
import UIKit

enum TileMaterialStyle: String, CaseIterable {
    case automatic, classic, porcelain, ivoryRedwood, paleJade, creamBakelite

    init(storedValue: String) {
        // The old Modern option bundled different markings with a cool porcelain face.
        self = storedValue == "modern" ? .porcelain : Self(rawValue: storedValue) ?? .automatic
    }

    var title: LocalizedStringKey {
        switch self {
        case .automatic: "自动"
        case .classic: "暖白"
        case .porcelain: "白釉瓷"
        case .ivoryRedwood: "牙白 · 紫檀拼"
        case .paleJade: "青白玉"
        case .creamBakelite: "奶油电木"
        }
    }

    func resolved(for scheme: ColorScheme) -> Self {
        self == .automatic ? (scheme == .dark ? .classic : .porcelain) : self
    }

    var material: TableTileMaterial {
        switch self {
        case .automatic, .classic: .classic
        case .porcelain: .porcelain
        case .ivoryRedwood: .ivoryRedwood
        case .paleJade: .paleJade
        case .creamBakelite: .creamBakelite
        }
    }

    var frontArtwork: String {
        switch self {
        case .ivoryRedwood: "IvoryRedwoodFront"
        case .paleJade: "PaleJadeFront"
        case .creamBakelite: "CreamBakeliteFront"
        case .automatic, .classic, .porcelain: "PorcelainTile"
        }
    }

    var backArtwork: String {
        switch self {
        case .automatic, .classic: "JadeTileBack"
        case .porcelain: "PorcelainTileBack"
        case .ivoryRedwood: "IvoryRedwoodBack"
        case .paleJade: "PaleJadeBack"
        case .creamBakelite: "CreamBakeliteBack"
        }
    }
}

enum TileFaceStyle: String, CaseIterable {
    case photoMatched, minimal, traditional

    var title: LocalizedStringKey {
        switch self {
        case .photoMatched: "实物经典"
        case .minimal: "极简"
        case .traditional: "传统雕花"
        }
    }

    fileprivate var markingsArtwork: String {
        switch self {
        case .photoMatched: "PhotoMatchedMarkings"
        case .minimal: "MinimalMarkings"
        case .traditional: "TraditionalMarkings"
        }
    }
}

extension EnvironmentValues {
    @Entry var tileMaterial: TileMaterialStyle = .classic
    @Entry var tileFaceStyle: TileFaceStyle = .photoMatched
}

struct TileFace: View {
    nonisolated static let artworkAspectRatio: CGFloat = 192.0 / 268.0

    @Environment(\.tileMaterial) private var tileMaterial
    @Environment(\.tileFaceStyle) private var faceStyle
    var kind: TileKind
    var gold = false
    var selected = false

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, geometry.size.height * Self.artworkAspectRatio)
            let height = width / Self.artworkAspectRatio
            let shape = RoundedRectangle(cornerRadius: width * 0.13)
            let crispIndicators = tileMaterial != .classic
            let selectionWidth: CGFloat = crispIndicators ? 2.5 : 2

            ZStack {
                artwork
                if gold && !crispIndicators { shape.fill(TeaTheme.goldShade.opacity(0.46)).blendMode(.multiply) }
            }
            .frame(width: width, height: height)
            .clipShape(shape)
            .overlay {
                if gold && crispIndicators {
                    shape.inset(by: selected ? selectionWidth : 0)
                        .strokeBorder(TeaTheme.modernTileGoldEdge, lineWidth: min(2, width * 0.085))
                }
                if selected {
                    shape.strokeBorder(crispIndicators ? TeaTheme.modernTileSelection : TeaTheme.color(0xF0D29A),
                                       lineWidth: selectionWidth)
                }
            }
            .overlay(alignment: .topTrailing) {
                if gold, width >= 26 {
                    Text("金")
                        .font(.system(size: min(11, width * 0.27), weight: .bold))
                        .foregroundStyle(crispIndicators ? TeaTheme.color(0x292115) : TeaTheme.porcelain)
                        .padding(.horizontal, crispIndicators ? 3 : 2)
                        .padding(.vertical, crispIndicators ? 1 : 2)
                        .background(crispIndicators ? TeaTheme.modernTileGoldBadge : TeaTheme.wood,
                                    in: RoundedRectangle(cornerRadius: 3))
                        .offset(x: crispIndicators ? 0 : 1, y: crispIndicators ? 0 : -2)
                        .accessibilityHidden(true)
                }
            }
            .shadow(color: .black.opacity(0.24), radius: selected ? 3 : 1, y: selected ? 3 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel(gold ? "\(kind.spokenName)，金牌" : kind.spokenName)
    }

    private var artwork: some View {
        Image(decorative: tileMaterial.frontArtwork)
            .resizable()
            .saturation(tileMaterial == .porcelain ? 0.28 : 1)
            .brightness(tileMaterial == .porcelain ? 0.05 : 0)
            .overlay {
                if let markings = TileMarkings.image(for: kind, style: faceStyle) {
                    Image(uiImage: markings).resizable().accessibilityHidden(true)
                }
            }
    }
}

@MainActor
enum TileMarkings {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for kind: TileKind, style: TileFaceStyle) -> UIImage? {
        let artwork = style.markingsArtwork
        let index = kind.markingsIndex
        let key = "\(artwork)-\(index)" as NSString
        if let markings = cache.object(forKey: key) { return markings }
        guard let source = UIImage(named: artwork)?.cgImage else { return nil }
        // Each atlas has seven columns and six rows in Tile.fullSet's suit and rank order.
        let width = source.width / 7
        let height = source.height / 6
        guard let output = source.cropping(to: CGRect(x: index % 7 * width, y: index / 7 * height,
                                                      width: width, height: height)) else { return nil }
        let markings = UIImage(cgImage: output)
        cache.setObject(markings, forKey: key)
        return markings
    }
}

struct TileBack: View {
    @Environment(\.tileMaterial) private var tileMaterial

    var body: some View {
        Image(decorative: tileMaterial.backArtwork)
            .resizable()
            .scaledToFit()
            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            .accessibilityHidden(true)
    }
}

extension TileKind {
    fileprivate var markingsIndex: Int {
        let first = switch suit {
        case .characters: 0
        case .circles: 9
        case .bamboo: 18
        case .wind: 27
        case .dragon: 31
        case .flower: 34
        case .season: 38
        }
        return first + rank - 1
    }

    var rankText: String { ["一", "二", "三", "四", "五", "六", "七", "八", "九"][rank - 1] }

    var faceText: String {
        switch suit {
        case .wind: ["東", "南", "西", "北"][rank - 1]
        case .dragon: ["中", "發", "白"][rank - 1]
        case .flower: ["梅", "蘭", "菊", "竹"][rank - 1]
        case .season: ["春", "夏", "秋", "冬"][rank - 1]
        default: rankText
        }
    }

    var spokenName: String {
        switch suit {
        case .characters: rankText + "万"
        case .circles: rankText + "筒"
        case .bamboo: rankText + "条"
        case .dragon where rank == 3: "白板"
        default: faceText
        }
    }
}
