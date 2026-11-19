import FuzhouAccess
import FuzhouCore
import FuzhouNearby
import SwiftUI

@main
struct FuzhouMahjongApp: App {
    @AppStorage("appearance.mode") private var appearance = GameAppearance.system

    var body: some Scene {
        WindowGroup {
            HomeView(appearance: $appearance)
                .gameAppearance(appearance)
        }
    }
}

private struct HomeView: View {
    private enum Route: Hashable { case solo, nearby, rules }
    private enum SoloPrompt {
        case legacyRemoved, retain(SoloSaveSlot)

        var title: String {
            switch self {
            case .legacyRemoved: "旧版单机牌局已清除"
            case .retain: "保留这张牌桌？"
            }
        }
    }

    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("nearby.nickname") private var nickname = ""
    @AppStorage("table.tileStyle") private var tileStyle = TileStyle.automatic
    @AppStorage("table.boardStyle") private var boardStyle = BoardStyle.automatic
    @Binding var appearance: GameAppearance
    @AppStorage("solo.ruleset") private var ruleset = FuzhouRuleset.pureSuit
    @AppStorage("solo.customRulesetID") private var customRulesetID = ""
    @State private var access: GameAccess
    @State private var session: SoloMatch
    @State private var nearby: NearbySession
    @State private var rulesetLibrary = RulesetLibrary()
    @State private var path: [Route] = []
    private enum HomeSheet: Identifiable {
        case settings, soloSetup, purchase(AccessReason)
        var id: String {
            switch self {
            case .settings: "settings"
            case .soloSetup: "solo-setup"
            case .purchase(let reason): reason.id
            }
        }
    }
    @State private var sheet: HomeSheet?
    @State private var soloPrompt: SoloPrompt?
    @State private var saveChoiceFailed = false
    @State private var opensSoloAfterSetup = false

    init(appearance: Binding<GameAppearance>) {
        _appearance = appearance
        let access = GameAccess()
        let session = SoloMatch(access: access)
        _access = State(initialValue: access)
        _session = State(initialValue: session)
        _soloPrompt = State(initialValue: session.removedLegacySave ? .legacyRemoved : nil)
        _nearby = State(initialValue: NearbySession(hostingAllowed: { access.authorizeHosting() }))
    }

    var body: some View {
        NavigationStack(path: $path) {
            home
            .modifier(HingeSafeContent())
            .teaBackdrop()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("玩法教程", systemImage: "book") { path.append(.rules) }
                            .accessibilityIdentifier("rules-entry")
                        Button("设置", systemImage: "gearshape") { sheet = .settings }
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                    }
                    .accessibilityIdentifier("home-more")
                }
            }
            .sheet(item: $sheet, onDismiss: openPreparedSoloGame) { destination in
                switch destination {
                case .settings: SettingsView(appearance: $appearance, boardStyle: $boardStyle, tileStyle: $tileStyle)
                case .soloSetup:
                    SoloSetup(ruleset: ruleset, customID: customRulesetID,
                              replacesUnfinishedGame: session.table?.matchFinished == false,
                              start: prepareSoloGame)
                case .purchase(let reason): PurchaseSheet(reason: reason)
                }
            }
            .alert(soloPrompt?.title ?? "", isPresented: Binding(
                get: { soloPrompt != nil }, set: { if !$0 { soloPrompt = nil } }
            ), presenting: soloPrompt) { prompt in
                switch prompt {
                case .legacyRemoved:
                    Button("好", role: .cancel) {}
                case .retain(let slot):
                    Button("保留这桌", role: .destructive) {
                        saveChoiceFailed = !session.keepSavedTable(slot)
                    }
                    .accessibilityIdentifier("confirm-save-choice")
                    Button("取消", role: .cancel) {}
                }
            } message: { prompt in
                switch prompt {
                case .legacyRemoved:
                    Text(session.canResume || !session.savedTableChoices.isEmpty
                         ? "使用当前规则的存档仍可继续。" : "请选择规则，开始新的单机牌局。")
                case .retain:
                    Text("确认后会清除另一张单机牌桌的进度。")
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .solo: MatchView(session: session)
                case .nearby: NearbyView(session: nearby)
                case .rules: RuleGuide(ruleset: ruleset, houseRules: selectedHouseRules)
                }
            }
        }
        .environment(access)
        .environment(rulesetLibrary)
        .environment(\.boardStyle, boardStyle.resolved(for: colorScheme))
        .environment(\.tileStyle, tileStyle.resolved(for: colorScheme))
        .tint(TeaTheme.brass)
        .foregroundStyle(TeaTheme.ink)
        .task {
            await access.start()
            while !Task.isCancelled {
                access.refreshClock()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .onChange(of: phase) { _, updated in
            if updated == .background { nearby.setBackgrounded(true) }
            else if updated == .active {
                nearby.setBackgrounded(false)
                access.refreshClock()
                Task { await access.refreshEntitlements() }
            }
        }
        .onOpenURL { url in
            guard let id = RoomInvite.id(from: url) else { return }
            sheet = nil
            soloPrompt = nil
            opensSoloAfterSetup = false
            path = [.nearby]
            nearby.joinInvite(id, name: nickname)
        }
    }

    private var selectedHouseRules: FuzhouHouseRules? { rulesetLibrary.preset(for: customRulesetID) }

    private var home: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 580 && geometry.size.width > geometry.size.height
                && !typeSize.isAccessibilitySize
            let layout = wide ? AnyLayout(HStackLayout(spacing: 22)) : AnyLayout(VStackLayout(spacing: 22))
            ScrollView {
                layout {
                    homeHero(wide: wide)
                    playModes
                }
                .frame(maxWidth: wide ? 860 : 500)
                .padding([.horizontal, .bottom], TeaTheme.gutter)
                .padding(.top, wide ? TeaTheme.gutter : 28)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: wide ? .center : .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var playModes: some View {
        VStack(spacing: 12) {
            if session.savedTableChoices.isEmpty {
                if let table = session.table { savedSoloEntry(table) }
                Button { sheet = .soloSetup } label: {
                    modeRow("开始新牌局", detail: session.canResume ? nil : "和三位电脑玩家一起打牌",
                            icon: "plus")
                }
                .buttonStyle(TeaButtonStyle(prominent: !session.canResume, verticalPadding: 13))
                .accessibilityIdentifier(session.canResume ? "new-solo-game" : "practice-entry")
            } else {
                soloSaveChoices
            }

            Button { path.append(.nearby) } label: {
                modeRow(nearby.isInRoom ? "返回附近牌桌" : "附近联机",
                        detail: "与身边的牌友同桌", icon: "person.2.fill")
            }
            .buttonStyle(TeaButtonStyle(prominent: false, verticalPadding: 13))
            .accessibilityIdentifier("nearby-entry")

            Button { sheet = .purchase(.settings) } label: {
                Label(access.soloAllowanceText, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(TeaTheme.muted)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: TeaTheme.hitTarget, alignment: .leading)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("solo-remaining")
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    private func savedSoloEntry(_ table: TableState) -> some View {
        VStack(spacing: 0) {
            Button { path.append(.solo) } label: {
                modeRow("继续单机", detail: "本桌规则 · \(table.ruleset.displayTitle(houseRules: table.houseRules))",
                        icon: "arrow.counterclockwise")
            }
            .buttonStyle(TeaButtonStyle(verticalPadding: 13))
            .accessibilityIdentifier("practice-entry")
            RulesetDetailsButton(ruleset: table.ruleset, houseRules: table.houseRules,
                                 title: "本桌规则详情", subtitle: "\(table.wind.wind)\(table.handNumber)局",
                                 identifier: "saved-solo-rules")
                .padding(.horizontal, 14)
        }
        .teaPanel(corner: TeaTheme.controlCorner)
    }

    private var soloSaveChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择保留的单机牌局")
                .font(.headline).foregroundStyle(TeaTheme.brass)
                .accessibilityAddTraits(.isHeader)
            if saveChoiceFailed {
                Text("暂时无法保留牌局，请重试。")
                    .font(.footnote).foregroundStyle(TeaTheme.loss)
            }
            ForEach(session.savedTableChoices) { saved in
                let table = saved.table
                let title = table.ruleset.displayTitle(houseRules: table.houseRules)
                let score = table.players.first { $0.seat == table.viewer }?.score ?? 0
                Button { soloPrompt = .retain(saved.slot) } label: {
                    modeRow(saved.slot == .first ? "保留第一桌" : "保留第二桌",
                            detail: "\(title) · \(table.wind.wind)\(table.handNumber)局 · \(score)分",
                            icon: "rectangle.on.rectangle")
                }
                .buttonStyle(TeaButtonStyle(prominent: false, verticalPadding: 13))
                .accessibilityIdentifier(saved.slot == .first ? "keep-first-solo" : "keep-second-solo")
            }
        }
        .padding(12)
        .teaPanel(corner: TeaTheme.controlCorner)
    }

    private func prepareSoloGame(_ ruleset: FuzhouRuleset, _ customID: String) -> Bool {
        let houseRules = rulesetLibrary.preset(for: customID)
        guard session.startNew(ruleset: ruleset, houseRules: houseRules) else { return false }
        self.ruleset = ruleset
        customRulesetID = houseRules?.id.uuidString ?? ""
        opensSoloAfterSetup = true
        return true
    }

    private func openPreparedSoloGame() {
        if opensSoloAfterSetup {
            opensSoloAfterSetup = false
            path.append(.solo)
        }
    }

    private func homeHero(wide: Bool) -> some View {
        VStack(spacing: wide ? 10 : 20) {
            HStack(spacing: -7) {
                TileFace(kind: TileKind(.bamboo, 1))
                    .frame(width: wide ? 55 : 68, height: wide ? 77 : 95)
                    .rotationEffect(.degrees(-16))
                    .offset(y: 9)
                TileFace(kind: TileKind(.circles, 5), gold: true)
                    .frame(width: wide ? 62 : 77, height: wide ? 86 : 107)
                    .rotationEffect(.degrees(-4))
                    .zIndex(1)
                TileFace(kind: TileKind(.characters, 8))
                    .frame(width: wide ? 55 : 68, height: wide ? 77 : 95)
                    .rotationEffect(.degrees(14))
                    .offset(y: 9)
            }
            .padding(.vertical, 9)
            .shadow(color: .black.opacity(0.55), radius: 12, y: 10)
            .accessibilityHidden(true)
            VStack(spacing: 7) {
                Text("福州麻将")
                    .font(TeaTheme.display)
                    .tracking(2)
                    .accessibilityAddTraits(.isHeader)
                Text("福州玩法，离线同玩")
                    .font(.subheadline)
                    .foregroundStyle(TeaTheme.brass)
            }
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, wide ? 19 : 30)
        .frame(maxWidth: .infinity)
        .modifier(Felt(inlaid: true))
    }

    private func modeRow(_ title: String, detail: String?, icon: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(minWidth: 38, minHeight: 38)
                .background(.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                if let detail { Text(detail).font(.footnote).opacity(0.85) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .accessibilityHidden(true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SoloSetup: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(GameAccess.self) private var access
    @Environment(RulesetLibrary.self) private var library
    @State var ruleset: FuzhouRuleset
    @State var customID: String
    let replacesUnfinishedGame: Bool
    let start: (FuzhouRuleset, String) -> Bool
    @State private var confirmsRestart = false
    @State private var showsPurchase = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    RulesetPicker(title: "选择规则", selection: $ruleset, selectedCustomID: $customID)
                    Button(action: requestStart) {
                        Text("开局").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TeaButtonStyle(verticalPadding: 16))
                    .accessibilityIdentifier("start-solo-setup")
                }
                .padding(TeaTheme.gutter)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .teaBackdrop()
            .modifier(HingeSafeContent())
            .navigationTitle("开始新牌局")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .accessibilityIdentifier("cancel-solo-setup")
                }
            }
            .alert("开始新的单机牌局？", isPresented: $confirmsRestart) {
                Button("重新开始", role: .destructive, action: begin)
                    .accessibilityIdentifier("confirm-new-solo-game")
                Button("取消", role: .cancel) {}
            } message: {
                let title = ruleset.displayTitle(houseRules: library.preset(for: customID))
                Text("新牌局采用「\(title)」，从东一局开始。当前单机牌局的进度会被清除。")
            }
            .sheet(isPresented: $showsPurchase) { PurchaseSheet(reason: .solo) }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }

    private func requestStart() {
        access.refreshClock()
        if !access.canBeginSoloHand { showsPurchase = true }
        else if replacesUnfinishedGame { confirmsRestart = true }
        else { begin() }
    }

    private func begin() {
        if start(ruleset, customID) { dismiss() }
        else { showsPurchase = true }
    }
}

private struct SettingsView: View {
    @Environment(GameAccess.self) private var access
    @Environment(\.dismiss) private var dismiss
    @AppStorage("practice.haptics.enabled") private var hapticsEnabled = true
    @AppStorage("table.sound.enabled") private var soundEnabled = true
    @AppStorage("table.sound.nearbyOwnMovesOnly") private var nearbyOwnMovesOnly = true
    @AppStorage("nearby.nickname") private var nickname = ""
    @Binding var appearance: GameAppearance
    @Binding var boardStyle: BoardStyle
    @Binding var tileStyle: TileStyle

    var body: some View {
        NavigationStack {
            Form {
                Section("版本与购买") {
                    NavigationLink {
                        PurchaseView(reason: .settings)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(access.statusTitle)
                            Text(access.soloAllowanceText).font(.footnote).foregroundStyle(TeaTheme.muted)
                        }
                    }
                    .accessibilityIdentifier("access-entry")
                }
                .listRowBackground(TeaTheme.surface)
                AppearanceSettings(appearance: $appearance, boardStyle: $boardStyle, tileStyle: $tileStyle,
                                   hapticsEnabled: $hapticsEnabled)

                Section("操作反馈") {
                    Toggle("触感", isOn: $hapticsEnabled)
                    Toggle("牌桌音效", isOn: $soundEnabled)
                    Toggle("联机时只播自己的音效", isOn: $nearbyOwnMovesOnly)
                        .disabled(!soundEnabled)
                    Text("开启后，附近联机时只会听到自己出牌、吃、碰、杠和胡牌的音效。")
                        .font(.footnote)
                }
                .listRowBackground(TeaTheme.surface)
                Section("附近联机") {
                    TextField("牌桌昵称", text: $nickname)
                    Text("创建或加入附近牌桌时，牌友可以看到你的昵称。").font(.footnote)
                }
                .listRowBackground(TeaTheme.surface)
                Section("支持与隐私") {
                    Link("使用帮助", destination: URL(string: "https://mj.jenny.media/support/")!)
                    Link("隐私政策", destination: URL(string: "https://mj.jenny.media/privacy/")!)
                }
                .listRowBackground(TeaTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .tint(TeaTheme.brass)
            .modifier(HingeSafeContent())
            .teaBackdrop()
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
        .gameAppearance(appearance)
    }
}
