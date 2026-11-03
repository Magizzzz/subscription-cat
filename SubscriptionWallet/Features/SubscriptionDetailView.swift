import SwiftUI

struct SubscriptionDetailView: View {
    let id: UUID
    @Environment(WalletRepository.self) var repo
    @Environment(NotificationCoordinator.self) var notifications
    @Environment(\.dismiss) var dismiss
    @State var editing = false
    @State var deleting = false
    @State var archiving = false
    @State var updatingDate = false
    @State var error: String?
    var today: LocalDate { LocalDate(date: Date()) }
    var member: Subscription? { repo.records.first { $0.id == id } }
    var body: some View {
        Group {
            if let s = member {
                ScrollView {
                    VStack(spacing: 0) {
                        DetailHero(member: s)
                        VStack(alignment: .leading, spacing: 14) {
                            costCard(s)
                            infoCard(s)
                            sourceCard(s)
                            if !s.notes.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("备注").font(.subheadline.weight(.semibold))
                                    Text(s.notes).font(.subheadline).foregroundStyle(Theme.secondary)
                                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
                            }
                            Button(s.isArchived ? "恢复这项记录" : "归档这项记录") { archiving = true }
                                .font(.subheadline.weight(.medium)).foregroundStyle(s.isArchived ? Theme.accent : Theme.destructive)
                                .frame(maxWidth: .infinity, minHeight: 50).card(radius: 16)
                            Text("只管理本机记录，不会取消原平台订阅。").font(.caption).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity)
                        }.padding(.horizontal, 16).padding(.top, -28).padding(.bottom, 32)
                    }
                }.background(Theme.background).ignoresSafeArea(edges: .top)
                .toolbarBackground(.hidden, for: .navigationBar).toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar(.visible, for: .navigationBar).navigationTitle("").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("编辑") { editing = true }.tint(.white)
                        Menu { Button("删除本机记录", role: .destructive) { deleting = true } } label: { Image(systemName: "ellipsis") }.tint(.white).accessibilityLabel("更多操作")
                    }
                }
                .sheet(isPresented: $editing) { SubscriptionEditor(subscription: s) }
                .alert("删除这项记录？", isPresented: $deleting) {
                    Button("删除", role: .destructive) { mutate { try repo.delete(s); dismiss() } }; Button("取消", role: .cancel) {}
                } message: { Text("只删除本机记录，不会取消原平台订阅。关联的子权益会保留。") }
                .alert(s.isArchived ? "恢复这项记录？" : "归档这项记录？", isPresented: $archiving) {
                    Button(s.isArchived ? "恢复" : "归档") { mutate { try repo.setArchived(s, !s.isArchived) } }; Button("取消", role: .cancel) {}
                } message: { Text(s.isArchived ? "恢复后将重新计算费用与提醒，请核对金额和日期。" : "只从当前钱包移出并停止本 App 的提醒。如需停止扣费，请到原服务处理。") }
                .alert("确认已核对日期", isPresented: $updatingDate) {
                    Button("更新日期") { if let next = EventResolver.suggestedNext(s, today: today) { var copy = s; copy.nextChargeOn = next.description; mutate { try repo.save(copy) } } }; Button("取消", role: .cancel) {}
                } message: { Text("保留原周期锚点，只更新你确认的日期，不生成付款记录。") }
            } else { ContentUnavailableView("这项记录已移除", systemImage: "wallet.bifold") }
        }
        .alert("操作未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(error ?? "") }
    }
    @ViewBuilder func costCard(_ s: Subscription) -> some View {
        let cost = CostCalculator.summary([s], preferences: repo.preferences, today: today)
        let status = StatusResolver.status(s, today: today)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Money.short(s)).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                Spacer()
                StatusPill(status: status)
            }
            if cost.eligible > 0 { Text("月均折算 \(cost.monthlyDisplay) · 年化约 \(cost.annualDisplay)").font(.footnote).foregroundStyle(Theme.secondary) }
            if s.currency != .CNY, let rate = repo.preferences.exchangeRates[s.currencyCode] { Text("1 \(s.currencyCode) = ¥\(rate)（你设置的固定汇率）").font(.footnote) }
            ForEach(cost.notices, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.warning) }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
    }
    @ViewBuilder func infoCard(_ s: Subscription) -> some View {
        VStack(spacing: 0) {
            if let event = EventResolver.event(s) {
                DetailRow(symbol: "calendar", title: event.title, value: "\(event.date.short)（\(event.date.relative(from: today))）")
            } else {
                DetailRow(symbol: "calendar", title: s.isTrial ? "试用结束日" : "预计续费日", value: s.nextChargeOn ?? "未填写")
            }
            if s.acquisition == .paid {
                DetailRow(symbol: "arrow.triangle.2.circlepath", title: "续费周期", value: s.cycle == .unknown ? "待补" : (s.cycle == .oneOff ? "一次性" : "每\(s.cycle.title)"))
                DetailRow(symbol: "repeat", title: "自动续费", value: s.autoRenew.title)
            }
            DetailRow(symbol: "hourglass", title: "权益到期日", value: s.accessEndsOn ?? "未填写")
            DetailRow(symbol: "bell", title: "提醒", value: s.reminderEnabled ? "提前\(s.reminderLeadDays)天" : "关闭", detail: notifications.states[s.id], last: true)
            VStack(spacing: 6) {
                if let next = EventResolver.suggestedNext(s, today: today), s.acquisition == .paid && !s.isTrial && s.cycle.months != nil {
                    Button("已核对，更新日期至 \(next.description)") { updatingDate = true }
                } else { Button("已核对，编辑日期") { editing = true } }
                if s.isTrial && StatusResolver.status(s, today: today) == .needsReview {
                    Button("已转付费") { convertTrial(s) }
                    Button("已取消（归档）") { archiving = true }
                }
            }.font(.footnote.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44).padding(.bottom, 6)
        }.padding(.horizontal, 18).padding(.top, 6).card()
    }
    @ViewBuilder func sourceCard(_ s: Subscription) -> some View {
        VStack(spacing: 0) {
            DetailRow(symbol: "creditcard", title: "来源", value: s.acquisition.title, last: s.sourceName.isEmpty && s.sourceSubscriptionID == nil && !repo.records.contains { $0.sourceSubscriptionID == s.id })
            if !s.sourceName.isEmpty { DetailRow(symbol: "person.2", title: "来源名称", value: s.sourceName) }
            if let parent = repo.records.first(where: { $0.id == s.sourceSubscriptionID }) {
                NavigationLink { SubscriptionDetailView(id: parent.id) } label: { DetailRow(symbol: "link", title: "来源会员", value: parent.name, chevron: true) }.buttonStyle(.plain)
                if !StatusResolver.status(parent, today: today).held { Text("来源会员已到期/归档，请核对。").font(.footnote).foregroundStyle(Theme.warning).padding(.vertical, 8) }
            }
            ForEach(repo.records.filter { $0.sourceSubscriptionID == s.id }) { child in
                NavigationLink { SubscriptionDetailView(id: child.id) } label: { DetailRow(symbol: "gift", title: "关联权益", value: child.name, chevron: true) }.buttonStyle(.plain)
            }
        }.padding(.horizontal, 18).padding(.vertical, 6).card()
    }
    func mutate(_ action: () throws -> Void) { do { try action(); Task { await notifications.reconcile(repo.records, preferences: repo.preferences, changedIDs: [id]) } } catch { self.error = error.localizedDescription } }
    func convertTrial(_ s: Subscription) {
        var v = s; v.isTrial = false; v.amountMinor = s.nextPeriodAmountMinor; v.nextPeriodAmountMinor = nil
        mutate { try repo.save(v) }; editing = true
    }
}

struct DetailHero: View {
    let member: Subscription
    var body: some View {
        let brand = member.brand
        let base = Theme.fixed(member.serviceID == nil ? heroFallback(member.category) : brand.heroColor)
        VStack(spacing: 10) {
            BrandMark(member, size: 76).shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                .background {
                    CatHead().fill(.white.opacity(0.09)).frame(width: 200, height: 170).offset(y: 18).accessibilityHidden(true)
                }
            Text(member.name).font(.title2.weight(.bold)).foregroundStyle(.white).multilineTextAlignment(.center)
            Text([member.planLabel, member.category?.title ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(.footnote).foregroundStyle(.white.opacity(0.75))
        }
        .padding(.top, 96).padding(.bottom, 52).padding(.horizontal, 24).frame(maxWidth: .infinity)
        .background {
            ZStack {
                LinearGradient(colors: [base, base.opacity(0.85), Theme.fixed(0x120E1C)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [.white.opacity(0.14), .clear], center: .topTrailing, startRadius: 10, endRadius: 260)
            }
            // Stretch with the pull-down overscroll, like Apple's own header images.
            .visualEffect { content, proxy in
                let pull = max(0, proxy.frame(in: .scrollView).minY)
                return content.scaleEffect(y: 1 + pull / max(proxy.size.height, 1), anchor: .bottom)
            }
        }
        .accessibilityElement(children: .combine)
    }
    private func heroFallback(_ c: Category?) -> UInt32 {
        switch c {
        case .aiCreation: 0x2A1F5C
        case .entertainment: 0x5A1E33
        case .storageEfficiency: 0x15497A
        case .readingLearning: 0x3B2A7A
        case .lifeShopping: 0x7A4A0E
        default: 0x3B2A8A
        }
    }
}
struct DetailRow: View {
    let symbol: String
    let title: String
    let value: String
    var detail: String? = nil
    var chevron = false
    var last = false
    @Environment(\.dynamicTypeSize) private var size
    var body: some View {
        VStack(spacing: 0) {
            AdaptiveRow {
                HStack(spacing: 12) {
                    Image(systemName: symbol).font(.subheadline).foregroundStyle(Theme.secondary).frame(width: 22)
                    Text(title).font(.subheadline).foregroundStyle(size.isAccessibilitySize ? Theme.secondary : Theme.text)
                }
                if !size.isAccessibilitySize { Spacer(minLength: 8) }
                VStack(alignment: size.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                    Text(value).font(.subheadline).foregroundStyle(Theme.text).multilineTextAlignment(size.isAccessibilitySize ? .leading : .trailing)
                    if let detail { Text(detail).font(.caption2).foregroundStyle(Theme.secondary).multilineTextAlignment(size.isAccessibilitySize ? .leading : .trailing) }
                }
                if chevron { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary) }
            }.padding(.vertical, 13).contentShape(Rectangle())
            if !last { Divider().padding(.leading, 34) }
        }.accessibilityElement(children: .combine)
    }
}
