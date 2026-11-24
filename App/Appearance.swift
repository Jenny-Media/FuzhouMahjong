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
        Section {
            TableAppearancePreview()
                .environment(\.boardStyle, boardStyle.resolved(for: colorScheme))
                .environment(\.tileMaterial, tileMaterial.resolved(for: colorScheme))
                .environment(\.tileFaceStyle, tileFaceStyle)
                .listRowInsets(EdgeInsets(top: 9, leading: 9, bottom: 9, trailing: 9))

            ArcChoicePicker(label: "牌桌", id: "board-style-picker", selection: $boardStyle,
                            title: \.title, hapticsEnabled: hapticsEnabled) { option in
                AppearanceSwatch(corner: true) { Color.clear }
                    .environment(\.boardStyle, option.resolved(for: colorScheme))
            }
            .listRowInsets(turntableInsets)

            ArcChoicePicker(label: "材质", id: "tile-material-picker", selection: $tileMaterial,
                            title: \.title, hapticsEnabled: hapticsEnabled) { option in
                AppearanceSwatch {
                    TileFace(kind: TileKind(.characters, 6)).frame(width: 24, height: 34)
                    TileBack().frame(width: 24, height: 34)
                }
                .environment(\.boardStyle, boardStyle.resolved(for: colorScheme))
                .environment(\.tileMaterial, option.resolved(for: colorScheme))
                .environment(\.tileFaceStyle, tileFaceStyle)
            }
            .listRowInsets(turntableInsets)

            ArcChoicePicker(label: "牌面", id: "tile-face-style-picker", selection: $tileFaceStyle,
                            title: \.title, hapticsEnabled: hapticsEnabled) { option in
                AppearanceSwatch {
                    TileFace(kind: TileKind(.circles, 1)).frame(width: 24, height: 34)
                    TileFace(kind: TileKind(.circles, 8)).frame(width: 24, height: 34)
                    TileFace(kind: TileKind(.bamboo, 1)).frame(width: 24, height: 34)
                }
                .environment(\.boardStyle, boardStyle.resolved(for: colorScheme))
                .environment(\.tileMaterial, tileMaterial.resolved(for: colorScheme))
                .environment(\.tileFaceStyle, option)
            }
            .listRowInsets(turntableInsets)
        } header: {
            HStack {
                Text("外观")
                Spacer(minLength: 8)
                SwipeChoicePicker(label: "显示模式", id: "appearance-picker", selection: $appearance,
                                  title: \.title, hapticsEnabled: hapticsEnabled)
            }
        }
        .listRowBackground(TeaTheme.surface)
    }

    private var turntableInsets: EdgeInsets {
        EdgeInsets(top: 7, leading: 9, bottom: 5, trailing: 9)
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
        HStack(spacing: 5) {
            Text(label)
                .lineLimit(1)
                .foregroundStyle(TeaTheme.muted)
                .accessibilityHidden(true)
            Picker(label, selection: $selection) {
                ForEach(Array(Option.allCases), id: \.self) { option in
                    Text(option[keyPath: title]).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(selection[keyPath: title]))
            .accessibilityIdentifier(id)
        }
        .frame(minWidth: 144, minHeight: TeaTheme.hitTarget, alignment: .trailing)
        .contentShape(Rectangle())
        .background {
            HorizontalChoiceSwipe(minimumDistance: 18, onSwipe: selectBySwipe).accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(id)-swipe")
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

private struct ArcChoicePicker<Option: CaseIterable & Hashable, Swatch: View>: View {
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: RotationDrag?
    @State private var turn: Turn?

    let label: LocalizedStringKey
    let id: String
    @Binding var selection: Option
    let title: KeyPath<Option, LocalizedStringKey>
    let hapticsEnabled: Bool
    @ViewBuilder var swatch: (Option) -> Swatch

    private let options = Array(Option.allCases)
    private var selectedIndex: Int { options.firstIndex(of: selection) ?? 0 }
    private var readingDirection: CGFloat { layoutDirection == .leftToRight ? 1 : -1 }

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(label).font(.subheadline)
                Spacer(minLength: 8)
                Picker(label, selection: Binding(get: { selection }, set: selectFromMenu)) {
                    ForEach(options, id: \.self) { option in
                        Text(option[keyPath: title]).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel(Text(label))
                .accessibilityValue(Text(selection[keyPath: title]))
                .accessibilityIdentifier(id)
            }
            .padding(.horizontal, 7)

            HStack(spacing: 2) {
                arrow("chevron.backward", label: "上一项", by: -1)
                TimelineView(.animation(paused: turn == nil)) { context in
                    track(at: displayedPosition(on: context.date))
                }
                .frame(height: 66)
                .background {
                    HorizontalChoiceSwipe(onChange: followDrag, onCancel: cancelDrag, onSwipe: finishSwipe)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(label))
                .accessibilityValue(Text(selection[keyPath: title]))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: step(by: 1)
                    case .decrement: step(by: -1)
                    @unknown default: break
                    }
                }
                .accessibilityIdentifier("\(id)-arc")
                arrow("chevron.forward", label: "下一项", by: 1)
            }
        }
        .task(id: turn) {
            guard let pending = turn else { return }
            do { try await Task.sleep(for: .seconds(pending.duration)) }
            catch { return }
            guard turn == pending else { return }
            commit(pending.destination)
        }
        .onDisappear {
            if let turn { commit(turn.destination) }
            drag = nil
        }
        .onChange(of: selection) {
            if hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
        }
    }

    private func track(at position: CGFloat) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let anchor = Int(position.rounded(.down))
            ZStack {
                ForEach((anchor - 2)...(anchor + 2), id: \.self) { index in
                    let offset = CGFloat(index) - position
                    if abs(offset) < 1.7 {
                        let angle = offset * 0.74
                        let rise = 1 - cos(angle)
                        let tilt = offset * readingDirection
                        swatch(option(at: index))
                            .frame(width: width * 0.62, height: 50)
                            .scaleEffect(1 - rise * 0.34)
                            .rotation3DEffect(.degrees(tilt * 20), axis: (x: 0, y: 1, z: 0))
                            .rotationEffect(.degrees(-tilt * 4))
                            .offset(x: sin(angle) * width * 0.61 * readingDirection, y: 4 - rise * 36)
                            .opacity(min(1, 1.1 - abs(offset) * 0.24))
                            .zIndex(2 - abs(offset))
                            .onTapGesture { move(to: index) }
                    }
                }
            }
            .frame(width: width, height: geometry.size.height)
            .contentShape(Rectangle())
            .clipped()
        }
    }

    private func arrow(_ symbol: String, label: LocalizedStringKey, by offset: Int) -> some View {
        Button { step(by: offset) } label: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TeaTheme.brass)
                .frame(width: TeaTheme.hitTarget, height: TeaTheme.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier("\(id)-\(offset < 0 ? "previous" : "next")")
    }

    private func option(at index: Int) -> Option {
        let remainder = index % options.count
        return options[remainder < 0 ? remainder + options.count : remainder]
    }

    private func displayedPosition(on date: Date) -> CGFloat {
        turn?.position(on: date) ?? drag?.position ?? CGFloat(selectedIndex)
    }

    private func step(by offset: Int) {
        move(to: (turn?.destination ?? selectedIndex) + offset)
    }

    private func stride(for width: CGFloat) -> CGFloat { max(38, width * 0.56) }

    private func followDrag(horizontal: CGFloat, width: CGFloat) {
        guard !reduceMotion else { return }
        let origin = drag?.origin ?? displayedPosition(on: .now)
        turn = nil
        drag = RotationDrag(origin: origin, position: origin - horizontal * readingDirection / stride(for: width))
    }

    private func finishSwipe(horizontal: CGFloat, velocity: CGFloat, width: CGFloat) {
        let origin = Int((drag?.origin ?? displayedPosition(on: .now)).rounded())
        let glide = horizontal * velocity > 0 ? abs(velocity) * 0.115 : 0
        let travel = (abs(horizontal) + glide) / stride(for: width)
        let steps = Int(min(CGFloat(options.count - 1), max(1, travel.rounded())))
        move(to: origin + (horizontal * readingDirection < 0 ? steps : -steps))
    }

    private func cancelDrag() {
        if let drag { move(to: Int(drag.origin.rounded())) }
    }

    private func move(to destination: Int) {
        let now = Date.now
        let origin = displayedPosition(on: now)
        drag = nil
        let distance = abs(CGFloat(destination) - origin)
        if reduceMotion || distance < 0.001 {
            commit(destination)
        } else {
            turn = Turn(origin: origin, destination: destination, startedAt: now,
                        duration: min(0.46, 0.25 + 0.058 * distance))
        }
    }

    private func commit(_ destination: Int) {
        selectFromMenu(option(at: destination))
    }

    private func selectFromMenu(_ option: Option) {
        turn = nil
        drag = nil
        selection = option
    }

    private struct RotationDrag {
        let origin: CGFloat
        let position: CGFloat
    }

    private struct Turn: Equatable {
        let origin: CGFloat
        let destination: Int
        let startedAt: Date
        let duration: TimeInterval

        func position(on date: Date) -> CGFloat {
            let progress = min(1, max(0, date.timeIntervalSince(startedAt) / duration))
            return origin + (CGFloat(destination) - origin) * (1 - pow(1 - progress, 3))
        }
    }
}

private struct AppearanceSwatch<Content: View>: View {
    var corner = false
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geometry in
            if corner {
                content
                    .frame(width: geometry.size.width + 14, height: geometry.size.height + 14)
                    .modifier(Felt(gameTable: true))
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            } else {
                HStack(spacing: 5) { content }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(Felt(gameTable: true))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
    }
}

private struct HorizontalChoiceSwipe: UIViewRepresentable {
    var onChange: ((CGFloat, CGFloat) -> Void)?
    var onCancel: (() -> Void)?
    var minimumDistance: CGFloat = 24
    let onSwipe: (CGFloat, CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> SwipeArea {
        let view = SwipeArea()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: SwipeArea, context: Context) {
        view.onChange = onChange
        view.onCancel = onCancel
        view.minimumDistance = minimumDistance
        view.onSwipe = onSwipe
    }

    final class SwipeArea: UIView, UIGestureRecognizerDelegate {
        var onChange: ((CGFloat, CGFloat) -> Void)?
        var onCancel: (() -> Void)?
        var minimumDistance: CGFloat = 24
        var onSwipe: ((CGFloat, CGFloat, CGFloat) -> Void)?
        private lazy var pan: UIPanGestureRecognizer = {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
            recognizer.delegate = self
            recognizer.maximumNumberOfTouches = 1
            return recognizer
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachToScrollView()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            attachToScrollView()
        }

        private func attachToScrollView() {
            // Let the Form scroll view arbitrate before a menu row takes over the drag.
            var ancestor = window == nil ? nil : superview
            while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
            guard pan.view !== ancestor else { return }
            pan.view?.removeGestureRecognizer(pan)
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
            let movement = pan.translation(in: pan.view)
            switch pan.state {
            case .began, .changed:
                onChange?(movement.x, bounds.width)
            case .ended:
                if abs(movement.x) >= minimumDistance, abs(movement.x) > abs(movement.y) * 1.2 {
                    onSwipe?(movement.x, pan.velocity(in: pan.view).x, bounds.width)
                } else {
                    onCancel?()
                }
            case .cancelled, .failed:
                onCancel?()
            default:
                break
            }
        }
    }
}

private struct TableAppearancePreview: View {
    private let samples = ([2, 5, 6, 9].map { TileKind(.characters, $0) }
                           + [1, 6, 8, 9].map { TileKind(.circles, $0) }
                           + [1, 3, 7].map { TileKind(.bamboo, $0) }).sorted()
    private let columnCount = 6
    private let maximumTileWidth: CGFloat = 48
    private let spacing: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            let columns = CGFloat(columnCount)
            let tileWidth = min(maximumTileWidth, max(0, (geometry.size.width - (columns - 1) * spacing) / columns))
            let tileHeight = tileWidth / TileFace.artworkAspectRatio
            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    faces(samples.prefix(columnCount), width: tileWidth, height: tileHeight)
                }
                HStack(spacing: spacing) {
                    faces(samples.dropFirst(columnCount), width: tileWidth, height: tileHeight)
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

    private func faces(_ samples: ArraySlice<TileKind>, width: CGFloat, height: CGFloat) -> some View {
        ForEach(samples, id: \.self) { kind in
            TileFace(kind: kind)
                .frame(width: width, height: height)
        }
    }
}
