import FuzhouCore
import SwiftUI
import UIKit

enum GameAppearance: String, CaseIterable {
    case system, light, dark

    var title: LocalizedStringKey {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

extension View {
    func gameAppearance(_ appearance: GameAppearance) -> some View {
        background {
            WindowAppearance(style: appearance.interfaceStyle)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct WindowAppearance: UIViewRepresentable {
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> AppearanceView {
        let view = AppearanceView()
        view.style = style
        return view
    }

    func updateUIView(_ view: AppearanceView, context: Context) {
        view.style = style
    }

    final class AppearanceView: UIView {
        var style: UIUserInterfaceStyle = .unspecified {
            didSet { updateWindow() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            updateWindow()
        }

        private func updateWindow() {
            // Apply to this window so already-presented sheets update and System clears the override.
            guard let window, window.overrideUserInterfaceStyle != style else { return }
            window.overrideUserInterfaceStyle = style
        }
    }
}

enum BoardStyle: String, CaseIterable {
    case automatic, jadeWalnut, snowWhite, inkBlue, redwoodSuede, bronzeLeather

    var title: LocalizedStringKey {
        switch self {
        case .automatic: "自动"
        case .jadeWalnut: "碧玉胡桃木"
        case .inkBlue: "墨蓝 · 枪灰金属"
        case .snowWhite: "雪白 · 白瓷"
        case .redwoodSuede: "紫檀 · 烟灰绒"
        case .bronzeLeather: "古铜 · 马鞍革"
        }
    }

    func resolved(for scheme: ColorScheme) -> BoardStyle {
        self == .automatic ? (scheme == .dark ? .jadeWalnut : .snowWhite) : self
    }

    private var clothRGB: UInt32 {
        switch self {
        case .automatic, .jadeWalnut: 0x164334
        case .inkBlue: 0x1F3548
        case .snowWhite: 0xADB7B6
        case .redwoodSuede: 0x4F4D4C
        case .bronzeLeather: 0x473731
        }
    }

    var cloth: Color { TeaTheme.color(clothRGB) }

    var surface: TablePlayingSurface {
        switch self {
        case .automatic, .jadeWalnut, .snowWhite, .inkBlue: .wool
        case .redwoodSuede: .suede
        case .bronzeLeather: .leather
        }
    }

    var railArtwork: String {
        switch self {
        case .automatic, .jadeWalnut: "WalnutRail"
        case .inkBlue: "GunmetalRail"
        case .snowWhite: "GlazedPorcelainRail"
        case .redwoodSuede: "RedwoodRail"
        case .bronzeLeather: "AgedBronzeRail"
        }
    }

    var trayEdge: Color {
        switch self {
        case .automatic, .jadeWalnut: TeaTheme.color(0xA27D60)
        case .inkBlue: TeaTheme.color(0xA5B0B8)
        case .snowWhite: TeaTheme.color(0xCFD4D3)
        case .redwoodSuede: TeaTheme.color(0xA7746D)
        case .bronzeLeather: TeaTheme.color(0xA78358)
        }
    }

    var tray: LinearGradient {
        switch self {
        case .automatic, .jadeWalnut: TeaTheme.railFinish
        case .snowWhite:
            LinearGradient(colors: [TeaTheme.color(0x757F80), TeaTheme.color(0x424D51)],
                           startPoint: .top, endPoint: .bottom)
        case .inkBlue, .redwoodSuede, .bronzeLeather:
            LinearGradient(colors: [cloth, seatSurface],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var ink: Color { TeaTheme.color(self == .snowWhite ? 0x26373A : 0xFFF6E7) }
    var muted: Color { TeaTheme.color(self == .snowWhite ? 0x304143 : 0xDEDFDA) }
    var accent: Color { TeaTheme.color(self == .snowWhite ? 0x123F41 : 0xF4D49E) }
    var accentInk: Color { TeaTheme.color(self == .snowWhite ? 0xFFFFFF : 0x20261F) }
    var seatSurface: Color {
        self == .snowWhite ? TeaTheme.color(0xE3E6DE) : TeaTheme.color(clothRGB, brightness: 0.60)
    }
}

extension EnvironmentValues {
    @Entry var boardStyle: BoardStyle = .jadeWalnut
}

struct AppearanceSettings: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var appearance: GameAppearance
    @Binding var boardStyle: BoardStyle
    @Binding var tileMaterial: TileMaterialStyle
    @Binding var tileFaceStyle: TileFaceStyle
    let hapticsEnabled: Bool

    var body: some View {
        Section("外观") {
            TableAppearancePreview()
                .environment(\.boardStyle, boardStyle.resolved(for: colorScheme))
                .environment(\.tileMaterial, tileMaterial.resolved(for: colorScheme))
                .environment(\.tileFaceStyle, tileFaceStyle)
                .listRowInsets(EdgeInsets(top: 9, leading: 9, bottom: 9, trailing: 9))

            appearancePicker("显示模式", id: "appearance-picker", selection: $appearance, title: \.title)
            appearancePicker("牌桌", id: "board-style-picker", selection: $boardStyle, title: \.title)
            appearancePicker("材质", id: "tile-material-picker", selection: $tileMaterial, title: \.title)
            appearancePicker("牌面", id: "tile-face-style-picker", selection: $tileFaceStyle, title: \.title)
        }
        .listRowBackground(TeaTheme.surface)
    }

    private func appearancePicker<Option: CaseIterable & Hashable>(
        _ label: LocalizedStringKey, id: String, selection: Binding<Option>, title: KeyPath<Option, LocalizedStringKey>
    ) -> some View {
        SwipeChoicePicker(label: label, id: id, selection: selection,
                          title: title, hapticsEnabled: hapticsEnabled)
    }
}

private struct SwipeChoicePicker<Option: CaseIterable & Hashable>: View {
    @Environment(\.layoutDirection) private var layoutDirection
    let label: LocalizedStringKey
    let id: String
    @Binding var selection: Option
    let title: KeyPath<Option, LocalizedStringKey>
    let hapticsEnabled: Bool

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(Array(Option.allCases), id: \.self) { option in
                Text(option[keyPath: title]).tag(option)
            }
        }
        .pickerStyle(.menu)
        .accessibilityValue(Text(selection[keyPath: title]))
        .accessibilityIdentifier(id)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background { HorizontalChoiceSwipe(onSwipe: selectBySwipe).accessibilityHidden(true) }
        .onChange(of: selection) {
            if hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
        }
    }

    private func selectBySwipe(horizontal: CGFloat, velocity: CGFloat, rowWidth: CGFloat) {
        let options = Array(Option.allCases)
        guard options.count > 1, let current = options.firstIndex(of: selection) else { return }

        let glide = horizontal * velocity > 0 ? abs(velocity) * 0.20 : 0
        let distance = abs(horizontal) + glide
        let stepWidth = min(110, max(66, rowWidth * 0.32))
        let steps = Int(min(CGFloat(options.count - 1), max(1, (distance / stepWidth).rounded())))
        let forward = layoutDirection == .leftToRight ? horizontal < 0 : horizontal > 0
        let destination = current + (forward ? steps : -steps) + options.count
        selection = options[destination % options.count]
    }
}

private struct HorizontalChoiceSwipe: UIViewRepresentable {
    let onSwipe: (CGFloat, CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> SwipeArea {
        let view = SwipeArea()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: SwipeArea, context: Context) {
        view.onSwipe = onSwipe
    }

    final class SwipeArea: UIView, UIGestureRecognizerDelegate {
        var onSwipe: ((CGFloat, CGFloat, CGFloat) -> Void)?
        private lazy var pan: UIPanGestureRecognizer = {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
            recognizer.delegate = self
            recognizer.maximumNumberOfTouches = 1
            return recognizer
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            pan.view?.removeGestureRecognizer(pan)
            guard window != nil else { return }

            // Let the Form scroll view arbitrate before a menu row takes over the drag.
            var ancestor = superview
            while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
            ancestor?.addGestureRecognizer(pan)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            bounds.contains(touch.location(in: self))
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.2
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            other === (pan.view as? UIScrollView)?.panGestureRecognizer
        }

        @objc private func handlePan() {
            guard pan.state == .ended else { return }
            let movement = pan.translation(in: pan.view)
            guard abs(movement.x) >= 24, abs(movement.x) > abs(movement.y) * 1.2 else { return }
            onSwipe?(movement.x, pan.velocity(in: pan.view).x, bounds.width)
        }
    }
}

private struct TableAppearancePreview: View {
    private let upperSamples = [TileKind(.circles, 1), TileKind(.circles, 8), TileKind(.circles, 9),
                                TileKind(.bamboo, 1), TileKind(.bamboo, 3), TileKind(.characters, 5)]
    private let lowerSamples = [TileKind(.wind, 1), TileKind(.dragon, 1), TileKind(.dragon, 3),
                                TileKind(.flower, 1), TileKind(.season, 1)]
    private let maximumTileWidth: CGFloat = 48
    private let spacing: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            let columns = CGFloat(upperSamples.count)
            let tileWidth = min(maximumTileWidth, max(0, (geometry.size.width - (columns - 1) * spacing) / columns))
            let tileHeight = tileWidth / TileFace.artworkAspectRatio
            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    faces(upperSamples, width: tileWidth, height: tileHeight)
                }
                HStack(spacing: spacing) {
                    faces(lowerSamples, width: tileWidth, height: tileHeight)
                    TileBack()
                        .frame(width: tileWidth, height: tileHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 2 * maximumTileWidth / TileFace.artworkAspectRatio + spacing)
        .padding(24)
        .modifier(Felt(gameTable: true))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("牌桌和麻将预览")
        .accessibilityIdentifier("table-appearance-preview")
    }

    private func faces(_ samples: [TileKind], width: CGFloat, height: CGFloat) -> some View {
        ForEach(samples, id: \.self) { kind in
            TileFace(kind: kind)
                .frame(width: width, height: height)
        }
    }
}
