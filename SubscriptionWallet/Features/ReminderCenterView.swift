import SwiftUI

struct EventRow: View {
    let event: MemberEvent
    let state: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: event.kind == "trial" ? "hourglass" : "calendar").foregroundStyle(Theme.accent).frame(width: 32)
            VStack(alignment: .leading, spacing: 6) {
                Text(event.name).font(.headline).foregroundStyle(Theme.text)
                Text(event.dateLabel).font(.subheadline).foregroundStyle(Theme.secondary)
                Text(state).font(.caption).foregroundStyle(Theme.secondary)
            }; Spacer(minLength: 0)
        }.padding(.vertical, 6).accessibilityElement(children: .combine)
    }
}
struct ReminderCenterView: View {
    @Environment(\.dynamicTypeSize) private var size
    @Environment(WalletRepository.self) var repo
    @Environment(NotificationCoordinator.self) var notifications
    var today: LocalDate { LocalDate(date: Date()) }
    var events: [MemberEvent] { repo.records.filter { !$0.isArchived }.compactMap(EventResolver.event).sorted { $0.date < $1.date } }
    func group(_ e: MemberEvent) -> Int { if e.date < today { return 0 }; if e.date <= today.adding(days: 7) { return 1 }; if e.date <= today.adding(days: 30) { return 2 }; return 3 }
    var byDate: [(LocalDate, [MemberEvent])] {
        Dictionary(grouping: events.filter { $0.date >= today }, by: \.date).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
    var overdue: [MemberEvent] { events.filter { $0.date < today } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                permissionCard
                if !overdue.isEmpty {
                    group(title: "日期已过，待核对", tint: Theme.warning, items: overdue)
                }
                ForEach(byDate, id: \.0) { date, items in
                    group(title: "\(date.short)（\(date.relative(from: today))）", tint: date <= today.adding(days: 7) ? Theme.accent : Theme.secondary, items: items)
                }
                let missing = repo.records.filter { !$0.isArchived && EventResolver.event($0) == nil && !($0.cycle == .oneOff && $0.isLifetime) }
                if !missing.isEmpty {
                    Text("未设置可用日期").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary).padding(.top, 4)
                    VStack(spacing: 0) {
                        ForEach(missing) { s in
                            NavigationLink { SubscriptionDetailView(id: s.id) } label: {
                                HStack(spacing: 12) {
                                    BrandMark(s, size: 36)
                                    VStack(alignment: .leading, spacing: 2) { Text(s.name).font(.subheadline.weight(.medium)); Text("补充日期后可设置提醒").font(.caption2).foregroundStyle(Theme.secondary) }
                                    Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                                }.padding(.vertical, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 16).card(radius: 18)
                }
                if events.isEmpty && missing.isEmpty { ContentUnavailableView("还没有需要提醒的日期", systemImage: "bell", description: Text("添加会员时填写续费或到期日，再选择提醒。")) }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 28)
        }.background(Theme.background).toolbar(.visible, for: .navigationBar).navigationTitle("即将续费").navigationBarTitleDisplayMode(.large)
    }
    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: notifications.allowed ? "bell.badge" : "bell.slash").foregroundStyle(notifications.allowed ? Theme.accent : Theme.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(notifications.permissionLabel).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    if notifications.allowed { Text("已核对安排 \(notifications.scheduledCount) 条提醒").font(.caption).foregroundStyle(Theme.secondary) }
                    if notifications.allowed && !notifications.outsideBudget.isEmpty { Text("已安排较近的60条，之后打开 App 时补齐。").font(.caption).foregroundStyle(Theme.warning) }
                }
            }.accessibilityElement(children: .combine)
            HStack(spacing: 16) {
                if notifications.authorization == .notDetermined {
                    Button("开启通知") { Task { await notifications.requestPermission(); await notifications.reconcile(repo.records, preferences: repo.preferences) } }
                }
                if notifications.authorization == .denied { Button("去系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }
                Button("重新核对安排状态") { Task { await notifications.reconcile(repo.records, preferences: repo.preferences) } }
            }.font(.caption.weight(.medium))
            Text("按北京时间提醒，不代表实际扣款。系统可能受专注模式影响，不能保证送达。").font(.caption2).foregroundStyle(Theme.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).card(radius: 18)
    }
    private func group(title: String, tint: Color, items: [MemberEvent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(tint).padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(items) { event in
                    if let s = repo.records.first(where: { $0.id == event.subscriptionID }) {
                        NavigationLink { SubscriptionDetailView(id: s.id) } label: {
                            AdaptiveRow {
                                BrandMark(s, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                                    Text("\(event.title) · \(notifications.states[s.id] ?? "待核对")").font(.caption2).foregroundStyle(Theme.secondary).lineLimit(1)
                                }
                                if !size.isAccessibilitySize { Spacer(minLength: 8) }
                                Text(s.acquisition == .paid ? Money.short(s) : s.acquisition.title).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.text)
                            }.padding(.vertical, 11).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityElement(children: .combine)
                        if event.id != items.last?.id { Divider().padding(.leading, 52) }
                    }
                }
            }.padding(.horizontal, 16).card(radius: 18)
        }
    }
}
