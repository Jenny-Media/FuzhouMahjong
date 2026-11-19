import FuzhouCore
import SwiftUI
import UIKit

enum TeaTheme {
    static let canvas = adaptive(0xF2F0EC, 0x101922)
    static let surface = adaptive(0xFCFAF6, 0x1C2933)
    static let ink = adaptive(0x25323C, 0xF6EDDA)
    static let muted = adaptive(0x4D5E6C, 0xB9C7C6)
    static let line = adaptive(0xBEC7CD, 0x3E5160)
    static let gain = adaptive(0x22614D, 0xA5D6BF)
    static let loss = adaptive(0x963A2B, 0xFFB49F)
    static let feltDark = adaptive(0xE2E9EC, 0x142B36)
    static let feltInk = ink
    static let wood = color(0x50392A)
    static let brass = adaptive(0x215D61, 0xF0D29A)
    static let brassInk = adaptive(0xFFFFFF, 0x292115)
    static let brassShade = adaptive(0x49777C, 0xBD965C)
    static let porcelain = color(0xFFFDF2)
    static let goldShade = color(0xFFE2A1)
    static let modernTileSelection = color(0x176F88)
    static let modernTileGoldEdge = color(0xAD710C)
    static let modernTileGoldBadge = color(0xFFD77D)

    static let gutter: CGFloat = 16
    static let tableGutter: CGFloat = 12
    static let hitTarget: CGFloat = 44
    static let controlCorner: CGFloat = 14
    static let surfaceCorner: CGFloat = 18
    static let tableCorner: CGFloat = 25
    static let tableRailCorner: CGFloat = 10
    static let contentWidth: CGFloat = 620

    static let brassFinish = LinearGradient(colors: [adaptive(0x347578, 0xF7E1B3), brass,
                                                    adaptive(0x164F54, 0xBD965C)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
    static let panelFinish = LinearGradient(colors: [surface, adaptive(0xE8ECEC, 0x18242E)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
    static let railFinish = LinearGradient(colors: [color(0x846044), wood, color(0x291C14)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing)
    static let backdrop = RadialGradient(colors: [adaptive(0xFCFAF5, 0x263A48), canvas], center: .top,
                                         startRadius: 0, endRadius: 530)
    static let display = Font.system(.largeTitle, design: .serif, weight: .bold)

    static func color(_ hex: UInt32, brightness: Double = 1) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255 * brightness,
              green: Double((hex >> 8) & 255) / 255 * brightness,
              blue: Double(hex & 255) / 255 * brightness)
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

extension View {
    func teaBackdrop() -> some View {
        background { TeaTheme.backdrop.ignoresSafeArea() }
    }

    func teaPanel(corner: CGFloat = TeaTheme.surfaceCorner, emphasized: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner)
        return background(TeaTheme.panelFinish, in: shape)
            .overlay { shape.strokeBorder(emphasized ? TeaTheme.brassShade : TeaTheme.line).allowsHitTesting(false) }
    }

    func teaFooter() -> some View {
        background(TeaTheme.canvas)
            .overlay(alignment: .top) { Rectangle().fill(TeaTheme.line).frame(height: 1).allowsHitTesting(false) }
    }
}

struct TeaButtonStyle: ButtonStyle {
    var prominent = true
    var verticalPadding: CGFloat = 6
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let raised = prominent && isEnabled
        let shape = RoundedRectangle(cornerRadius: TeaTheme.controlCorner)
        return configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(raised ? TeaTheme.brassInk : TeaTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, verticalPadding)
            .frame(minWidth: TeaTheme.hitTarget, minHeight: TeaTheme.hitTarget)
            .background(raised ? TeaTheme.brassFinish : TeaTheme.panelFinish, in: shape)
            .overlay { shape.strokeBorder(raised ? TeaTheme.brass : TeaTheme.line).allowsHitTesting(false) }
            .opacity(isEnabled ? (configuration.isPressed ? 0.77 : 1) : 0.55)
    }
}

struct SeatBadge: View {
    var seat: Seat
    var highlighted = false
    var board: BoardStyle?

    var body: some View {
        Text(seat.wind)
            .font(.system(.caption, design: .serif, weight: .bold))
            .foregroundStyle(highlighted ? (board?.accentInk ?? TeaTheme.brassInk) : (board?.ink ?? TeaTheme.feltInk))
            .frame(minWidth: 24, minHeight: 24)
            .background(highlighted ? (board?.accent ?? TeaTheme.brass) : (board?.seatSurface ?? TeaTheme.feltDark),
                        in: Circle())
            .overlay { Circle().strokeBorder((board?.accent ?? TeaTheme.brassShade).opacity(0.65)) }
    }
}

struct Felt: ViewModifier {
    var inlaid = false
    var gameTable = false
    @Environment(\.boardStyle) private var board
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let rim = RoundedRectangle(cornerRadius: TeaTheme.tableCorner)
        let cloth = RoundedRectangle(cornerRadius: TeaTheme.tableCorner - 6)
        return content.background {
            Group {
                if gameTable && board == .jadeWalnut {
                    jadeTexture
                        .clipShape(RoundedRectangle(cornerRadius: TeaTheme.tableRailCorner, style: .circular))
                        .padding(1)
                        .overlay { TableRail(board: board) }
                } else if gameTable {
                    materialTable
                } else {
                    panelTexture
                        .clipShape(cloth)
                        .overlay {
                            cloth.strokeBorder(TeaTheme.brassShade.opacity(0.52))
                            if inlaid {
                                cloth.inset(by: 7).strokeBorder(TeaTheme.brass.opacity(0.22), lineWidth: 1)
                            }
                        }
                        .padding(6)
                        .background(scheme == .light ? TeaTheme.panelFinish : TeaTheme.railFinish, in: rim)
                        .overlay { rim.strokeBorder(TeaTheme.brass.opacity(0.29)) }
                }
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.18), radius: 8, y: 5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var materialTable: some View {
        let rim = RoundedRectangle(cornerRadius: TeaTheme.tableRailCorner, style: .circular)
        return tabletopSurface(board.cloth, texture: board.surface.artwork)
            .overlay {
                LinearGradient(colors: [.white.opacity(0.09), .clear, .black.opacity(0.10)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .clipShape(rim)
            .padding(1)
            .overlay { TableRail(board: board) }
    }

    @ViewBuilder private var panelTexture: some View {
        if scheme == .light { tabletopSurface(TeaTheme.feltDark, texture: TablePlayingSurface.wool.artwork) }
        else { jadeTexture }
    }

    private func tabletopSurface(_ color: Color, texture: String) -> some View {
        color.overlay {
            Image(decorative: texture)
                .resizable(resizingMode: .tile)
                .saturation(0)
                .blendMode(.overlay)
                .opacity(0.26)
        }
    }

    private var jadeTexture: some View {
        GeometryReader { geometry in
            Image("WalnutTable")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(1.16)
        }
        .overlay {
            RadialGradient(colors: [.clear, TeaTheme.color(0x102D23).opacity(0.5)],
                           center: .center, startRadius: 30, endRadius: 290)
        }
    }
}

private struct TableRail: View {
    let board: BoardStyle

    // The 3x sprites use slightly different padding in their alpha channels.
    private let scale: CGFloat = 0.5
    private var clearMargin: CGFloat { board == .jadeWalnut ? 49 / 3 : 42 / 3 }
    private let cornerCaps = EdgeInsets(top: 43, leading: 43, bottom: 43, trailing: 43)

    var body: some View {
        GeometryReader { geometry in
            Image(decorative: board.railArtwork)
                .resizable(capInsets: cornerCaps, resizingMode: .stretch)
                .frame(width: geometry.size.width / scale + clearMargin * 2,
                       height: geometry.size.height / scale + clearMargin * 2)
                .scaleEffect(scale)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .clipped()
    }
}

extension Seat {
    var wind: String {
        switch self {
        case .east: "东"
        case .south: "南"
        case .west: "西"
        case .north: "北"
        }
    }

    var practiceName: String {
        switch self {
        case .east: "电脑甲"
        case .south: "你"
        case .west: "电脑乙"
        case .north: "电脑丙"
        }
    }
}
