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
    @ScaledMetric(relativeTo: .body) private var modeIconWidth = 22
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
        return NavigationStack(path: $path) {
            GeometryReader { geometry in
                let compact = geometry.size.width > geometry.size.height && !typeSize.isAccessibilitySize
                let homeLayout = compact ? AnyLayout(HStackLayout(spacing: 20)) : AnyLayout(VStackLayout(spacing: 24))
                ScrollView {
                    VStack(spacing: compact ? 12 : 24) {
                        Text("福州麻将")
                            .font(.system(.largeTitle, design: .serif, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)

                        homeLayout {
                            tableArt(compact: compact)

                            VStack(spacing: 12) {
                                Button {
                                    if session.startIfNeeded() { path.append(.solo) }
                                    else { sheet = .purchase(.solo) }
                                } label: {
                                    modeRow(session.canResume ? "继续单机" : "单机对战",
                                            icon: session.canResume ? "arrow.counterclockwise" : "person.fill")
                                }
                                .buttonStyle(TeaButtonStyle())
                                .accessibilityIdentifier("practice-entry")

                                Button {
                                    path.append(.nearby)
                                } label: {
                                    modeRow(nearby.isInRoom ? "返回附近牌桌" : "附近联机",
                                            icon: "dot.radiowaves.left.and.right")
                                }
                                .buttonStyle(TeaButtonStyle(prominent: false))
                                .accessibilityIdentifier("nearby-entry")
                                Button { sheet = .purchase(.settings) } label: {
                                    Text(access.soloAllowanceText)
                                        .font(.caption).foregroundStyle(TeaTheme.muted)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("solo-remaining")
                            }
                        }
                    }
                    .padding(TeaTheme.gutter)
                    .padding(.top, compact ? 0 : 20)
                }
            }
            .modifier(HingeSafeContent())
            .background(TeaTheme.canvas)
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
        .tint(TeaTheme.ink)
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

    private func openNewSoloGame() {
        if secondSession.startNew() { path.append(.secondSolo) }
        else { sheet = .purchase(.solo) }
    }

    private func tableArt(compact: Bool) -> some View {
        HStack(spacing: -9) {
            TileFace(kind: TileKind(.bamboo, 7))
                .frame(width: 65, height: 91)
                .rotationEffect(.degrees(-15))
                .offset(y: 13)
            TileFace(kind: TileKind(.circles, 5), gold: true)
                .frame(width: 70, height: 97)
                .rotationEffect(.degrees(-3))
                .zIndex(1)
            TileFace(kind: TileKind(.characters, 8))
                .frame(width: 65, height: 91)
                .rotationEffect(.degrees(15))
                .offset(y: 13)
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 145 : 218)
        .modifier(Felt())
        .accessibilityHidden(true)
    }

    private func modeRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: modeIconWidth)
                .accessibilityHidden(true)
            Text(title).font(.body.weight(.semibold))
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
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(TeaTheme.felt, in: RoundedRectangle(cornerRadius: TeaTheme.controlCorner))
                    .accessibilityHidden(true)
                }

                Section("操作反馈") {
                    Toggle("触感", isOn: $hapticsEnabled)
                    Toggle("牌桌音效", isOn: $soundEnabled)
                    Toggle("同桌只播自己的操作", isOn: $nearbyOwnMovesOnly)
                        .disabled(!soundEnabled)
                    Text("附近联机时仅播放自己的摸牌、出牌、吃碰杠和胡牌音效。")
                        .font(.footnote)
                }
                Section("附近联机") {
                    TextField("牌桌昵称", text: $nickname)
                    Text("附近牌友会看到此昵称。").font(.footnote)
                }
            }
            .modifier(HingeSafeContent())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
    }
}
