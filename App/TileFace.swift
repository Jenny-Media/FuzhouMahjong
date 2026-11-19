import FuzhouCore
import SwiftUI

enum TileStyle: String, CaseIterable {
    case classic
    case modern

    var title: LocalizedStringKey {
        switch self {
        case .classic: "经典"
        case .modern: "现代"
        }
    }

    fileprivate var assetPrefix: String {
        switch self {
        case .classic: "Face"
        case .modern: "ModernFace"
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
            let modern = tileStyle == .modern
            let selectionWidth: CGFloat = modern ? 2.5 : 2

            ZStack {
                Image(kind.artworkName(for: tileStyle))
                    .resizable()
                    .accessibilityHidden(true)
                if gold && !modern { shape.fill(TeaTheme.goldShade.opacity(0.46)).blendMode(.multiply) }
            }
            .frame(width: width, height: height)
            .clipShape(shape)
            .overlay {
                if gold && modern {
                    shape.inset(by: selected ? selectionWidth : 0)
                        .strokeBorder(TeaTheme.modernTileGoldEdge, lineWidth: min(2, width * 0.085))
                }
                if selected {
                    shape.strokeBorder(modern ? TeaTheme.modernTileSelection : TeaTheme.brass,
                                       lineWidth: selectionWidth)
                }
            }
            .overlay(alignment: .topTrailing) {
                if gold, width >= 26 {
                    Text("金")
                        .font(.system(size: min(11, width * 0.27), weight: .bold))
                        .foregroundStyle(modern ? TeaTheme.brassInk : TeaTheme.porcelain)
                        .padding(.horizontal, modern ? 3 : 2)
                        .padding(.vertical, modern ? 1 : 2)
                        .background(modern ? TeaTheme.modernTileGoldBadge : TeaTheme.wood,
                                    in: RoundedRectangle(cornerRadius: 3))
                        .offset(x: modern ? 0 : 1, y: modern ? 0 : -2)
                        .accessibilityHidden(true)
                }
            }
            .shadow(color: .black.opacity(0.24), radius: selected ? 3 : 1, y: selected ? 3 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel(gold ? "\(kind.spokenName)，金牌" : kind.spokenName)
    }
}

struct TileBack: View {
    var body: some View {
        Image("JadeTileBack")
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
