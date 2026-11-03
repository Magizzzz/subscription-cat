import SwiftUI

struct SubscriptionEditor: View {
    @Environment(WalletRepository.self) var repo
    @Environment(NotificationCoordinator.self) var notifications
    @Environment(\.dismiss) var dismiss
    private enum TextFieldFocus: Hashable { case name, plan, amount, source, notes }
    @FocusState private var focusedField: TextFieldFocus?
    @State var draft: Subscription
    private let original: Subscription?
    private let checkupChoice: CheckupChoice?
    private let onDraft: ((Subscription) throws -> Void)?
    @State var amount = ""
    @State var feeConfirmation = false
    @State var error: String?
    @State var saving = false
    @State var showError = false
    @State var sourceConfirmation = false
    @State var permissionExplanation = false
    @State var duplicate: Subscription?
    @State var duplicateWarning = false
    @State var ignoreNameDuplicate = false
    @State var openExisting: Subscription?
    @State var suggestions = true
    @State var pendingSave: Subscription?
    init(subscription: Subscription? = nil, checkupChoice: CheckupChoice? = nil, onDraft: ((Subscription) throws -> Void)? = nil) {
        original = subscription; self.checkupChoice = checkupChoice; self.onDraft = onDraft
        var initial = subscription ?? Subscription()
        if let choice = checkupChoice { initial.acquisition = choice == .paid ? .paid : (initial.acquisition == .gifted ? .gifted : .bundled) }
        _draft = State(initialValue: initial)
        let value = subscription ?? Subscription()
        _amount = State(initialValue: SimpleFeeEntry.displayAmount(value))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("会员名称（必填）", text: $draft.name).accessibilityIdentifier("memberName").focused($focusedField, equals: .name)
                        .onChange(of: draft.name) { _, new in if onDraft == nil, let id = draft.serviceID, repo.catalog.first(where: { $0.id == id })?.name != new { draft.serviceID = nil; suggestions = true } }
                    if suggestions && original == nil && !draft.name.isEmpty {
                        ForEach(Array(repo.catalog.filter { $0.matches(draft.name) }.prefix(5))) { item in
                            Button { select(item) } label: { HStack(spacing: 10) { BrandMark(style: BrandStyle.of(item.id, name: item.name, category: Category(rawValue: item.category)), assetID: item.id, size: 26); Text(item.name); Spacer(); Text(Category(rawValue: item.category)?.title ?? "").font(.caption).foregroundStyle(Theme.secondary) } }
                        }
                    }
                    TextField("套餐备注（可选）", text: $draft.planLabel).focused($focusedField, equals: .plan)
                } header: { Text(onDraft == nil ? "这是什么会员？" : "已有资料已预填；留空保留原值，可全部以后补。") }
                Section {
                    CategoryPicker(selected: $draft.categoryRaw)
                    if draft.category == nil { Text("请选择一个分类，目录服务会带出默认分类。").font(.caption).foregroundStyle(error != nil ? Theme.destructive : Theme.secondary) }
                } header: { Text("分类 · 必选") }
                Section {
                    Picker("会员来源", selection: $draft.acquisitionRaw) { ForEach(Acquisition.allCases.filter { checkupChoice == nil || (checkupChoice == .paid ? $0 == .paid : [.bundled, .gifted].contains($0)) }) { Text($0.title).tag($0.rawValue) } }
                } header: { Text("来源") } footer: { Text("联名和赠送只记录权益，不重复计算费用。") }
                if draft.acquisition == .paid {
                    Section {
                        HStack {
                            Text("金额")
                            Spacer()
                            Text("¥").foregroundStyle(Theme.secondary)
                            TextField("可留空", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .accessibilityLabel("金额，人民币").accessibilityIdentifier("amount").focused($focusedField, equals: .amount)
                        }
                        Picker("付费周期", selection: $draft.billingCycleRaw) { ForEach(Cycle.allCases) { Text($0.title).tag($0.rawValue) } }.accessibilityIdentifier("billingCycle")
                        if draft.cycle == .oneOff {
                            Toggle("买断 / 永久", isOn: $draft.isLifetime)
                        }
                        if let original, SimpleFeeEntry.isLegacy(original) {
                            Text("旧费用：" + Money.label(original)).font(.footnote).foregroundStyle(Theme.secondary)
                            Text("旧记录会保留；填写新的人民币金额时，确认后再替换。").font(.caption).foregroundStyle(Theme.secondary)
                        }
                    } header: { Text("费用") } footer: { Text("统一按人民币记录，可留空以后补。") }
                }

                if draft.acquisition == .bundled {
                    Section("联名来源") {
                        Picker("关联自费主会员", selection: Binding(get: { draft.sourceSubscriptionID?.uuidString ?? "" }, set: { raw in draft.sourceSubscriptionID = UUID(uuidString: raw); if let p = repo.records.first(where: { $0.id == draft.sourceSubscriptionID }) { draft.sourceName = p.name } })) {
                            Text("不关联 / 手填来源").tag("")
                            ForEach(repo.records.filter { $0.acquisition == .paid && $0.id != draft.id }) { Text($0.name + ($0.isArchived ? "（已归档）" : "")).tag($0.id.uuidString) }
                        }
                        TextField("来源名称，例如88VIP", text: $draft.sourceName).focused($focusedField, equals: .source)
                    }
                }
                if draft.acquisition == .gifted { Section("赠送来源") { TextField("来源备注（可选，不必写人名）", text: $draft.sourceName).focused($focusedField, equals: .source) } }
                if !(draft.cycle == .oneOff && draft.isLifetime && draft.acquisition == .paid) {
                    Section {
                        if draft.acquisition == .paid && draft.cycle != .oneOff {
                            Picker("自动续费", selection: $draft.autoRenewRaw) { ForEach(AutoRenew.allCases) { Text($0.title).tag($0.rawValue) } }
                            OptionalDatePicker(title: draft.isTrial ? "试用结束日" : "下次预计续费日", value: $draft.nextChargeOn)
                        }
                        OptionalDatePicker(title: "权益到期日", value: $draft.accessEndsOn)
                        if draft.acquisition == .paid && draft.autoRenew == .unknown && draft.chargeDate != nil && draft.endDate != nil && !draft.isTrial {
                            Picker("提醒哪一个日期", selection: $draft.preferredEventRaw) { Text("较早日期").tag("earliest"); Text("预计续费").tag("renewal"); Text("权益到期").tag("expiry") }
                        }
                    } header: { Text("日期 · 可以以后补") } footer: { Text("日期和提醒按北京时间计算；日期过去不会自动记录已扣款。") }
                }
                Section {
                    Toggle("提醒我", isOn: $draft.reminderEnabled).disabled(!draft.hasDate).accessibilityIdentifier("reminderEnabled")
                    if draft.hasDate {
                        Picker("提前提醒", selection: $draft.reminderLeadDays) { ForEach([0,1,3,7], id: \.self) { Text($0 == 0 ? "当天" : "提前\($0)天").tag($0) } }
                    } else { Text("填写可用日期后可提醒。").font(.caption).foregroundStyle(Theme.secondary) }
                } header: { Text("提醒") } footer: { Text("仅在你希望提醒时申请系统权限；通知从不显示金额。") }
                Section("备注") { TextField("不要填写账号密码（最多500字）", text: $draft.notes, axis: .vertical).lineLimit(3...6).focused($focusedField, equals: .notes) }
                if let error { Section { Text(error).foregroundStyle(Theme.destructive).accessibilityIdentifier("saveError") } }
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            // Keep keyboard dismissal outside the keyboard toolbar, whose initial
            // layout emits a non-finite frame warning on the tested iOS runtime.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focusedField != nil {
                    HStack {
                        Spacer()
                        Button("收起键盘") { focusedField = nil }
                            .frame(minHeight: 44).padding(.horizontal, 16)
                    }.background(Theme.surface)
                }
            }
            .navigationTitle(onDraft != nil ? "补充体检资料" : original == nil ? "添加会员" : "编辑会员").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "保存中…" : onDraft != nil ? "保存回答" : "保存") { prepareSave() }.fontWeight(.semibold).disabled(saving).accessibilityIdentifier("saveMember") }
            }
            .onAppear { if original == nil { draft.reminderLeadDays = repo.preferences.defaultLeadDays } }
            .onChange(of: draft.nextChargeOn) { old, new in if old != new { draft.recurrenceAnchorOn = new }; dateChanged(old: old, new: new) }
            .onChange(of: draft.accessEndsOn) { old, new in dateChanged(old: old, new: new) }
            .onChange(of: draft.billingCycleRaw) { _, _ in if draft.cycle != .oneOff { draft.isLifetime = false }; if draft.cycle == .oneOff && original?.isTrial != true { draft.isTrial = false } }
            .alert("暂时无法保存", isPresented: $showError) { Button("返回修改", role: .cancel) {} } message: { Text(error ?? "请检查填写内容。") }
            .alert("替换旧费用记录？", isPresented: $feeConfirmation) {
                Button("改用这笔人民币金额") { prepareSave(feeApproved: true) }
                Button("返回检查", role: .cancel) {}
            } message: { Text("原币种、试用或下期价格将替换为当前填写的一笔人民币金额。没有填写或没有修改金额时会保留旧费用。") }
            .alert("费用将退出统计", isPresented: $sourceConfirmation) {
                Button("确认更改来源") { prepareSave(sourceApproved: true) }; Button("返回检查", role: .cancel) {}
            } message: { Text("将清空费用、周期、试用及续费设置，保留权益到期日，并重新安排提醒。") }
            .alert("钱包里可能已有这项会员", isPresented: $duplicateWarning) {
                Button("打开已有") { openExisting = duplicate }
                if draft.serviceID == nil { Button("仍然添加") { ignoreNameDuplicate = true; prepareSave() } }
                Button("返回检查", role: .cancel) {}
            } message: { Text(duplicate?.isArchived == true ? "这项记录已归档，可打开后恢复。" : "可编辑已有记录，避免重复记录权益。") }
            .sheet(item: $openExisting) { s in NavigationStack { SubscriptionDetailView(id: s.id).toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { openExisting = nil } } } } }
            .sheet(isPresented: $permissionExplanation) {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "bell.badge").font(.largeTitle).foregroundStyle(Theme.accent)
                    Text("在关键日期前，提醒你看一眼").font(.title2.weight(.semibold))
                    Text("会员已保存在本机。允许通知后，我们会按北京时间安排本地提醒，不显示金额。系统可能受专注模式等影响，无法保证送达。").foregroundStyle(Theme.secondary)
                    PrimaryButton(title: "允许系统通知", symbol: "bell") { permissionExplanation = false; finishAfterPermission(request: true) }
                    Button("暂不开启") { permissionExplanation = false; finishAfterPermission(request: false) }.frame(maxWidth: .infinity, minHeight: 44)
                }.padding(28).presentationDetents([.medium, .large]).interactiveDismissDisabled()
            }
        }.interactiveDismissDisabled(saving)
    }
    func select(_ item: CatalogItem) {
        draft.name = item.name; draft.serviceID = item.id; draft.categoryRaw = item.category; suggestions = false
        if let existing = repo.existing(serviceID: item.id) { duplicate = existing; duplicateWarning = true }
    }
    func dateChanged(old: String?, new: String?) { if old == nil && new != nil { draft.reminderEnabled = true }; if !draft.hasDate { draft.reminderEnabled = false } }
    func prepareSave(sourceApproved: Bool = false, feeApproved: Bool = false) {
        error = nil
        let hasPreviousPaidData = original.map { old in repo.records.contains { $0.id == old.id } || old.amountMinor != nil || old.nextPeriodAmountMinor != nil || old.cycle != .unknown || old.isTrial || old.nextChargeOn != nil } ?? false
        if original?.acquisition == .paid && draft.acquisition != .paid && hasPreviousPaidData && !sourceApproved { sourceConfirmation = true; return }
        do {
            var s = draft
            if s.acquisition == .paid {
                if try SimpleFeeEntry.needsConfirmation(s, text: amount, original: original), !feeApproved { feeConfirmation = true; return }
                s = try SimpleFeeEntry.resolve(s, text: amount, original: original, preserveBlank: onDraft != nil, allowLegacyReplacement: feeApproved)
                if s.cycle != .oneOff { s.isLifetime = false }
                if s.isLifetime { s.nextChargeOn = nil; s.accessEndsOn = nil; s.reminderEnabled = false }
            } else {
                s.amountMinor = nil; s.nextPeriodAmountMinor = nil; s.cycle = .unknown; s.isTrial = false; s.isLifetime = false; s.autoRenew = .unknown; s.nextChargeOn = nil; s.recurrenceAnchorOn = nil; s.amountConfidenceRaw = "unknown"
                if s.acquisition != .bundled { s.sourceSubscriptionID = nil }
            }
            if !s.hasDate { s.reminderEnabled = false }
            if onDraft == nil && original == nil && !ignoreNameDuplicate {
                let normalized = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let match = repo.records.first { $0.name.caseInsensitiveCompare(normalized) == .orderedSame || (s.serviceID != nil && $0.serviceID == s.serviceID) }
                let alias = repo.catalog.first { ([$0.name] + $0.aliases).contains { $0.caseInsensitiveCompare(normalized) == .orderedSame } }
                if let match = match ?? alias.flatMap({ repo.existing(serviceID: $0.id) }) { duplicate = match; duplicateWarning = true; return }
                if s.serviceID == nil, let alias { s.serviceID = alias.id }
            }
            if onDraft != nil, let original { s = try CheckupEngine.preservingBlanks(s, original: original, preserveNextPeriodAmount: false) }
            if s.isLifetime { s.nextChargeOn = nil; s.recurrenceAnchorOn = nil; s.accessEndsOn = nil; s.reminderEnabled = false }
            try Validator.validate(s, all: repo.records)
            if let onDraft { try onDraft(s); dismiss(); return }
            saving = true
            try repo.save(s)
            pendingSave = s
            Task {
                let status = await UNPermission.current()
                if s.reminderEnabled && status { permissionExplanation = true }
                else { await notifications.reconcile(repo.records, preferences: repo.preferences, changedIDs: [s.id]); saving = false; dismiss() }
            }
        } catch { saving = false; self.error = error.localizedDescription; showError = true }
    }
    func finishAfterPermission(request: Bool) {
        Task { if request { await notifications.requestPermission() }; await notifications.reconcile(repo.records, preferences: repo.preferences, changedIDs: Set([pendingSave?.id].compactMap { $0 })); saving = false; dismiss() }
    }
}
import UserNotifications
private enum UNPermission { static func current() async -> Bool { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined } }
struct OptionalDatePicker: View {
    let title: String
    @Binding var value: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: Binding(get: { value != nil }, set: { value = $0 ? LocalDate(date: Date()).description : nil })).accessibilityIdentifier("dateToggle-" + title)
            if value != nil {
                DatePicker(title, selection: Binding(get: { value.flatMap(LocalDate.init)?.at() ?? Date() }, set: { value = LocalDate(date: $0).description }), in: LocalDate(year: 1900, month: 1, day: 1).at()...LocalDate(year: 2200, month: 12, day: 31).at(), displayedComponents: .date)
                    .environment(\.timeZone, LocalDate.calendar.timeZone).environment(\.calendar, LocalDate.calendar).environment(\.locale, Locale(identifier: "zh_CN"))
            }
        }
    }
}
