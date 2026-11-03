import SwiftUI

struct CheckupReviewView: View {
    @Environment(WalletRepository.self) private var repo
    @Environment(NotificationCoordinator.self) private var notifications
    let session: CheckupSession
    @State private var confirm = false
    @State private var saving = false
    @State private var error: String?
    private var plan: Result<CheckupPlan, Error> { Result { try repo.checkupPlan() } }
    var body: some View {
        List {
            Section {
                Text("提交前，再看一眼").font(.title2.weight(.semibold)).accessibilityIdentifier("checkupReview")
                Text("逐项确认后，一次写入钱包。已有资料留空不会被清除；“没有”默认保留，只有勾选才归档。").foregroundStyle(Theme.secondary)
            }
            if case .success(let plan) = plan {
                Section("将写入的变更 · \(plan.changes.count) 项") {
                    if plan.changes.isEmpty { Text("没有新增或修改，仍会保存本次结果与待确认项。") }
                    ForEach(plan.changes) { change in
                        HStack(spacing: 12) {
                        BrandMark(change.member, size: 36)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(change.kind) · \(change.member.name)").font(.headline)
                            Text("\(change.member.acquisition.title) · \(Money.label(change.member))").font(.subheadline).foregroundStyle(Theme.secondary)
                            if repo.records.first(where: { $0.id == change.member.id })?.acquisition == .paid && change.member.acquisition != .paid { Text("原自费费用将退出统计，付费字段会清空。").font(.caption).foregroundStyle(Theme.warning) }
                        }
                        }
                    }
                }
                Section("提交后的钱包折算") { MoneySummary(summary: plan.result.summary).listRowInsets(EdgeInsets()) }
            } else if case .failure(let failure) = plan {
                Section { Text(failure.localizedDescription).foregroundStyle(Theme.destructive) }
            }
            Section("没有 · 默认保留已有记录") {
                let none = session.answers.filter { $0.choice == .none }
                if none.isEmpty { Text("没有这类回答").foregroundStyle(Theme.secondary) }
                ForEach(none, id: \.serviceID) { answer in
                    if let member = repo.existing(serviceID: answer.serviceID), !member.isArchived {
                        Toggle("归档 \(member.name)", isOn: Binding(get: { session.archiveServiceIDs.contains(answer.serviceID) }, set: { selected in perform { try repo.selectCheckupArchive(serviceID: answer.serviceID, selected: selected) } }))
                            .accessibilityIdentifier("archive-" + answer.serviceID)
                    }
                }
            }
            Section("不确定 · 待确认区") {
                let unsure = session.answers.filter { $0.choice == .unsure }
                if unsure.isEmpty { Text("没有待确认项").foregroundStyle(Theme.secondary) }
                ForEach(unsure, id: \.serviceID) { answer in Text(name(answer.serviceID)) }
                Text("待确认项不新增钱包记录、不计费用。已有记录保持不变。").font(.caption).foregroundStyle(Theme.secondary)
            }
            Section("返回修改回答") {
                DisclosureGroup("逐项查看 20 个回答") {
                    ForEach(session.queue, id: \.self) { id in Button(name(id)) { perform { try repo.revisitCheckupCard(serviceID: id) } } }
                }
            }
            Section {
                Button("撤回上一张") { perform { try repo.previousCheckupCard() } }.disabled(saving)
            }
            if let error { Section { Text(error).foregroundStyle(Theme.destructive) } }
        }.scrollContentBackground(.hidden).background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            Button("确认提交到钱包") { confirm = true }.font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(saving || !canSubmit).accessibilityIdentifier("commitCheckup")
                .padding(.horizontal, 20).padding(.vertical, 8).background(Theme.background)
        }
        .alert("确认写入钱包？", isPresented: $confirm) {
            Button("返回检查", role: .cancel) {}
            Button("确认提交") { commit() }
        } message: { Text("将一次保存上述新增、更新、恢复与已勾选的归档。失败时钱包与草稿保持原样。") }
        .disabled(saving)
    }
    private var canSubmit: Bool { if case .success = plan { return true }; return false }
    private func name(_ id: String) -> String { repo.existing(serviceID: id)?.name ?? repo.catalog.first { $0.id == id }?.name ?? id }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = error.localizedDescription } }
    private func commit() {
        saving = true
        do {
            let changed = try repo.commitCheckup(sessionID: session.id)
            if changed { Task { await notifications.reconcile(repo.records, preferences: repo.preferences) } }
        } catch { self.error = error.localizedDescription }
        saving = false
    }
}

struct CheckupResultContent: View {
    @Environment(WalletRepository.self) private var repo
    @Environment(NotificationCoordinator.self) private var notifications
    let result: CheckupResult
    var onWallet: () -> Void = {}
    @State private var celebrate = false
    @State private var rolled: Double = 0
    @Environment(FindProgress.self) private var progress
    /// Items found in this run, falling back to what this check-up added.
    private var foundCount: Int { progress.items.isEmpty ? result.added + result.restored : progress.items.count }
    /// One real, actionable finding — never a ranking or a “you found everything”.
    private struct Insight { let symbol: String; let title: String; let detail: String; let id: UUID? }
    private var insight: Insight? {
        let today = LocalDate(date: Date())
        let held = repo.records.filter { StatusResolver.status($0, today: today).held }
        if let soon = held.compactMap({ s in EventResolver.event(s).map { (s, $0) } }).filter({ $0.1.kind == "renewal" && $0.1.date >= today && $0.1.date <= today.adding(days: 7) }).min(by: { $0.1.date < $1.1.date }) {
            return Insight(symbol: "calendar.badge.clock", title: "\(soon.0.name) \(soon.1.date.relative(from: today))续费", detail: Money.short(soon.0), id: soon.0.id)
        }
        let video = held.filter { ["tencent_video", "iqiyi", "youku", "mango_tv"].contains($0.serviceID ?? "") && $0.acquisition == .paid }
        if video.count >= 2 { return Insight(symbol: "rectangle.stack", title: "同时开着 \(video.count) 个视频会员", detail: video.map(\.name).joined(separator: "、"), id: nil) }
        let missing = held.filter { $0.acquisition == .paid && $0.amountMinor == nil && $0.nextPeriodAmountMinor == nil }
        if !missing.isEmpty { return Insight(symbol: "yensign.circle", title: "\(missing.count) 项还没有金额", detail: "补上后，年度花费会更准", id: missing.first?.id) }
        return nil
    }
    @ViewBuilder private func insightCard(_ i: Insight) -> some View {
        let content = HStack(spacing: 12) {
            Image(systemName: i.symbol).font(.title3).foregroundStyle(Theme.accent).frame(width: 40, height: 40).background(Theme.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("发现").font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                Text(i.title).font(.subheadline.weight(.semibold))
                Text(i.detail).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer()
            if i.id != nil { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary) }
        }.padding(14).card(radius: 18)
        if let id = i.id { NavigationLink { SubscriptionDetailView(id: id) } label: { content }.buttonStyle(PressScale()) } else { content }
    }
    @ScaledMetric(relativeTo: .footnote) private var tile: CGFloat = 30
    var body: some View {
        VStack(spacing: 18) {
            // “开盒”: the cat peeks out, the count lands, then the yearly total rolls up.
            ZStack {
                ForEach(0..<6) { i in
                    Image(systemName: "pawprint.fill").font(.system(size: 11)).foregroundStyle(Theme.accent.opacity(0.55))
                        .rotationEffect(.degrees(Double(i) * 60 + 90)).offset(y: -62).rotationEffect(.degrees(Double(i) * 60 + 15))
                        .scaleEffect(celebrate ? 1 : 0.2).opacity(celebrate ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.35 + Double(i) * 0.05), value: celebrate)
                }
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        CatHead().fill(LinearGradient(colors: [.white, Theme.fixed(0xE4DBFF)], startPoint: .top, endPoint: .bottom))
                            .frame(width: 84, height: 70).shadow(color: Theme.action.opacity(0.25), radius: 10, y: 4)
                        HStack(spacing: 16) { ForEach(0..<2, id: \.self) { _ in Capsule().fill(Theme.action).frame(width: 7, height: 15) } }.padding(.bottom, 16)
                    }
                    .offset(y: celebrate ? 0 : 30).opacity(celebrate ? 1 : 0).scaleEffect(celebrate ? 1 : 0.6, anchor: .bottom)
                    .animation(.spring(response: 0.55, dampingFraction: 0.62).delay(0.1), value: celebrate)
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.actionGradient).frame(width: 120, height: 44)
                        .overlay(Image(systemName: "checkmark").font(.system(size: 20, weight: .bold)).foregroundStyle(.white).symbolEffect(.bounce, value: celebrate))
                        .shadow(color: Theme.action.opacity(0.35), radius: 12, y: 4)
                }
            }.frame(height: 150).accessibilityHidden(true)
                .onAppear { celebrate = true; withAnimation(.easeOut(duration: 1.4).delay(0.6)) { rolled = NSDecimalNumber(decimal: current.annual).doubleValue } }
                .sensoryFeedback(.success, trigger: celebrate)
            VStack(spacing: 6) {
                Text(foundCount > 0 ? "这次找到 \(foundCount) 项" : "体检完成！").font(.title2.weight(.bold))
                Text("本次新增 \(result.added) 项；钱包当前共 \(current.held) 项").font(.subheadline).accessibilityIdentifier("checkupResult")
                if current.eligible > 0 {
                    VStack(spacing: 0) {
                        Text("每年约").font(.caption).foregroundStyle(Theme.secondary)
                        RollingMoney(value: rolled).foregroundStyle(Theme.text)
                        Text("月均约 \(current.monthlyDisplay) · 按记录折算").font(.caption).foregroundStyle(Theme.secondary)
                    }.padding(.top, 4)
                }
                if !progress.badges.isEmpty {
                    HStack(spacing: 6) { ForEach(progress.badges, id: \.self) { PawMedal(level: $0).frame(width: 24, height: 24) } }.padding(.top, 4)
                }
            }.multilineTextAlignment(.center)
            if let insight { insightCard(insight) }
            VStack(spacing: 0) {
                let rows = Category.allCases.compactMap { c -> (Category, CostSummary)? in
                    let cost = CostCalculator.summary(repo.records.filter { $0.category == c }, preferences: repo.preferences, today: LocalDate(date: Date()))
                    return cost.held > 0 ? (c, cost) : nil
                }
                ForEach(Array(rows.enumerated()), id: \.element.0) { index, row in
                    HStack(spacing: 12) {
                        Image(systemName: row.0.symbol).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent).frame(width: tile, height: tile).background(Theme.soft, in: RoundedRectangle(cornerRadius: tile * 0.3))
                        Text(row.0.title).font(.subheadline)
                        Text("\(row.1.held) 个").font(.caption).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text(row.1.eligible > 0 ? "\(row.1.monthlyDisplay) / 月" : row.1.mainLabel).font(.subheadline.weight(.semibold)).monospacedDigit()
                    }.padding(.vertical, 11).accessibilityElement(children: .combine)
                    if index < rows.count - 1 { Divider().padding(.leading, 42) }
                }
                ForEach(current.notices, id: \.self) { Text($0).font(.caption).foregroundStyle(Theme.warning).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6) }
            }.padding(.horizontal, 16).padding(.vertical, 6).card(radius: 20)
            PrimaryButton(title: "查看我的订阅", action: onWallet)
            if current.held > 0 {
                NavigationLink { SharePreviewView() } label: {
                    Text("分享我的结果").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, minHeight: 50).background(Theme.fill, in: Capsule())
                }.buttonStyle(PressScale()).accessibilityIdentifier("checkupShare")
            }
            DisclosureGroup("查看提交时费用快照") { MoneySummary(summary: result.summary) }.font(.footnote)
            if notifications.authorization == .notDetermined && repo.records.contains(where: { $0.reminderEnabled && $0.hasDate }) {
                Text("提醒意愿已保存。允许通知后才可接收系统提醒，通知不含金额，系统可能受专注模式影响。").font(.footnote).foregroundStyle(Theme.secondary)
                Button("允许系统通知") { Task { await notifications.requestPermission(); await notifications.reconcile(repo.records, preferences: repo.preferences) } }
            }
        }
    }
    private var current: CostSummary { CostCalculator.summary(repo.records, preferences: repo.preferences, today: LocalDate(date: Date())) }
}
struct PendingServicesView: View {
    @Environment(WalletRepository.self) private var repo
    @State private var editing: Subscription?
    @State private var error: String?
    var body: some View {
        List {
            Section { Text("这里的待确认项不额外计入钱包或费用。补充会员资料后，可手动移出待确认区。").font(.footnote).foregroundStyle(Theme.secondary) }
            ForEach(repo.checkup.pending) { pending in
                Section(pending.name) {
                    Button(repo.existing(serviceID: pending.serviceID) == nil ? "补充会员记录" : "核对已有记录") {
                        if let existing = repo.existing(serviceID: pending.serviceID) { editing = existing }
                        else { var value = Subscription(); value.serviceID = pending.serviceID; value.name = pending.name; value.categoryRaw = repo.catalog.first { $0.id == pending.serviceID }?.category ?? Category.other.rawValue; editing = value }
                    }
                    Button("已确认，移出待确认") { do { try repo.resolvePending(serviceID: pending.serviceID) } catch { self.error = error.localizedDescription } }
                }
            }
            if repo.checkup.pending.isEmpty { ContentUnavailableView("待确认项已整理完", systemImage: "checkmark.circle") }
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("待确认区")
        .sheet(item: $editing) { SubscriptionEditor(subscription: $0) }
        .alert("操作未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(error ?? "") }
    }
}
