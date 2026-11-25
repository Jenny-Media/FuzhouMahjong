import FuzhouCore
import SwiftUI
import UIKit

enum TileMaterialStyle: String, CaseIterable {
    case automatic, classic, porcelain, ivoryRedwood, redwood, paleJade, creamBakelite
    case frostedGlass, bambooPorcelain, blackLacquer

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
        case .redwood: "紫檀"
        case .paleJade: "青白玉"
        case .creamBakelite: "奶油电木"
        case .frostedGlass: "冰蓝琉璃"
        case .bambooPorcelain: "竹背瓷面"
        case .blackLacquer: "缎面黑漆"
        }
    }

    func resolved(for scheme: ColorScheme) -> Self {
        self == .automatic ? (scheme == .dark ? .classic : .porcelain) : self
    }

    var material: TableTileMaterial {
        switch self {
        case .automatic, .classic: .classic
        case .porcelain, .frostedGlass: .porcelain
        case .ivoryRedwood, .redwood, .bambooPorcelain: .ivoryRedwood
        case .paleJade: .paleJade
        case .creamBakelite, .blackLacquer: .creamBakelite
        }
    }

    var frontArtwork: String {
        switch self {
        case .ivoryRedwood: "IvoryRedwoodFront"
        case .redwood: "RedwoodTileFront"
        case .paleJade: "PaleJadeFront"
        case .creamBakelite: "CreamBakeliteFront"
        case .frostedGlass: "FrostedGlassFront"
        case .blackLacquer: "BlackLacquerFront"
        case .automatic, .classic, .porcelain, .bambooPorcelain: "PorcelainTile"
        }
    }

    var backArtwork: String {
        switch self {
        case .automatic, .classic: "JadeTileBack"
        case .porcelain: "PorcelainTileBack"
        case .ivoryRedwood, .redwood: "IvoryRedwoodBack"
        case .paleJade: "PaleJadeBack"
        case .creamBakelite: "CreamBakeliteBack"
        case .frostedGlass: "FrostedGlassBack"
        case .bambooPorcelain: "BambooPorcelainBack"
        case .blackLacquer: "BlackLacquerBack"
        }
    }

    fileprivate var usesLightInk: Bool { self == .redwood || self == .blackLacquer }
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
    var showsGoldBadge = true

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, geometry.size.height * Self.artworkAspectRatio)
            let height = width / Self.artworkAspectRatio
            let shape = RoundedRectangle(cornerRadius: width * 0.13)
            // Keep the nested gold and selection outlines within the unprinted margin.
            let selectionWidth = min(tileMaterial == .classic ? 2 : 2.5, width * (gold ? 0.045 : 0.075))
            let goldWidth = min(2, width * (selected ? 0.03 : 0.06))
            let goldEdge = tileMaterial.usesLightInk ? TeaTheme.modernTileGoldBadge : TeaTheme.modernTileGoldEdge
            let selectionEdge = switch tileMaterial {
            case .classic: TeaTheme.color(0xF0D29A)
            case .redwood: TeaTheme.color(0x94D5F2)
            case .blackLacquer: TeaTheme.color(0x86CCD1)
            default: TeaTheme.modernTileSelection
            }
            ZStack {
                artwork
                if gold && tileMaterial == .classic {
                    shape.fill(TeaTheme.goldShade.opacity(0.46)).blendMode(.multiply)
                }
            }
            .frame(width: width, height: height)
            .clipShape(shape)
            .overlay {
                if gold {
                    let inset = selected ? selectionWidth : 0
                    let goldShape = shape.inset(by: inset)
                    let cornerSize = min(8, width * 0.19)
                    goldShape.strokeBorder(goldEdge, lineWidth: goldWidth)
                        .overlay(alignment: .topTrailing) {
                            GoldTileCorner()
                                .fill(goldEdge)
                                .frame(width: cornerSize, height: cornerSize)
                                .padding(inset)
                                .flipsForRightToLeftLayoutDirection(true)
                        }
                        .clipShape(goldShape)
                }
                if selected {
                    shape.strokeBorder(selectionEdge, lineWidth: selectionWidth)
                }
            }
            .overlay(alignment: .topTrailing) {
                if gold && showsGoldBadge && width >= 26 {
                    goldBadge(width: width)
                }
            }
            .shadow(color: .black.opacity(0.24), radius: selected ? 3 : 1, y: selected ? 3 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel(gold ? "\(kind.spokenName)，金牌" : kind.spokenName)
    }

    private func goldBadge(width: CGFloat) -> some View {
        let classic = tileMaterial == .classic
        return Text("金")
            .font(.system(size: min(11, width * 0.27), weight: .bold))
            .foregroundStyle(classic ? TeaTheme.porcelain : TeaTheme.color(0x292115))
            .padding(.horizontal, classic ? 2 : 3)
            .padding(.vertical, classic ? 2 : 1)
            .background(classic ? TeaTheme.wood : TeaTheme.modernTileGoldBadge,
                        in: RoundedRectangle(cornerRadius: 3))
            .offset(x: classic ? 1 : 0, y: classic ? -2 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var artwork: some View {
        Image(decorative: tileMaterial.frontArtwork)
            .resizable()
            .saturation(tileMaterial == .porcelain ? 0.28 : 1)
            .brightness(tileMaterial == .porcelain ? 0.05 : 0)
            .overlay {
                if let markings = TileMarkings.image(for: kind, style: faceStyle) {
                    Image(uiImage: markings)
                        .resizable()
                        .aspectRatio(Self.artworkAspectRatio, contentMode: .fit)
                        .brightness(tileMaterial.usesLightInk ? 0.52 : 0)
                        .accessibilityHidden(true)
                }
            }
    }
}

private struct GoldTileCorner: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
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
