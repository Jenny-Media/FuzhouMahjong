import FuzhouAccess
import SwiftUI

public enum AccessReason: String, Identifiable {
    case settings, solo, hosting
    public var id: String { rawValue }
    var title: String {
        switch self {
        case .settings: "一起开一桌"
        case .solo: "继续你的单机牌局"
        case .hosting: "做房主，邀牌友免费加入"
        }
    }
}

extension GameAccess {
    var statusTitle: String {
        switch tier {
        case .lifetime: "完整版 · 已永久解锁"
        case .trial: "14天免费体验中"
        case .free: hasUsedTrial ? "免费体验已结束" : "免费版"
        }
    }
    var soloAllowanceText: String {
        switch tier {
        case .lifetime: "单机不限局数 · 永久开桌"
        case .trial(let ends): "体验至 \(ends.formatted(date: .abbreviated, time: .omitted)) · 单机和开桌不限次数"
        case .free: "今日还可新开 \(remainingSoloHands) 局单机 · 加入牌桌始终免费"
        }
    }
}

struct PurchaseSheet: View {
    let reason: AccessReason
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        PurchaseView(reason: reason, close: { dismiss() })
    }
}

struct PurchaseView: View {
    let reason: AccessReason
    var close: (() -> Void)? = nil
    @Environment(GameAccess.self) private var access
    @Environment(\.scenePhase) private var scenePhase

    private var catalogIncomplete: Bool {
        access.tier != .lifetime && (access.lifetimeProduct == nil || (!access.hasUsedTrial && access.trialProduct == nil))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(reason.title).font(TeaTheme.display)
                        .accessibilityAddTraits(.isHeader)
                    Text(access.statusTitle).font(.headline).foregroundStyle(TeaTheme.brass)
                        .accessibilityIdentifier("access-status")
                    Text(access.soloAllowanceText).font(.subheadline).foregroundStyle(TeaTheme.muted)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(Felt(inlaid: true))
                VStack(alignment: .leading, spacing: 16) {
                    feature("单机尽兴玩", detail: "与三位电脑玩家对局，不限每日局数。", icon: "person.fill")
                    feature("永久做房主", detail: "解锁后随时创建附近牌桌，牌友免费加入。", icon: "person.3.fill")
                    feature("离线也能玩", detail: "提前联网开启体验或购买，之后可以离线使用。", icon: "wifi.slash")
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .teaPanel()

                if access.tier == .lifetime {
                    Label("已拥有完整版，无需再次购买", systemImage: "checkmark.seal.fill")
                        .font(.headline).foregroundStyle(TeaTheme.gain)
                        .accessibilityIdentifier("lifetime-owned")
                } else {
                    if !access.hasUsedTrial {
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                Task { await access.purchase(GameAccess.trialID) }
                            } label: { Text("开始14天免费体验").frame(maxWidth: .infinity) }
                                .buttonStyle(TeaButtonStyle(prominent: false))
                                .disabled(access.busy || access.loadingProducts || access.pending.contains(GameAccess.trialID)
                                          || access.trialProduct == nil || access.lifetimeProduct == nil)
                                .accessibilityIdentifier("trial-start")
                            Text(trialTerms).font(.footnote).foregroundStyle(TeaTheme.muted)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            Task { await access.purchase(GameAccess.lifetimeID) }
                        } label: {
                            Text(access.lifetimeProduct.map { "\($0.displayPrice) · 永久解锁完整版" } ?? "永久解锁完整版")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TeaButtonStyle())
                        .disabled(access.busy || access.loadingProducts || access.pending.contains(GameAccess.lifetimeID) || access.lifetimeProduct == nil)
                        .accessibilityIdentifier("lifetime-buy")
                        Text("一次购买，无订阅。解锁无限单机和永久开桌，牌友无需购买。")
                            .font(.footnote).foregroundStyle(TeaTheme.muted)
                    }
                }
                if !access.offlineCacheAvailable {
                    Text("当前设备未能保存离线购买凭据。已有权限仍可使用；出发前请恢复购买并确认离线权限。")
                        .font(.footnote).foregroundStyle(TeaTheme.muted)
                }
                if access.busy || access.loadingProducts {
                    ProgressView(access.busy ? "正在处理…" : "正在读取 App Store 价格…")
                }
                if let message = access.message {
                    Text(message).font(.subheadline).foregroundStyle(TeaTheme.muted)
                        .accessibilityIdentifier("purchase-message")
                }
                if catalogIncomplete {
                    if !access.loadingProducts, let message = access.catalogMessage {
                        Text(message).font(.subheadline).foregroundStyle(TeaTheme.muted)
                            .accessibilityIdentifier("purchase-catalog-message")
                    }
                    Button("重新读取购买信息") { Task { await access.loadProducts() } }
                        .buttonStyle(TeaButtonStyle(prominent: false))
                        .disabled(access.busy || access.loadingProducts)
                        .accessibilityIdentifier("purchase-retry")
                }
                Button("恢复购买") { Task { await access.restore() } }
                    .buttonStyle(TeaButtonStyle(prominent: false))
                    .disabled(access.busy).accessibilityIdentifier("purchase-restore")
                Text("免费版每天可以新开2局单机，每局从发牌到胡牌或流局。继续保存的这一局不重复计次。加入牌友的牌桌始终免费，经典与现代牌面、玩法讲解均可使用。")
                    .font(.footnote).foregroundStyle(TeaTheme.muted)
            }
            .padding(TeaTheme.gutter)
            .frame(maxWidth: TeaTheme.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("purchase-scroll")
        .safeAreaInset(edge: .top, spacing: 0) {
            if let close {
                HStack {
                    Text("完整版与免费体验")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button("完成", action: close)
                        .buttonStyle(TeaButtonStyle(prominent: false))
                }
                .padding(.horizontal, TeaTheme.gutter)
                .padding(.vertical, 8)
                .frame(maxWidth: TeaTheme.contentWidth)
                .frame(maxWidth: .infinity)
                .background(TeaTheme.canvas)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(TeaTheme.line).frame(height: 1).allowsHitTesting(false)
                }
            }
        }
        .modifier(HingeSafeContent())
        .teaBackdrop()
        .foregroundStyle(TeaTheme.ink)
        .navigationTitle("完整版与免费体验")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            access.refreshClock()
            if catalogIncomplete { await access.loadProducts() }
        }
    }
    private var trialTerms: String {
        let price = access.lifetimeProduct?.displayPrice ?? "App Store 显示的价格"
        return "体验从确认开启时开始，持续14天，单机和开桌不限次数。到期不会自动扣费；之后每天可新开2局单机，加入牌友的牌桌始终免费。若要继续不限局数玩单机或做房主，可选择以\(price)一次购买完整版。"
    }
    private func feature(_ title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(TeaTheme.brass)
                .frame(width: 34, height: 34)
                .background(TeaTheme.canvas, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(TeaTheme.muted)
            }
        }
    }
}
