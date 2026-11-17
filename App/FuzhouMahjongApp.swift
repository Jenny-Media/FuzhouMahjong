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
    private enum Route: Hashable { case solo, secondSolo, nearby }

    @Environment(\.scenePhase) private var phase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("nearby.nickname") private var nickname = ""
    @AppStorage("table.tileStyle") private var tileStyle = TileStyle.classic
    @State private var session = SoloMatch()
    @State private var secondSession = SoloMatch(storageKey: "solo-match.second.v1")
    @State private var nearby = NearbySession()
    @State private var path: [Route] = []
    @State private var showsSettings = false
    @State private var confirmsRestart = false

    var body: some View {
        let compact = verticalSizeClass == .compact
        let homeLayout = compact ? AnyLayout(HStackLayout(spacing: 20)) : AnyLayout(VStackLayout(spacing: 24))
        return NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: compact ? 12 : 24) {
                    Text("福州麻将")
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)

                    homeLayout {
                        tableArt

                        VStack(spacing: 12) {
                            Button {
                                session.startIfNeeded()
                                path.append(.solo)
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
                        }
                    }
                }
                .padding(TeaTheme.gutter)
                .padding(.top, compact ? 0 : 20)
            }
            .background(TeaTheme.canvas)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if session.canResume {
                            Button("新开一局", systemImage: "plus.circle") {
                                if secondSession.canResume { confirmsRestart = true }
                                else { openNewSoloGame() }
                            }
                            .accessibilityIdentifier("new-solo-game")
                        }
                        if secondSession.canResume {
                            Button("返回第二张牌桌", systemImage: "arrow.counterclockwise") { path.append(.secondSolo) }
                                .accessibilityIdentifier("resume-second-solo-game")
                        }
                        Button("设置", systemImage: "gearshape") { showsSettings = true }
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                    }
                    .accessibilityIdentifier("home-more")
                }
            }
            .sheet(isPresented: $showsSettings) { SettingsView(tileStyle: $tileStyle) }
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
                }
            }
        }
        .environment(\.tileStyle, tileStyle)
        .tint(TeaTheme.ink)
        .foregroundStyle(TeaTheme.ink)
        .onChange(of: phase) { _, updated in
            if updated == .background { nearby.setBackgrounded(true) }
            else if updated == .active { nearby.setBackgrounded(false) }
        }
        .onOpenURL { url in
            guard let id = RoomInvite.id(from: url) else { return }
            path = [.nearby]
            nearby.joinInvite(id, name: nickname)
        }
    }

    private func openNewSoloGame() {
        secondSession.startNew()
        path.append(.secondSolo)
    }

    private var tableArt: some View {
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
        .frame(height: verticalSizeClass == .compact ? 145 : 218)
        .modifier(Felt())
        .accessibilityHidden(true)
    }

    private func modeRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 22)
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
    @Environment(\.dismiss) private var dismiss
    @AppStorage("practice.haptics.enabled") private var hapticsEnabled = true
    @AppStorage("table.sound.enabled") private var soundEnabled = true
    @AppStorage("table.sound.nearbyOwnMovesOnly") private var nearbyOwnMovesOnly = true
    @AppStorage("nearby.nickname") private var nickname = ""
    @Binding var tileStyle: TileStyle

    var body: some View {
        NavigationStack {
            Form {
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
                        TileFace(kind: TileKind(.characters, 6)).frame(width: 32, height: 44)
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
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
    }
}
