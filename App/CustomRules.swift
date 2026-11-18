import Foundation
import FuzhouCore
import Observation
import SwiftUI

@MainActor
@Observable
final class RulesetLibrary {
    static let maximumPresets = 5
    private static let key = "table.custom-rulesets.v1"
    private let defaults: UserDefaults
    private(set) var presets: [FuzhouHouseRules]
    var canAddPreset: Bool { presets.count < Self.maximumPresets }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        presets = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([FuzhouHouseRules].self, from: $0) } ?? []
    }

    func preset(for selection: String) -> FuzhouHouseRules? {
        guard let id = UUID(uuidString: selection) else { return nil }
        return presets.first { $0.id == id }
    }

    func nameError(for rules: FuzhouHouseRules) -> String? {
        let name = rules.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "请给这套规则起个名字。" }
        if name.count > 32 { return "规则名称最多 32 个字符。" }
        if presets.contains(where: { $0.id != rules.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return "已有一套同名规则，请换个名字。"
        }
        return nil
    }

    func save(_ draft: FuzhouHouseRules) -> Bool {
        guard nameError(for: draft) == nil else { return false }
        var rules = draft
        rules.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = presets
        if let index = updated.firstIndex(where: { $0.id == rules.id }) {
            updated[index] = rules
        } else {
            guard canAddPreset else { return false }
            updated.append(rules)
        }
        return persist(updated)
    }

    func delete(_ id: UUID) -> Bool {
        persist(presets.filter { $0.id != id })
    }

    private func persist(_ updated: [FuzhouHouseRules]) -> Bool {
        guard let data = try? JSONEncoder().encode(updated) else { return false }
        defaults.set(data, forKey: Self.key)
        presets = updated
        return true
    }
}

extension FuzhouHouseRules.DiscardPayment {
    var title: String { self == .discarder ? "放炮的人付分" : "其余三家各付分" }
}

extension FuzhouHouseRules.Flush {
    var title: String {
        switch self {
        case .disabled: "不加分"
        case .wildcard: "金可代牌"
        case .faceValue: "金按牌面"
        }
    }
}

extension FuzhouHouseRules {
    var summary: String {
        [keepDealerOnDraw ? "流局连庄" : "流局换庄", "接炮胡时\(discardPayment.title)",
         flush == .disabled ? "清一色不加分" : "清一色时\(flush.title)",
         stackBonuses ? "特殊加分可叠加" : "特殊加分只取最高的一项"].joined(separator: "。")
    }
}

struct RulesetPicker: View {
    let title: String
    @Binding var selection: FuzhouRuleset
    @Binding var selectedCustomID: String
    @Environment(RulesetLibrary.self) private var library
    @State private var showsLibrary = false

    var body: some View {
        let custom = library.preset(for: selectedCustomID)
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(TeaTheme.muted)
                .accessibilityHidden(true)
            HStack(spacing: 6) {
                ForEach(FuzhouRuleset.builtIn, id: \.self) { ruleset in
                    let selected = custom == nil && selection == ruleset
                    Button {
                        selection = ruleset
                        selectedCustomID = ""
                    } label: {
                        Text(ruleset.title).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TeaButtonStyle(prominent: selected))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
            .accessibilityIdentifier("ruleset-picker")

            Menu {
                ForEach(library.presets) { preset in
                    Button {
                        selectedCustomID = preset.id.uuidString
                    } label: {
                        if preset.id == custom?.id { Label(preset.name, systemImage: "checkmark") }
                        else { Text(preset.name) }
                    }
                    .accessibilityIdentifier("select-custom-\(preset.id.uuidString)")
                }
                Button("管理自定义规则", systemImage: "slider.horizontal.3") { showsLibrary = true }
                    .accessibilityIdentifier("manage-custom-rules")
            } label: {
                HStack {
                    Label(custom?.name ?? "自定义规则", systemImage: custom == nil ? "slider.horizontal.3" : "checkmark.circle.fill")
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: TeaTheme.hitTarget)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("custom-rules-menu")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .teaPanel(corner: TeaTheme.controlCorner)
        .sheet(isPresented: $showsLibrary) {
            CustomRulesLibrary(template: selection) { selectedCustomID = $0.uuidString }
        }
    }
}

private struct CustomRulesLibrary: View {
    let template: FuzhouRuleset
    let select: (UUID) -> Void
    @Environment(RulesetLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        CustomRulesEditor(rules: FuzhouHouseRules(name: "", flush: template.defaultFlush),
                                          selectOnSave: select)
                    } label: {
                        Label("新建一套规则", systemImage: "plus")
                    }
                    .disabled(!library.canAddPreset)
                    .accessibilityIdentifier("add-custom-rules")
                } footer: {
                    if !library.canAddPreset {
                        Text("最多保存 \(RulesetLibrary.maximumPresets) 套自定义规则。少于 \(RulesetLibrary.maximumPresets) 套时可再新建。")
                            .accessibilityIdentifier("custom-rules-limit")
                    }
                }
                .listRowBackground(TeaTheme.surface)

                if !library.presets.isEmpty {
                    Section("已保存 \(library.presets.count) 套") {
                        ForEach(library.presets) { preset in
                            NavigationLink {
                                CustomRulesEditor(rules: preset)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(preset.name)
                                    Text(preset.summary).font(.footnote).foregroundStyle(TeaTheme.muted)
                                }
                            }
                        }
                    }
                    .listRowBackground(TeaTheme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .teaBackdrop()
            .modifier(HingeSafeContent())
            .navigationTitle("自定义规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}

private struct CustomRulesEditor: View {
    @State var rules: FuzhouHouseRules
    var selectOnSave: ((UUID) -> Void)? = nil
    @Environment(RulesetLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDelete = false
    @State private var storageError = false

    var body: some View {
        let nameError = library.nameError(for: rules)
        Form {
            Section("名称") {
                TextField("规则名称", text: $rules.name)
                    .accessibilityIdentifier("custom-rules-name")
                if !rules.name.isEmpty, let nameError { Text(nameError).font(.footnote).foregroundStyle(TeaTheme.loss) }
                Menu("从内置玩法复制设置", systemImage: "square.on.square") {
                    ForEach(FuzhouRuleset.builtIn, id: \.self) { preset in
                        Button(preset.title) { applyTemplate(preset) }
                    }
                }
                .accessibilityIdentifier("custom-rules-template")
            }
            .listRowBackground(TeaTheme.surface)

            Section {
                Toggle("流局连庄", isOn: $rules.keepDealerOnDraw)
                Picker("接炮胡时谁付分", selection: $rules.discardPayment) {
                    ForEach(FuzhouHouseRules.DiscardPayment.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("custom-discard-payment")
            } header: {
                Text("庄家与付分")
            } footer: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(rules.keepDealerOnDraw ? "流局后，这一局的庄家继续坐庄。" : "流局后，由庄家的下家坐庄。")
                    Text(RuleScoringExample.discard(payment: rules.discardPayment))
                        .accessibilityIdentifier("custom-payment-example")
                }
            }
            .listRowBackground(TeaTheme.surface)

            Section {
                Picker("清一色", selection: $rules.flush) {
                    ForEach(FuzhouHouseRules.Flush.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("custom-flush-rule")
                Toggle("叠加特殊加分", isOn: $rules.stackBonuses)
            } header: {
                Text("胡牌加分")
            } footer: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(rules.flush.explanation)
                    if let count = RuleOdds.count(for: .pureSuit, flush: rules.flush) {
                        Text("清一色参考概率 · \(RuleOdds.rate(count))")
                            .accessibilityIdentifier("custom-flush-estimate")
                    }
                    Text(RuleScoringExample.bonuses(flush: rules.flush, stacks: rules.stackBonuses))
                        .accessibilityIdentifier("custom-bonus-example")
                }
            }
            .listRowBackground(TeaTheme.surface)

            Section {
                NavigationLink {
                    RuleGuide(startingAt: .scoring, houseRules: rules)
                } label: {
                    Label("计分与概率", systemImage: "chart.bar.xaxis")
                }
                .accessibilityIdentifier("custom-rules-reference")
            }
            .listRowBackground(TeaTheme.surface)

            if selectOnSave == nil {
                Section {
                    Button("删除这套规则", role: .destructive) { confirmsDelete = true }
                }
                .listRowBackground(TeaTheme.surface)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .teaBackdrop()
        .modifier(HingeSafeContent())
        .navigationTitle(selectOnSave == nil ? "编辑规则" : "新建规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    guard library.save(rules) else { storageError = true; return }
                    selectOnSave?(rules.id)
                    dismiss()
                }
                .disabled(nameError != nil)
                .accessibilityIdentifier("save-custom-rules")
            }
        }
        .alert("删除这套规则？", isPresented: $confirmsDelete) {
            Button("删除", role: .destructive) {
                if library.delete(rules.id) { dismiss() }
                else { storageError = true }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("未能保存规则更改", isPresented: $storageError) {
            Button("好", role: .cancel) {}
        }
    }

    private func applyTemplate(_ preset: FuzhouRuleset) {
        let template = FuzhouHouseRules(name: "", flush: preset.defaultFlush)
        rules.keepDealerOnDraw = template.keepDealerOnDraw
        rules.discardPayment = template.discardPayment
        rules.flush = template.flush
        rules.stackBonuses = template.stackBonuses
    }
}
