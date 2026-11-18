import FuzhouAccess
import FuzhouCore
import FuzhouNearby
import SwiftUI

@main
struct FuzhouMahjongApp: App {
    var body: some Scene {
        WindowGroup { HomeView() }
    }
}

private struct HomeView: View {
    private enum Route: Hashable { case solo, secondSolo, nearby, rules }

    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("nearby.nickname") private var nickname = ""
    @AppStorage("table.tileStyle") private var tileStyle = TileStyle.classic
    @State private var access: GameAccess
    @State private var session: SoloMatch
    @State private var secondSession: SoloMatch
    @State private var nearby: NearbySession
    @State private var path: [Route] = []
    private enum HomeSheet: Identifiable {
        case settings, purchase(AccessReason)
        var id: String { switch self { case .settings: "settings"; case .purchase(let reason): reason.id } }
    }
    @State private var sheet: HomeSheet?
    @State private var confirmsRestart = false

    init() {
        let access = GameAccess()
        _access = State(initialValue: access)
        _session = State(initialValue: SoloMatch(access: access))
        _secondSession = State(initialValue: SoloMatch(access: access, storageKey: "solo-match.second.v1"))
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
                        if session.canResume {
                            Button("新开一局", systemImage: "plus.circle") {
                                access.refreshClock()
                                if !access.canBeginSoloHand { sheet = .purchase(.solo) }
                                else if secondSession.canResume { confirmsRestart = true }
                                else { openNewSoloGame() }
                            }
                            .accessibilityIdentifier("new-solo-game")
                        }
                        if secondSession.canResume {
                            Button("返回第二张牌桌", systemImage: "arrow.counterclockwise") { path.append(.secondSolo) }
                                .accessibilityIdentifier("resume-second-solo-game")
                        }
                        Button("玩法", systemImage: "book") { path.append(.rules) }
                            .accessibilityIdentifier("rules-entry")
                        Button("设置", systemImage: "gearshape") { sheet = .settings }
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                    }
                    .accessibilityIdentifier("home-more")
                }
            }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .settings: SettingsView(tileStyle: $tileStyle)
                case .purchase(let reason): PurchaseSheet(reason: reason)
                }
            }
            .confirmationDialog("重新开始第二张牌桌？", isPresented: $confirmsRestart, titleVisibility: .visible) {
                Button("重新开始", role: .destructive) { openNewSoloGame() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("第二张牌桌的进度会重置，原来的单机牌桌会保留。")
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .solo: MatchView(session: session)
                case .secondSolo: MatchView(session: secondSession)
                case .nearby: NearbyView(session: nearby)
                case .rules: RuleGuide()
                }
            }
        }
        .environment(access)
        .environment(\.tileStyle, tileStyle)
        .preferredColorScheme(.dark)
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
            confirmsRestart = false
            path = [.nearby]
            nearby.joinInvite(id, name: nickname)
        }
    }

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
                .padding(TeaTheme.gutter)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var playModes: some View {
        VStack(spacing: 10) {
            Button {
                if session.startIfNeeded() { path.append(.solo) }
                else { sheet = .purchase(.solo) }
            } label: {
                modeRow(session.canResume ? "继续单机" : "单机对战",
                        detail: session.canResume ? "回到上次保存的牌局" : "与三位电脑玩家对局",
                        icon: session.canResume ? "arrow.counterclockwise" : "person.fill")
            }
            .buttonStyle(TeaButtonStyle())
            .accessibilityIdentifier("practice-entry")

            Button { path.append(.nearby) } label: {
                modeRow(nearby.isInRoom ? "返回附近牌桌" : "附近联机",
                        detail: "与身边的牌友同桌", icon: "person.2.fill")
            }
            .buttonStyle(TeaButtonStyle(prominent: false))
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
        .frame(maxWidth: .infinity)
    }

    private func openNewSoloGame() {
        if secondSession.startNew() { path.append(.secondSolo) }
        else { sheet = .purchase(.solo) }
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

    private func modeRow(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(minWidth: 38, minHeight: 38)
                .background(.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.footnote).opacity(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
    }
}

private struct SettingsView: View {
    @Environment(GameAccess.self) private var access
    @Environment(\.dismiss) private var dismiss
    @AppStorage("practice.haptics.enabled") private var hapticsEnabled = true
    @AppStorage("table.sound.enabled") private var soundEnabled = true
    @AppStorage("table.sound.nearbyOwnMovesOnly") private var nearbyOwnMovesOnly = true
    @AppStorage("nearby.nickname") private var nickname = ""
    @Binding var tileStyle: TileStyle

    var body: some View {
        NavigationStack {
            Form {
                Section("游戏权限") {
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
                Section("牌面") {
                    Picker("牌面", selection: $tileStyle) {
                        ForEach(TileStyle.allCases, id: \.self) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("tile-style-picker")

                    HStack(spacing: 7) {
                        TileFace(kind: TileKind(.characters, 6), selected: true).frame(width: 32, height: 44)
                        TileFace(kind: TileKind(.circles, 5), gold: true).frame(width: 32, height: 44)
                        TileFace(kind: TileKind(.bamboo, 1)).frame(width: 32, height: 44)
                        TileFace(kind: TileKind(.dragon, 2)).frame(width: 32, height: 44)
                    }
                    .environment(\.tileStyle, tileStyle)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .modifier(Felt(inlaid: true))
                    .accessibilityHidden(true)
                }
                .listRowBackground(TeaTheme.surface)

                Section("操作反馈") {
                    Toggle("触感", isOn: $hapticsEnabled)
                    Toggle("牌桌音效", isOn: $soundEnabled)
                    Toggle("同桌只播自己的操作", isOn: $nearbyOwnMovesOnly)
                        .disabled(!soundEnabled)
                    Text("附近联机时仅播放自己的摸牌、出牌、吃碰杠和胡牌音效。")
                        .font(.footnote)
                }
                .listRowBackground(TeaTheme.surface)
                Section("附近联机") {
                    TextField("牌桌昵称", text: $nickname)
                    Text("附近牌友会看到此昵称。").font(.footnote)
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
    }
}
