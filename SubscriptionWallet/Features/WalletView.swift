import SwiftUI

private enum WalletFilter: String, CaseIterable {
    case all = "全部", held = "进行中", upcoming = "即将续费", archived = "已归档"
}
struct WalletView: View {
    var onCheckup: () -> Void = {}
    @Environment(WalletRepository.self) var repo
    @Environment(NotificationCoordinator.self) var notifications
    @State private var selection: WalletFilter = .all
    @State var adding = false
    @State var explanation = false
    @State private var reordering = false
    var today: LocalDate { LocalDate(date: Date()) }
    var summary: CostSummary { CostCalculator.summary(repo.records, preferences: repo.preferences, today: today) }
    /// Monthly equivalents of up to 7 current paid members, low to high.
    var bars: [Decimal] {
        Array(repo.records.filter { StatusResolver.status($0, today: today).held }
            .compactMap { CostCalculator.annual($0, preferences: repo.preferences).map { $0 / 12 } }.sorted().suffix(7))
    }
    var displayed: [Subscription] {
        let list = repo.records.filter { member in
            switch selection {
            case .all: return !member.isArchived
            case .held: return StatusResolver.status(member, today: today).held
            case .archived: return member.isArchived
            case .upcoming:
                guard !member.isArchived, let event = EventResolver.event(member), event.kind != "expiry" else { return false }
                return event.date >= today && event.date <= today.adding(days: 30)
            }
        }
        // “即将续费”按日期最近排；其余按用户拖出来的顺序（没拖过就按最近事件）。
        return selection == .upcoming ? list.sorted(by: memberOrder) : WalletOrdering.apply(list, order: repo.preferences.walletOrder)
    }
    /// 首页长按拖动后的新顺序：拖的这一页排在前面，没出现在这一页的接在后面保持原样。
    private func commitOrder(_ list: [Subscription]) {
        let rest = WalletOrdering.apply(repo.records.filter { r in !list.contains { $0.id == r.id } }, order: repo.preferences.walletOrder)
        try? repo.saveWalletOrder(list.map(\.id) + rest.map(\.id))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("订阅猫").font(.largeTitle.bold())
                        #if DEBUG
                        if PreviewFixtures.enabled { Text("界面演示 · 金额为虚构示例").font(.caption2).foregroundStyle(Theme.secondary) }
                        #endif
                    }
                    Spacer()
                    if repo.records.filter({ !$0.isArchived }).count > 1 {
                        Button { reordering = true } label: {
                            Image(systemName: "arrow.up.arrow.down").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.accent)
                                .frame(width: 44, height: 44).background(Theme.surface, in: Circle()).shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                        }.buttonStyle(PressScale()).accessibilityLabel("调整顺序").accessibilityIdentifier("walletReorder")
                    }
                    Button { adding = true } label: {
                        Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 44).background(Theme.actionGradient, in: Circle()).shadow(color: Theme.action.opacity(0.3), radius: 8, y: 3)
                    }.accessibilityLabel("添加会员").accessibilityIdentifier("walletAdd")
                }
                if repo.records.isEmpty {
                    VStack(alignment: .leading, spacing: 24) {
                        CatLayeredArt().frame(maxWidth: .infinity).frame(height: 240).padding(.top, 8)
                        Text("给会员，一个清楚的位置").font(.title2.weight(.semibold))
                        Text("把你的第一个会员放进钱包。\n费用、权益和日期，都整理在这里。").foregroundStyle(Theme.secondary)
                        PrimaryButton(title: "手动添加") { adding = true }.accessibilityIdentifier("addFirst")
                        SecondaryButton(title: "快速回想有哪些会员", action: onCheckup).accessibilityIdentifier("walletStartCheckup")
                        Text("无需登录，资料保存在这台设备。").font(.footnote).foregroundStyle(Theme.secondary)
                    }.padding(.bottom, 48)
                } else {
                    UnderlineTabs(items: WalletFilter.allCases.map { ($0, $0.rawValue) }, selection: $selection)
                    Button { explanation = true } label: { WalletOverview(summary: summary, bars: bars, ears: true) }.buttonStyle(PressScale()).padding(.top, 14)
                    if displayed.isEmpty {
                        Text("这个分类下还没有会员。").foregroundStyle(Theme.secondary).padding(.vertical, 24)
                    } else {
                        WalletPassStack(records: displayed, today: today, onReorder: selection == .upcoming ? nil : commitOrder).padding(.top, 4)
                            .background(alignment: .bottomTrailing) {
                                CatTail().stroke(Theme.catAccent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                                    .frame(width: 70, height: 80).offset(x: 26, y: 26).accessibilityHidden(true)
                            }
                    }
                    HStack(spacing: 10) {
                        NavigationLink { MemberListView() } label: { QuickLink(title: "全部 \(repo.records.count) 项", symbol: "list.bullet") }
                        NavigationLink { ReminderCenterView() } label: { QuickLink(title: "即将续费", symbol: "calendar") }.accessibilityIdentifier("openReminders")
                        if summary.held > 0 {
                            NavigationLink { SharePreviewView() } label: { QuickLink(title: "分享", symbol: "square.and.arrow.up") }.accessibilityIdentifier("openShare")
                        }
                    }.buttonStyle(PressScale()).padding(.top, 8)
                    if summary.review > 0 { Text("\(summary.review) 项日期需要核对").font(.footnote).foregroundStyle(Theme.warning) }
                }
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 28)
        }.background(Theme.background).navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $adding) { SubscriptionEditor() }
            .sheet(isPresented: $reordering) { WalletReorderView() }
            .alert("费用折算说明", isPresented: $explanation) { Button("知道了", role: .cancel) {} } message: {
                Text("按当前记录折算，非实际扣款账单。未知金额不作为零；联名与赠送不重复计算费用。旧版费用数据保持原有口径。")
            }
    }
}
struct QuickLink: View {
    let title: String
    let symbol: String
    var body: some View {
        Label(title, systemImage: symbol).font(.footnote.weight(.medium)).foregroundStyle(Theme.text).lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 44).card(radius: 14)
    }
}
func memberOrder(_ a: Subscription, _ b: Subscription) -> Bool {
    let da = EventResolver.event(a)?.date, db = EventResolver.event(b)?.date
    if let da, let db, da != db { return da < db }
    if da != nil && db == nil { return true }
    if da == nil && db != nil { return false }
    return a.updatedAt > b.updatedAt
}
struct MemberListView: View {
    @Environment(WalletRepository.self) var repo
    @Environment(NotificationCoordinator.self) var notifications
    @State var search = ""
    @State var category = "all"
    @State var source = "all"
    @State var status = "held"
    @State var sort = "event"
    @State var error: String?
    var today: LocalDate { LocalDate(date: Date()) }
    var filtered: [Subscription] {
        repo.records.filter { s in
            let state = StatusResolver.status(s, today: today)
            let aliasMatch = s.serviceID.flatMap { id in repo.catalog.first { $0.id == id } }?.matches(search) ?? false
            return (search.isEmpty || s.name.localizedCaseInsensitiveContains(search) || s.planLabel.localizedCaseInsensitiveContains(search) || aliasMatch)
            && (category == "all" || s.categoryRaw == category)
            && (source == "all" || (source == "gifts" ? [.bundled, .gifted].contains(s.acquisition) : s.acquisitionRaw == source))
            && (status == "all" || (status == "held" ? state.held : state.rawValue == status))
        }.sorted { a, b in
            if sort == "name" { return a.name.localizedStandardCompare(b.name) == .orderedAscending }
            if sort == "cost" {
                let ca = CostCalculator.annual(a, preferences: repo.preferences), cb = CostCalculator.annual(b, preferences: repo.preferences)
                if let ca, let cb, ca != cb { return ca > cb }; if ca != nil && cb == nil { return true }; if ca == nil && cb != nil { return false }
            }
            return memberOrder(a, b)
        }
    }
    private var categoryTabs: [(String, String)] {
        [("all", "全部")] + Category.allCases.filter { c in repo.records.contains { $0.category == c } }.map { ($0.rawValue, $0.shortTitle) }
    }
    var body: some View {
        List {
            Section {
                ForEach(filtered) { s in
                    NavigationLink { SubscriptionDetailView(id: s.id) } label: { MemberRow(member: s, today: today, reminder: notifications.states[s.id]) }
                        .listRowBackground(Theme.surface)
                        .swipeActions { Button(s.isArchived ? "恢复" : "归档") { archive(s) }.tint(Theme.accent) }
                }
                if filtered.isEmpty { Text(search.isEmpty ? "这个分类下还没有会员。" : "没有找到，试试添加自定义会员。").foregroundStyle(Theme.secondary).listRowBackground(Theme.surface) }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    UnderlineTabs(items: categoryTabs, selection: $category)
                    Text("\(filtered.count) 项 · \(statusTitle)").font(.caption).foregroundStyle(Theme.secondary).textCase(nil)
                }.listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 8, trailing: 4))
            } footer: {
                if filtered.count > 3 { Label("就这些啦", systemImage: "pawprint.fill").font(.caption).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity).padding(.top, 10) }
            }
        }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Theme.background)
            .searchable(text: $search, prompt: "名称、别名或套餐")
            .toolbar(.visible, for: .navigationBar).navigationTitle("我的订阅").navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("状态", selection: $status) { Text("当前持有").tag("held"); Text("全部记录").tag("all"); ForEach(MemberStatus.allCases.filter { $0 != .active }) { Text($0.title).tag($0.rawValue) } }
                        Picker("来源", selection: $source) { Text("全部来源").tag("all"); Text("自费").tag("paid"); Text("联名/赠送").tag("gifts"); Text("来源待确认").tag("unknown") }
                        Picker("排序", selection: $sort) { Text("最近事件").tag("event"); Text("月均从高到低").tag("cost"); Text("名称").tag("name") }
                    } label: { Image(systemName: "line.3.horizontal.decrease") }.accessibilityLabel("筛选与排序")
                }
            }
            .alert("操作未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(error ?? "") }
    }
    private var statusTitle: String {
        switch status { case "held": "当前持有"; case "all": "全部记录"; default: MemberStatus(rawValue: status)?.title ?? "" }
    }
    func archive(_ s: Subscription) { do { try repo.setArchived(s, !s.isArchived); Task { await notifications.reconcile(repo.records, preferences: repo.preferences, changedIDs: [s.id]) } } catch { self.error = error.localizedDescription } }
}

struct MemberRow: View {
    let member: Subscription
    let today: LocalDate
    var reminder: String? = nil
    @Environment(\.dynamicTypeSize) private var size
    var body: some View {
        AdaptiveRow {
            BrandMark(member, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(member.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(Money.short(member)).font(.footnote).monospacedDigit().foregroundStyle(Theme.text).lineLimit(1)
                Text(EventResolver.dateLabel(member, today: today)).font(.caption2).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            if !size.isAccessibilitySize { Spacer(minLength: 6) }
            StatusPill(status: StatusResolver.status(member, today: today))
        }.padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint(reminder ?? "")
    }
}
