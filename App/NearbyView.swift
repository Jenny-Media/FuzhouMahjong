import CoreImage
import CoreImage.CIFilterBuiltins
import FuzhouAccess
import FuzhouCore
import FuzhouNearby
import SwiftUI
import UIKit

struct NearbyView: View {
    let session: NearbySession
    @Environment(GameAccess.self) private var access
    @Environment(RulesetLibrary.self) private var rulesetLibrary
    @State private var purchaseReason: AccessReason?

    @AppStorage("nearby.nickname") private var nickname = ""
    @AppStorage("nearby.ruleset") private var ruleset = FuzhouRuleset.pureSuit
    @AppStorage("nearby.customRulesetID") private var customRulesetID = ""
    @Environment(\.openURL) private var openURL
    @State private var showsHostSetup = false
    @State private var showsInvite = false
    @State private var showsScanner = false
    @State private var confirmsLeave = false
    @State private var inviteCode = ""

    var body: some View {
        Group {
            if session.table != nil {
                MatchView(session: session)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                if session.isHost {
                                    ForEach(session.players.filter { !$0.connected }) { player in
                                        Button("让电脑接替\(player.name)") { session.substitute(player.seat) }
                                    }
                                }
                                Button("离开牌桌", role: .destructive) { confirmsLeave = true }
                            } label: {
                                Label("牌桌操作", systemImage: "ellipsis.circle")
                            }
                        }
                    }
            } else {
                lobby
                    .navigationTitle("附近联机")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let recovery = session.recovery { recoveryBar(recovery) }
        }
        .task { session.browse() }
        .onDisappear {
            if let round = session.openingRound { session.finishOpening(round) }
            if !session.isInRoom { session.stopBrowsing() }
        }
        .sheet(item: $purchaseReason) { PurchaseSheet(reason: $0) }
        .sheet(isPresented: $showsHostSetup) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        RulesetPicker(title: "新牌桌的玩法", selection: $ruleset, selectedCustomID: $customRulesetID)
                        Button {
                            session.create(name: nickname, ruleset: ruleset,
                                           houseRules: rulesetLibrary.preset(for: customRulesetID))
                            showsHostSetup = false
                        } label: { Text("确认创建").frame(maxWidth: .infinity) }
                        .buttonStyle(TeaButtonStyle())
                        .accessibilityIdentifier("confirm-host-create")
                    }
                    .padding(TeaTheme.gutter)
                    .frame(maxWidth: TeaTheme.contentWidth)
                    .frame(maxWidth: .infinity)
                }
                .modifier(HingeSafeContent())
                .teaBackdrop()
                .navigationTitle("创建牌桌")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showsHostSetup = false } } }
            }
        }
        .sheet(isPresented: $showsInvite) {
            if let id = session.roomID { InviteView(id: id) }
        }
        .sheet(isPresented: $showsScanner) {
            InviteScanner { id in
                showsScanner = false
                session.joinInvite(id, name: nickname)
            }
        }
        .confirmationDialog("离开当前牌桌？", isPresented: $confirmsLeave, titleVisibility: .visible) {
            Button("离开牌桌", role: .destructive) { session.leave() }
            Button("继续对局", role: .cancel) {}
        } message: {
            Text(session.isHost ? "离开后，所有人的牌局都会结束。" : "离开后，你的位置会由电脑接替。")
        }
    }

    private func recoveryBar(_ state: NearbySession.Recovery) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if state == .reconnecting {
                Label("正在重新连接房主…", systemImage: "wifi.exclamationmark")
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("暂时连不上房主").font(.subheadline.weight(.semibold))
                Text("牌桌可能已关闭。你可以重试，或返回大厅。")
                    .font(.footnote).foregroundStyle(TeaTheme.muted)
            }
            HStack(spacing: 8) {
                if state == .unavailable {
                    Button("重试") { session.retryRecovery() }.buttonStyle(TeaButtonStyle())
                }
                Button("返回大厅") { session.leave() }
                    .buttonStyle(TeaButtonStyle(prominent: false))
                    .accessibilityIdentifier("recovery-lobby")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TeaTheme.gutter)
        .padding(.vertical, 8)
        .teaPanel(corner: 0)
    }

    private var lobby: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(session.isInRoom
                         ? (session.isHost ? "你的牌桌" : "\(session.roomName ?? "牌友")的牌桌")
                         : "与牌友同桌")
                        .font(TeaTheme.display)
                        .accessibilityAddTraits(.isHeader)
                    Label("无需连接互联网", systemImage: "dot.radiowaves.left.and.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TeaTheme.brass)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(Felt(inlaid: true))

                if let notice = session.notice {
                    Text(notice).font(.subheadline).foregroundStyle(TeaTheme.muted)
                    if notice.contains("权限") || notice.contains("访问") {
                        Button("打开设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .buttonStyle(TeaButtonStyle(prominent: false))
                    }
                }
                if let search = session.inviteSearch {
                    HStack(spacing: 8) {
                        if search == .unavailable {
                            Button("重新查找邀请牌桌") { session.retryInviteSearch() }
                                .buttonStyle(TeaButtonStyle())
                        }
                        Button("取消查找") { session.cancelInviteSearch() }
                            .buttonStyle(TeaButtonStyle(prominent: false))
                            .accessibilityIdentifier("cancel-invite-search")
                    }
                }

                if session.isInRoom {
                    roster
                } else {
                    discovery
                }
            }
            .padding(TeaTheme.gutter)
            .frame(maxWidth: TeaTheme.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .modifier(HingeSafeContent())
        .teaBackdrop()
    }

    private var discovery: some View {
        Group {
            if let previous = session.lastRoomName {
                HStack {
                    Button("返回上次牌桌 · \(previous)") { session.resumeLastRoom() }
                        .buttonStyle(TeaButtonStyle(prominent: false))
                        .disabled(session.inviteSearch == .searching)
                    Menu {
                        Button("忘记上次牌桌", role: .destructive) { session.forgetLastRoom() }
                    } label: { Label("上次牌桌选项", systemImage: "ellipsis.circle").labelStyle(.iconOnly) }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("加入附近牌桌")
                    .font(.headline).foregroundStyle(TeaTheme.brass)
                    .accessibilityAddTraits(.isHeader)
                Text("加入牌友的牌桌始终免费。").font(.footnote).foregroundStyle(TeaTheme.muted)
                Button { showsScanner = true } label: {
                    Label("扫码加入", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TeaButtonStyle())
                .accessibilityIdentifier("scan-invite")
                ForEach(session.rooms) { room in
                    Button {
                        session.join(room, name: nickname)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(room.name)的牌桌").font(.headline)
                                Text(room.code).font(.caption.monospaced()).foregroundStyle(TeaTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(TeaButtonStyle(prominent: false))
                }
                HStack {
                    TextField("4 位邀请码", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 10)
                        .frame(minHeight: TeaTheme.hitTarget)
                        .background(TeaTheme.canvas, in: RoundedRectangle(cornerRadius: 10))
                    Button("加入") {
                        if let room = inviteRoom { session.join(room, name: nickname) }
                    }
                    .buttonStyle(TeaButtonStyle(prominent: false))
                    .disabled(inviteRoom == nil)
                }

                if !inviteCode.isEmpty, inviteCode.count == 4, inviteRoom == nil {
                    Text("还未找到唯一匹配的牌桌。请核对邀请码，或扫描房主的二维码。")
                        .font(.footnote).foregroundStyle(TeaTheme.muted)
                }
                if session.rooms.isEmpty {
                    HStack {
                        Label("正在查找附近牌桌…", systemImage: "wifi")
                            .font(.footnote).foregroundStyle(TeaTheme.muted)
                        Spacer()
                        Button("重新查找") { session.stopBrowsing(); session.browse() }
                            .disabled(session.inviteSearch == .searching)
                    }
                }
                Text("请靠近房主，并打开 Wi-Fi。")
                    .font(.footnote).foregroundStyle(TeaTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .teaPanel()

            Button {
                if access.authorizeHosting() { showsHostSetup = true }
                else { purchaseReason = .hosting }
            } label: { Label("创建牌桌", systemImage: "plus").frame(maxWidth: .infinity) }
            .buttonStyle(TeaButtonStyle(prominent: false))
            .accessibilityIdentifier("host-create")

            TextField("牌桌昵称（可选）", text: $nickname)
                .padding(12)
                .frame(minHeight: TeaTheme.hitTarget)
                .teaPanel(corner: TeaTheme.controlCorner)
        }
    }

    private var inviteRoom: DiscoveredRoom? {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = session.rooms.filter { $0.code.caseInsensitiveCompare(code) == .orderedSame }
        return matches.count == 1 ? matches[0] : nil
    }

    private var roster: some View {
        Group {
            if let update = session.update {
                Label("玩法 · \(update.houseRules?.name ?? update.ruleset.title)", systemImage: "list.bullet.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("room-ruleset")
                RulesetDetailsButton(ruleset: update.ruleset, houseRules: update.houseRules)
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(session.players) { player in
                    HStack {
                        SeatBadge(seat: player.seat, highlighted: player.seat == .east)
                        Text(player.name)
                        Spacer()
                        Text(player.seat == .east ? "房主" : player.connected ? "已入座" : "已断开，等待重连")
                            .font(.caption).foregroundStyle(TeaTheme.muted)
                    }
                    .frame(minHeight: TeaTheme.hitTarget)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .teaPanel()
            if session.isHost {
                Text(session.canStart ? "开局时，空位会由电脑补上。" : "至少有一位牌友入座后才可以开局。")
                    .font(.footnote).foregroundStyle(TeaTheme.muted)
                Button {
                    if access.authorizeHosting() { session.startMatch() }
                    else { purchaseReason = .hosting }
                } label: { Text(access.canHost ? "开始对局" : "解锁并开始对局").frame(maxWidth: .infinity) }
                    .buttonStyle(TeaButtonStyle())
                    .disabled(!session.canStart)
                    .accessibilityIdentifier("host-start")
                Button("分享邀请") { showsInvite = true }
                    .buttonStyle(TeaButtonStyle(prominent: false))
            } else if session.connected {
                Text("等待房主开局").font(.footnote).foregroundStyle(TeaTheme.muted)
            }
            Button("离开牌桌") { session.leave() }
                .buttonStyle(TeaButtonStyle(prominent: false))
        }
    }
}

private struct InviteView: View {
    let id: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let png = qrImage {
                        Image(uiImage: png)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 190)
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: TeaTheme.controlCorner))
                            .accessibilityLabel("牌桌邀请二维码")
                    }
                    Text(id.uuidString.prefix(4))
                        .font(TeaTheme.display.monospaced()).foregroundStyle(TeaTheme.brass)
                    Text("请牌友打开「附近联机」，扫描二维码，或输入上方的 4 位邀请码。")
                        .font(.subheadline).multilineTextAlignment(.center)
                }
                .padding(18)
                .frame(maxWidth: 360)
                .teaPanel()
                .padding(TeaTheme.gutter)
                .frame(maxWidth: .infinity)
            }
            .modifier(HingeSafeContent())
            .teaBackdrop()
            .navigationTitle("邀请牌友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }

    private var qrImage: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(RoomInvite.url(for: id).utf8)
        guard let output = filter.outputImage,
              let rendered = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: rendered)
    }
}
