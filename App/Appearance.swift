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
    @Binding var tileStyle: TileStyle
    let hapticsEnabled: Binding<Bool>

    var body: some View {
        Section {
            Picker("显示模式", selection: $appearance) {
                ForEach(GameAppearance.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .accessibilityValue(Text(appearance.title))
            .accessibilityIdentifier("appearance-picker")
            MaterialPicker("牌桌", id: "board-style-picker", options: BoardStyle.allCases,
                           selection: $boardStyle, hapticsEnabled: hapticsEnabled, name: \.title) { style in
                Color.clear
                    .modifier(Felt(gameTable: true))
                    .environment(\.boardStyle, style.resolved(for: colorScheme))
            }
            MaterialPicker("牌面", id: "tile-style-picker", options: TileStyle.allCases,
                           selection: $tileStyle, hapticsEnabled: hapticsEnabled, name: \.title) { style in
                HStack(spacing: 5) {
                    TileFace(kind: TileKind(.characters, 6)).frame(width: 28, height: 39)
                    TileFace(kind: TileKind(.circles, 5), gold: true).frame(width: 28, height: 39)
                    TileFace(kind: TileKind(.bamboo, 1)).frame(width: 28, height: 39)
                    TileBack().frame(width: 28, height: 39)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(Felt(gameTable: true))
                .environment(\.boardStyle, boardStyle.resolved(for: colorScheme))
                .environment(\.tileStyle, style.resolved(for: colorScheme))
            }
        } header: {
            Text("外观")
        } footer: {
            Text("左右滑动更换牌桌和牌面。自动选项随显示模式变化，手动选择会保留。")
        }
        .listRowBackground(TeaTheme.surface)
    }
}

private struct MaterialPicker<Option: Hashable, Preview: View>: View {
    let label: LocalizedStringKey
    let id: String
    let options: [Option]
    @Binding var selection: Option
    let hapticsEnabled: Binding<Bool>
    let name: KeyPath<Option, LocalizedStringKey>
    let preview: (Option) -> Preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @GestureState private var drag: CGFloat = 0
    @State private var position = 0
    @State private var selectionChangeID: UUID?

    private var selectedPosition: Int {
        if !options.isEmpty, option(at: position) == selection { return position }
        return options.firstIndex(of: selection) ?? 0
    }
    private var readingDirection: CGFloat { layoutDirection == .leftToRight ? 1 : -1 }
    private var snapAnimation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.24) }

    init(_ label: LocalizedStringKey, id: String, options: [Option], selection: Binding<Option>,
         hapticsEnabled: Binding<Bool>, name: KeyPath<Option, LocalizedStringKey>,
         @ViewBuilder preview: @escaping (Option) -> Preview) {
        self.label = label
        self.id = id
        self.options = options
        _selection = selection
        self.hapticsEnabled = hapticsEnabled
        self.name = name
        self.preview = preview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                Spacer()
                Text(selection[keyPath: name])
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TeaTheme.brass)
                    .multilineTextAlignment(.trailing)
            }
            HStack(spacing: 4) {
                arrow("chevron.backward", by: -1)
                GeometryReader { geometry in
                    let width = min(geometry.size.width, min(270, max(132, geometry.size.width * 0.78)))
                    materialStrip(width: width, viewport: geometry.size.width)
                }
                .frame(height: 62)
                arrow("chevron.forward", by: 1)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(selection[keyPath: name]))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(by: 1)
            case .decrement: move(by: -1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier(id)
        .onDisappear { selectionChangeID = nil }
    }

    private func materialStrip(width: CGFloat, viewport: CGFloat) -> some View {
        let stride = width + 8
        let center = selectedPosition
        let nearest = center - Int((drag * readingDirection / stride).rounded())
        // Keep a full cycle on either side of the viewport so previews keep their identities during a snap.
        let radius = options.count + Int(ceil(viewport / (2 * stride)))
        let positions = options.count > 1 ? (nearest - radius)..<(nearest + radius + 1) : options.indices
        return ZStack {
            ForEach(positions, id: \.self) { index in
                preview(option(at: index))
                    .frame(width: width, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: TeaTheme.tableRailCorner))
                    .offset(x: CGFloat(index - center) * stride * readingDirection + drag)
                    .transition(.identity)
            }
        }
        .frame(width: viewport, height: 62)
        .clipped()
        .contentShape(Rectangle())
        .animation(drag == 0 ? snapAnimation : nil, value: drag == 0)
        .simultaneousGesture(DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .updating($drag) { value, drag, _ in
                guard options.count > 1 else { return }
                let translation = value.translation
                drag = abs(translation.width) > abs(translation.height) ? translation.width : 0
            }
            .onEnded { value in
                let horizontal = value.translation.width
                guard options.count > 1, abs(horizontal) > abs(value.translation.height), abs(horizontal) >= 24 else { return }
                let projected = value.predictedEndTranslation.width
                let distance = horizontal * projected > 0 ? max(abs(horizontal), abs(projected)) : abs(horizontal)
                // A fling can skip materials, up to one fewer than a full lap.
                let stepDistance = max(1, min(stride * 0.62, viewport * 0.42))
                let steps = Int(min(CGFloat(options.count - 1), max(1, (distance / stepDistance).rounded())))
                move(by: horizontal * readingDirection < 0 ? steps : -steps)
            })
    }

    private func arrow(_ icon: String, by offset: Int) -> some View {
        let enabled = options.count > 1
        return Button { move(by: offset) } label: {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(enabled ? TeaTheme.brass : TeaTheme.line)
                .frame(width: TeaTheme.hitTarget, height: TeaTheme.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func option(at position: Int) -> Option {
        let index = position % options.count
        return options[index < 0 ? index + options.count : index]
    }

    private func move(by offset: Int) {
        guard options.count > 1 else { return }
        let destination = selectedPosition + offset
        let material = option(at: destination)
        guard material != selection else { return }

        let changeID = UUID()
        selectionChangeID = changeID
        withAnimation(snapAnimation) {
            position = destination
            selection = material
        } completion: {
            guard selectionChangeID == changeID, selection == material, hapticsEnabled.wrappedValue else { return }
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}
