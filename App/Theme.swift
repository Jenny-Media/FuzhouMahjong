import FuzhouCore
import SwiftUI

enum TeaTheme {
    static let canvas = color(0x101B17)
    static let surface = color(0x1B2B24)
    static let ink = color(0xF6EDDA)
    static let muted = color(0xB6C6B9)
    static let line = color(0x3D5245)
    static let gain = color(0xA5D6BF)
    static let loss = color(0xFFB49F)
    static let feltDark = color(0x102D23)
    static let feltInk = ink
    static let wood = color(0x50392A)
    static let brass = color(0xF0D29A)
    static let brassInk = color(0x292115)
    static let brassShade = color(0xBD965C)
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

    static let brassFinish = LinearGradient(colors: [color(0xF7E1B3), brass, brassShade],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
    static let panelFinish = LinearGradient(colors: [surface, color(0x17251E)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
    static let railFinish = LinearGradient(colors: [color(0x846044), wood, color(0x291C14)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing)
    static let backdrop = RadialGradient(colors: [color(0x233C30), canvas], center: .top,
                                         startRadius: 0, endRadius: 530)
    static let display = Font.system(.largeTitle, design: .serif, weight: .bold)

    private static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255)
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
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let raised = prominent && isEnabled
        let shape = RoundedRectangle(cornerRadius: TeaTheme.controlCorner)
        return configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(raised ? TeaTheme.brassInk : TeaTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minWidth: TeaTheme.hitTarget, minHeight: TeaTheme.hitTarget)
            .background(raised ? TeaTheme.brassFinish : TeaTheme.panelFinish, in: shape)
            .overlay { shape.strokeBorder(raised ? TeaTheme.brass : TeaTheme.line).allowsHitTesting(false) }
            .opacity(isEnabled ? (configuration.isPressed ? 0.77 : 1) : 0.55)
    }
}

struct SeatBadge: View {
    var seat: Seat
    var highlighted = false

    var body: some View {
        Text(seat.wind)
            .font(.system(.caption, design: .serif, weight: .bold))
            .foregroundStyle(highlighted ? TeaTheme.brassInk : TeaTheme.feltInk)
            .frame(minWidth: 24, minHeight: 24)
            .background(highlighted ? TeaTheme.brass : TeaTheme.feltDark, in: Circle())
            .overlay { Circle().strokeBorder(TeaTheme.brassShade.opacity(0.65)) }
    }
}

struct Felt: ViewModifier {
    var inlaid = false
    var walnutRail = false

    func body(content: Content) -> some View {
        let rim = RoundedRectangle(cornerRadius: TeaTheme.tableCorner)
        let cloth = RoundedRectangle(cornerRadius: TeaTheme.tableCorner - 6)
        return content.background {
            Group {
                if walnutRail {
                    feltTexture
                        .clipShape(RoundedRectangle(cornerRadius: TeaTheme.tableRailCorner, style: .circular))
                        .padding(1)
                        .overlay { WalnutRail() }
                } else {
                    feltTexture
                        .clipShape(cloth)
                        .overlay {
                            cloth.strokeBorder(TeaTheme.brassShade.opacity(0.52))
                            if inlaid {
                                cloth.inset(by: 7).strokeBorder(TeaTheme.brass.opacity(0.22), lineWidth: 1)
                            }
                        }
                        .padding(6)
                        .background(TeaTheme.railFinish, in: rim)
                        .overlay { rim.strokeBorder(TeaTheme.brass.opacity(0.29)) }
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var feltTexture: some View {
        GeometryReader { geometry in
            Image("WalnutTable")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(1.16)
        }
        .overlay {
            RadialGradient(colors: [.clear, TeaTheme.feltDark.opacity(0.5)],
                           center: .center, startRadius: 30, endRadius: 290)
        }
    }
}

private struct WalnutRail: View {
    // The 3x original has 49 transparent pixels outside the wood. At half scale the rail is about 6 pt wide.
    private let scale: CGFloat = 0.5
    private let clearMargin: CGFloat = 49 / 3
    private let cornerCaps = EdgeInsets(top: 43, leading: 43, bottom: 43, trailing: 43)

    var body: some View {
        GeometryReader { geometry in
            Image(decorative: "WalnutRail")
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
