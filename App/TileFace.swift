import FuzhouCore
import SwiftUI
import UIKit

struct TileFace: View {
    var kind: TileKind
    var gold = false
    var selected = false

    private static let calligraphy = ["KaitiSC-Bold", "SongtiSC-Bold"].first { UIFont(name: $0, size: 20) != nil }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let shape = RoundedRectangle(cornerRadius: width * 0.13)

            ZStack {
                Image("PorcelainTile")
                    .resizable()
                    .accessibilityHidden(true)
                if gold { shape.fill(TeaTheme.goldShade.opacity(0.46)).blendMode(.multiply) }
                face(width: width, height: height)
                    .offset(y: -height * 0.015)
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(selected ? TeaTheme.brass : .clear, lineWidth: selected ? 2 : 0) }
            .overlay(alignment: .topTrailing) {
                if gold, width >= 26 {
                    Text("金")
                        .font(.system(size: min(11, width * 0.27), weight: .bold))
                        .foregroundStyle(TeaTheme.porcelain)
                        .padding(2)
                        .background(TeaTheme.wood, in: RoundedRectangle(cornerRadius: 3))
                        .offset(x: 1, y: -2)
                }
            }
            .shadow(color: .black.opacity(0.24), radius: selected ? 3 : 1, y: selected ? 3 : 1)
        }
        .accessibilityLabel(gold ? "\(kind.spokenName)，金牌" : kind.spokenName)
    }

    @ViewBuilder
    private func face(width: CGFloat, height: CGFloat) -> some View {
        switch kind.suit {
        case .bamboo where kind.rank == 1:
            Image(systemName: "bird.fill")
                .font(.system(size: width * 0.66, weight: .medium))
                .foregroundStyle(TeaTheme.pipGreen)
                .rotationEffect(.degrees(-10))
        case .circles, .bamboo:
            SuitMarkings(kind: kind)
        case .characters:
            VStack(spacing: -height * 0.05) {
                Text(kind.rankText).foregroundStyle(TeaTheme.tileInk)
                Text("萬").foregroundStyle(TeaTheme.tileRed)
            }
            .font(glyphFont(min(width * 0.62, height * 0.40)))
        case .wind, .dragon, .flower, .season:
            Text(kind.faceText)
                .font(glyphFont(width * 0.60))
                .foregroundStyle(kind.suit == .dragon && kind.rank == 1 ? TeaTheme.tileRed : TeaTheme.tileInk)
        }
    }

    private func glyphFont(_ size: CGFloat) -> Font {
        if let name = Self.calligraphy { return .custom(name, fixedSize: size) }
        return .system(size: size, weight: .semibold, design: .serif)
    }
}

struct TileBack: View {
    var body: some View {
        Image("JadeTileBack")
            .resizable()
            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            .accessibilityHidden(true)
    }
}

private struct SuitMarkings: View {
    let kind: TileKind

    private static let standard = [
        [], [4], [1, 7], [0, 4, 8], [0, 2, 6, 8], [0, 2, 4, 6, 8],
        [0, 2, 3, 5, 6, 8], [0, 1, 2, 3, 5, 6, 8], [], [0, 1, 2, 3, 4, 5, 6, 7, 8],
    ]

    var body: some View {
        Canvas { context, size in
            let points = positions
            for (index, point) in points.enumerated() {
                let center = CGPoint(x: point.x * size.width, y: point.y * size.height)
                if kind.suit == .circles {
                    let diameter = size.width * (kind.rank == 1 ? 0.57 : kind.rank == 8 ? 0.24 : 0.22)
                    wheel(at: center, diameter: diameter, ink: ink(for: index), in: context)
                } else {
                    stalk(at: center, width: size.width * 0.135,
                          height: size.height * (kind.rank == 8 ? 0.14 : 0.17), ink: ink(for: index), in: context)
                }
            }
        }
    }

    private var positions: [CGPoint] {
        if kind.rank == 8 {
            return (0..<8).map { CGPoint(x: $0.isMultiple(of: 2) ? 0.32 : 0.68, y: 0.23 + CGFloat($0 / 2) * 0.18) }
        }
        return Self.standard[kind.rank].map {
            CGPoint(x: 0.5 + CGFloat($0 % 3 - 1) * 0.235, y: 0.5 + CGFloat($0 / 3 - 1) * 0.245)
        }
    }

    private func ink(for index: Int) -> Color {
        if kind.rank == 1 || (kind.rank == 5 && index == 2) || (kind.rank == 7 && index < 3) {
            return TeaTheme.tileRed
        }
        if kind.suit == .circles && kind.rank.isMultiple(of: 2) { return TeaTheme.pipBlue }
        return TeaTheme.pipGreen
    }

    private func wheel(at center: CGPoint, diameter: CGFloat, ink: Color, in context: GraphicsContext) {
        let outer = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        context.fill(Path(ellipseIn: outer), with: .color(ink))
        let rim = outer.insetBy(dx: diameter * 0.19, dy: diameter * 0.19)
        context.stroke(Path(ellipseIn: rim), with: .color(TeaTheme.porcelain.opacity(0.88)), lineWidth: diameter * 0.10)
        if kind.rank == 1 {
            let hub = outer.insetBy(dx: diameter * 0.37, dy: diameter * 0.37)
            context.fill(Path(ellipseIn: hub), with: .color(TeaTheme.porcelain.opacity(0.9)))
        }
    }

    private func stalk(at center: CGPoint, width: CGFloat, height: CGFloat, ink: Color,
                       in context: GraphicsContext) {
        let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        context.fill(Path(roundedRect: rect, cornerRadius: width * 0.3), with: .color(ink))
        var joints = Path()
        for fraction in [0.34, 0.66] {
            let y = rect.minY + height * fraction
            joints.move(to: CGPoint(x: rect.minX, y: y))
            joints.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        context.stroke(joints, with: .color(TeaTheme.porcelain.opacity(0.7)), lineWidth: width * 0.18)
    }
}

extension TileKind {
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
        default: faceText
        }
    }
}
