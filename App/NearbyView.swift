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
    @State private var purchaseReason: AccessReason?

    @AppStorage("nearby.nickname") private var nickname = ""
    @Environment(\.openURL) private var openURL
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
                                        Button("电脑接替 \(player.name)") { session.substitute(player.seat) }
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
            Text(session.isHost ? "离开会结束所有人的对局。" : "你的座位将由电脑接替。")
        }
    }

    private func recoveryBar(_ state: NearbySession.Recovery) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if state == .reconnecting {
                Label("正在重新连接房主…", systemImage: "wifi.exclamationmark")
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("暂时无法连接房主").font(.subheadline.weight(.semibold))
                Text("牌桌可能已经结束。可以重试，或返回大厅。")
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
        .background(TeaTheme.canvas)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var lobby: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("无需连接互联网", systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
                    .background(TeaTheme.surface, in: Capsule())

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
                            Button("重试邀请") { session.retryInviteSearch() }
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
        }
        .modifier(HingeSafeContent())
        .background(TeaTheme.canvas)
    }

    private var discovery: some View {
        Group {
            TextField("牌桌昵称（可选）", text: $nickname)
                .padding(12)
                .frame(minHeight: TeaTheme.hitTarget)
                .background(TeaTheme.surface, in: RoundedRectangle(cornerRadius: TeaTheme.controlCorner))

            Text("附近牌桌").font(.headline).accessibilityAddTraits(.isHeader)
            if session.rooms.isEmpty {
                Text("正在查找附近牌桌…").font(.subheadline).foregroundStyle(TeaTheme.muted)
                Button("重新查找") { session.stopBrowsing(); session.browse() }
                    .buttonStyle(TeaButtonStyle(prominent: false))
            }
            ForEach(session.rooms) { room in
                Button {
                    session.join(room, name: nickname)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(room.name)的牌桌").font(.headline)
                            Text("福州麻将 · \(room.code)").font(.caption).foregroundStyle(TeaTheme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                }
                .buttonStyle(TeaButtonStyle(prominent: false))
            }
            Button {
                if access.authorizeHosting() { session.create(name: nickname) }
                else { purchaseReason = .hosting }
            } label: {
                Text("创建牌桌").frame(maxWidth: .infinity)
            }
            .buttonStyle(TeaButtonStyle())
            .accessibilityIdentifier("host-create")
            Text("加入牌友的牌桌始终免费，无需开启体验。")
                .font(.footnote).foregroundStyle(TeaTheme.muted)
            Button {
                showsScanner = true
            } label: {
                Label("扫描邀请码", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TeaButtonStyle(prominent: false))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("邀请码", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("加入") {
                        if let room = inviteRoom { session.join(room, name: nickname) }
                    }
                    .buttonStyle(TeaButtonStyle(prominent: false))
                    .disabled(inviteRoom == nil)
                }
                Text("邀请码和二维码都用于选择附近的牌桌。请与房主保持靠近，并开启 Wi-Fi。")
                    .font(.footnote).foregroundStyle(TeaTheme.muted)
            }
        }
    }

    private var inviteRoom: DiscoveredRoom? {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = session.rooms.filter { $0.code.caseInsensitiveCompare(code) == .orderedSame }
        return matches.count == 1 ? matches[0] : nil
    }

    private var roster: some View {
        Group {
            Text(session.isHost ? "你的牌桌" : "\(session.roomName ?? "牌友")的牌桌")
                .font(.title2.weight(.semibold))
            ForEach(session.players) { player in
                HStack {
                    SeatBadge(seat: player.seat, highlighted: player.seat == .east)
                    Text(player.name)
                    Spacer()
                    Text(player.seat == .east ? "房主" : player.connected ? "已准备" : "正在重新连接")
                        .font(.caption).foregroundStyle(TeaTheme.muted)
                }
                .frame(minHeight: TeaTheme.hitTarget)
            }
            if session.isHost {
                Text(session.canStart ? "空位将由电脑玩家补齐。" : "等待至少一位牌友加入。")
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
                Text("等待房主开始").font(.footnote).foregroundStyle(TeaTheme.muted)
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
                            .frame(width: 190, height: 190)
                            .padding(16).background(.white)
                            .accessibilityLabel("牌桌邀请二维码")
                    }
                    Text(id.uuidString.prefix(4)).font(.largeTitle.monospaced())
                    Text("请牌友在「附近联机」中扫描二维码，或输入上方的邀请码。")
                        .font(.subheadline).multilineTextAlignment(.center)
                }
                .padding(TeaTheme.gutter)
                .frame(maxWidth: .infinity)
            }
            .modifier(HingeSafeContent())
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
