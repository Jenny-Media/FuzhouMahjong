import FuzhouCore
import SwiftUI
import UIKit

enum TileStyle: String, CaseIterable {
    case automatic, classic, porcelain, modern, ivoryRedwood, paleJade, creamBakelite

    var title: LocalizedStringKey {
        switch self {
        case .automatic: "自动"
        case .classic: "经典"
        case .porcelain: "白釉瓷"
        case .modern: "现代"
        case .ivoryRedwood: "牙白 · 紫檀拼"
        case .paleJade: "青白玉"
        case .creamBakelite: "奶油电木"
        }
    }

    func resolved(for scheme: ColorScheme) -> TileStyle {
        self == .automatic ? (scheme == .dark ? .classic : .porcelain) : self
    }

    fileprivate var assetPrefix: String {
        self == .modern ? "ModernFace" : "Face"
    }

    var material: TableTileMaterial {
        switch self {
        case .automatic, .classic: .classic
        case .porcelain, .modern: .porcelain
        case .ivoryRedwood: .ivoryRedwood
        case .paleJade: .paleJade
        case .creamBakelite: .creamBakelite
        }
    }

    var faceBodyArtwork: String? {
        switch self {
        case .ivoryRedwood: "IvoryRedwoodFront"
        case .paleJade: "PaleJadeFront"
        case .creamBakelite: "CreamBakeliteFront"
        case .automatic, .classic, .porcelain, .modern: nil
        }
    }

    var backArtwork: String {
        switch self {
        case .automatic, .classic, .modern: "JadeTileBack"
        case .porcelain: "PorcelainTileBack"
        case .ivoryRedwood: "IvoryRedwoodBack"
        case .paleJade: "PaleJadeBack"
        case .creamBakelite: "CreamBakeliteBack"
        }
    }
}

extension EnvironmentValues {
    @Entry var tileStyle: TileStyle = .classic
}

struct TileFace: View {
    static let artworkAspectRatio: CGFloat = 192.0 / 268.0

    @Environment(\.tileStyle) private var tileStyle
    var kind: TileKind
    var gold = false
    var selected = false

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, geometry.size.height * Self.artworkAspectRatio)
            let height = width / Self.artworkAspectRatio
            let shape = RoundedRectangle(cornerRadius: width * 0.13)
            let crispIndicators = tileStyle != .classic
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

    @ViewBuilder private var artwork: some View {
        let face = Image(decorative: kind.artworkName(for: tileStyle)).resizable()
        if let body = tileStyle.faceBodyArtwork,
           let markings = TileMarkings.image(named: kind.artworkName(for: .modern)) {
            Image(decorative: body).resizable()
                .overlay { Image(uiImage: markings).resizable().accessibilityHidden(true) }
        } else if tileStyle == .porcelain {
            // Grade the full Classic sprite so the glaze, relief and bevel share one surface.
            face.saturation(0.86)
                .brightness(0.052)
                .colorMultiply(TeaTheme.color(0xF3F8FF))
        } else {
            face
        }
    }
}

@MainActor
private enum TileMarkings {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(named artwork: String) -> UIImage? {
        let key = artwork as NSString
        if let markings = cache.object(forKey: key) { return markings }
        guard let source = UIImage(named: artwork)?.cgImage else { return nil }
        let width = source.width
        let height = source.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                          CGBitmapInfo.byteOrder32Big.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Keep the antialiased pigments and remove the light substrate and outer bevel.
        let paper = 228
        let insetX = width * 6 / 100
        let insetY = height * 7 / 100
        for y in 0..<height {
            for x in 0..<width {
                let pixel = pixels.advanced(by: (y * width + x) * 4)
                let shade = Int(min(pixel[0], pixel[1], pixel[2]))
                let hasInk = x >= insetX && x < width - insetX && y >= insetY && y < height - insetY
                    && shade < 215
                let alpha = hasInk ? 255 - shade * 255 / paper : 0
                for channel in 0..<3 {
                    pixel[channel] = UInt8(min(alpha, max(0, Int(pixel[channel]) - shade)))
                }
                pixel[3] = UInt8(alpha)
            }
        }

        guard let output = context.makeImage() else { return nil }
        let markings = UIImage(cgImage: output)
        cache.setObject(markings, forKey: key)
        return markings
    }
}

struct TileBack: View {
    @Environment(\.tileStyle) private var tileStyle

    var body: some View {
        Image(decorative: tileStyle.backArtwork)
            .resizable()
            .scaledToFit()
            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            .accessibilityHidden(true)
    }
}

extension TileKind {
    fileprivate func artworkName(for style: TileStyle) -> String {
        let family = switch suit {
        case .characters: "characters"
        case .circles: "circles"
        case .bamboo: "bamboo"
        case .wind: "wind"
        case .dragon: "dragon"
        case .flower: "flower"
        case .season: "season"
        }
        return "\(style.assetPrefix)-\(family)-\(rank)"
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
