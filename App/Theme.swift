import FuzhouCore
import SwiftUI
import UIKit

enum TeaTheme {
    static let canvas = adaptive(0xF6F2E9, 0x1B211D)
    static let surface = adaptive(0xEAE8DB, 0x262E27)
    static let ink = adaptive(0x242C25, 0xF4ECDC)
    static let muted = adaptive(0x555E53, 0xB6BBAE)
    static let line = adaptive(0xD8D6C9, 0x40483E)
    static let gain = adaptive(0x285D43, 0x9BD9B1)
    static let loss = adaptive(0x8F392B, 0xFFB9A5)
    static let felt = color(0x244237)
    static let feltDark = color(0x1A3329)
    static let feltInk = color(0xF1EAD5)
    static let wood = color(0x49382A)
    static let brass = color(0xEAD3A2)
    static let brassInk = color(0x27291D)
    static let porcelain = color(0xFFFDF2)
    static let tileShade = color(0xE9DEBC)
    static let tileEdge = color(0xBBA57A)
    static let tileInk = color(0x25362E)
    static let tileRed = color(0x903D2F)
    static let pipBlue = color(0x405D63)
    static let pipGreen = color(0x3E6152)
    static let goldShade = color(0xFFE2A1)

    static let gutter: CGFloat = 16
    static let tableGutter: CGFloat = 12
    static let hitTarget: CGFloat = 44
    static let controlCorner: CGFloat = 14
    static let surfaceCorner: CGFloat = 18
    static let tableCorner: CGFloat = 25

    private static func color(_ value: UInt32) -> Color {
        let (r, g, b) = channels(value)
        return Color(red: r, green: g, blue: b)
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let (r, g, b) = channels(traits.userInterfaceStyle == .dark ? dark : light)
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
    }

    private static func channels(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
        (CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255)
    }
}

struct TeaButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(prominent && isEnabled ? TeaTheme.brassInk : TeaTheme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minWidth: TeaTheme.hitTarget, minHeight: TeaTheme.hitTarget)
            .background(prominent && isEnabled ? TeaTheme.brass : TeaTheme.surface,
                        in: RoundedRectangle(cornerRadius: TeaTheme.controlCorner))
            .overlay {
                RoundedRectangle(cornerRadius: TeaTheme.controlCorner)
                    .strokeBorder(prominent && isEnabled ? .clear : TeaTheme.line)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.77 : 1) : 0.55)
    }
}

struct SeatBadge: View {
    var seat: Seat
    var highlighted = false

    var body: some View {
        Text(seat.wind)
            .font(.caption.weight(.semibold))
            .foregroundStyle(highlighted ? TeaTheme.brassInk : TeaTheme.feltInk)
            .frame(minWidth: 24, minHeight: 24)
            .padding(.horizontal, 2)
            .background(highlighted ? TeaTheme.brass : TeaTheme.feltDark, in: Circle())
    }
}

struct Felt: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                Image("WalnutTable")
                    .resizable()
                    .clipShape(RoundedRectangle(cornerRadius: TeaTheme.tableCorner))
                    .accessibilityHidden(true)
            }
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
