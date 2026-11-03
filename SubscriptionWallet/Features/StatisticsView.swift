import SwiftUI

struct StatisticsView: View {
    @Environment(WalletRepository.self) private var repo
    @State private var yearly = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var tile: CGFloat = 34
    private var today: LocalDate { LocalDate(date: Date()) }
    private var total: CostSummary { CostCalculator.summary(repo.records, preferences: repo.preferences, today: today) }
    private var projection: [RenewalProjection.Month] { RenewalProjection.months(repo.records, preferences: repo.preferences, today: today) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("消费统计").font(.largeTitle.bold())
                SegmentedCapsule(options: ["月度", "年度"], selection: Binding(get: { yearly ? 1 : 0 }, set: { yearly = $0 == 1 }))
                summaryCard
                Text("分类统计").font(.title3.weight(.semibold)).padding(.top, 4)
                categoryCard
                ForEach(total.notices, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.warning) }
                if let oneOff = total.oneOffLabel { Text(oneOff).font(.footnote).foregroundStyle(Theme.secondary) }
                NavigationLink { ReminderCenterView() } label: { QuickLink(title: "查看即将续费", symbol: "calendar") }.buttonStyle(PressScale())
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 28)
        }.background(Theme.background).toolbar(.hidden, for: .navigationBar)
    }
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(yearly ? "年化折算" : "月均折算").font(.subheadline).foregroundStyle(Theme.secondary)
            Text(total.eligible > 0 ? (yearly ? total.annualDisplay : total.monthlyDisplay) : total.mainLabel)
                .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
            Text("\(total.held) 个订阅 · \(total.paid) 项自费" + (total.gifted > 0 ? " · \(total.gifted) 项赠送/联名" : "")).font(.footnote).foregroundStyle(Theme.secondary)
            if projection.contains(where: { $0.amount > 0 }) {
                Divider().padding(.vertical, 8)
                Text("未来 12 个月预计续费").font(.subheadline.weight(.semibold))
                ProjectionChart(months: projection).frame(height: 150)
                Text("按当前记录的续费日和周期推算，不是实际扣款，也不含试用和待核对项。").font(.caption2).foregroundStyle(Theme.secondary)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).card(radius: 24)
    }
    /// Categories with current members, highest annual cost first; unknown costs last.
    private var categoryCosts: [(Category, CostSummary)] {
        Category.allCases.compactMap { c -> (Category, CostSummary)? in
            let cost = CostCalculator.summary(repo.records.filter { $0.category == c }, preferences: repo.preferences, today: today)
            return cost.held > 0 ? (c, cost) : nil
        }.sorted { $0.1.annual > $1.1.annual }
    }
    private var categoryCard: some View {
        VStack(spacing: 18) {
            ForEach(categoryCosts, id: \.0) { category, cost in
                Group {
                    let share = total.annual > 0 && cost.eligible > 0 ? NSDecimalNumber(decimal: cost.annual / total.annual).doubleValue : 0
                    VStack(alignment: .leading, spacing: 8) {
                        AdaptiveRow {
                            Image(systemName: category.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                                .frame(width: tile, height: tile).background(Theme.soft, in: RoundedRectangle(cornerRadius: tile * 0.3, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.title).font(.subheadline.weight(.medium))
                                Text("\(cost.held) 个").font(.caption2).foregroundStyle(Theme.secondary)
                            }
                            if !typeSize.isAccessibilitySize { Spacer() }
                            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                                Text(cost.eligible > 0 ? (yearly ? cost.annualDisplay : cost.monthlyDisplay) : cost.mainLabel).font(.subheadline.weight(.semibold)).monospacedDigit()
                                if share > 0 { Text(share.formatted(.percent.precision(.fractionLength(0)))).font(.caption2).foregroundStyle(Theme.secondary) }
                            }
                        }
                        if share > 0 {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.fill)
                                    Capsule().fill(Theme.action).frame(width: max(6, g.size.width * share))
                                }
                            }.frame(height: 6).padding(.leading, typeSize.isAccessibilitySize ? 0 : 46).accessibilityHidden(true)
                        }
                    }.accessibilityElement(children: .combine)
                }
            }
            if total.held == 0 { Text("添加会员后，在这里查看分类与费用。").foregroundStyle(Theme.secondary) }
        }.padding(18).card(radius: 24)
    }
}

struct SegmentedCapsule: View {
    let options: [String]
    @Binding var selection: Int
    @Namespace private var pill
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, title in
                Button { withAnimation(.snappy(duration: 0.2)) { selection = index } } label: {
                    Text(title).font(.subheadline.weight(selection == index ? .semibold : .regular))
                        .foregroundStyle(selection == index ? Theme.text : Theme.secondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background { if selection == index { Capsule().fill(Theme.surface).shadow(color: .black.opacity(0.08), radius: 4, y: 1).matchedGeometryEffect(id: "pill", in: pill) } }
                        .contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }.padding(4).background(Theme.fill, in: Capsule()).sensoryFeedback(.selection, trigger: selection)
    }
}

struct ProjectionChart: View {
    let months: [RenewalProjection.Month]
    @State private var grown = false
    var body: some View {
        let values = months.map { NSDecimalNumber(decimal: $0.amount).doubleValue }
        let top = max(values.max() ?? 1, 0.01)
        let peak = values.firstIndex(of: top)
        GeometryReader { g in
            let barArea = g.size.height - 40
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(months.enumerated()), id: \.offset) { index, m in
                    VStack(spacing: 4) {
                        if index == peak && top > 0 {
                            Text(Money.display(m.amount)).font(.system(size: 9, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 2).background(Theme.text, in: RoundedRectangle(cornerRadius: 4)).fixedSize()
                        }
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(index == peak ? Theme.action : Theme.action.opacity(index == 0 ? 0.45 : 0.2))
                            .frame(height: values[index] > 0 ? max(4, barArea * values[index] / top * (grown ? 1 : 0.05)) : 2)
                            .animation(.spring(response: 0.6, dampingFraction: 0.75).delay(Double(index) * 0.03), value: grown)
                        Text("\(m.month)").font(.system(size: 10)).foregroundStyle(index == 0 ? Theme.text : Theme.secondary).frame(height: 12)
                    }.frame(maxWidth: .infinity)
                }
            }.frame(maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear { grown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("未来 12 个月预计续费：" + months.filter { $0.amount > 0 }.map { "\($0.month)月 \(Money.display($0.amount))" }.joined(separator: "，"))
    }
}

struct ProfileView: View {
    @Environment(WalletRepository.self) private var repo
    @Environment(\.showWallet) private var showWallet
    private var held: Int { repo.records.filter { !$0.isArchived }.count }
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AppLogo(size: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("订阅猫").font(.headline)
                        Text("共 \(held) 项 · 本机保存 · 无需登录").font(.footnote).foregroundStyle(Theme.secondary)
                    }
                }.padding(.vertical, 8)
            }
            Section {
                NavigationLink { ReminderCenterView() } label: { ProfileRow(title: "通知提醒", symbol: "bell") }.accessibilityIdentifier("profileReminders")
                NavigationLink { SettingsView() } label: { ProfileRow(title: "设置与偏好", symbol: "slider.horizontal.3") }
                ProfileRow(title: "外观", symbol: "sun.max", value: "跟随系统")
            }
            Section {
                NavigationLink { DataManagementView(onCleared: showWallet) } label: { ProfileRow(title: "备份与恢复", symbol: "externaldrive") }
                NavigationLink { SharePreviewView() } label: { ProfileRow(title: "分享我的订阅", symbol: "square.and.arrow.up") }.disabled(repo.records.isEmpty)
            }
            Section {
                ProfileRow(title: "关于", symbol: "info.circle", value: AppVersion.display)
            } footer: {
                VStack(spacing: 18) {
                    Text("资料保存在这台设备，不接入广告或第三方统计。删除 App 会移除本机资料，请定期导出备份。")
                    Image(systemName: "pawprint.fill").font(.title3).foregroundStyle(Theme.catAccent).frame(maxWidth: .infinity).accessibilityHidden(true)
                }
            }
        }.listSectionSpacing(.compact).environment(\.defaultMinListRowHeight, 48)
            .scrollContentBackground(.hidden).background(Theme.background).navigationTitle("我的")
    }
}
struct ProfileRow: View {
    let title: String
    let symbol: String
    var value: String? = nil
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.subheadline).foregroundStyle(Theme.accent).frame(width: 24)
            Text(title).font(.subheadline)
            Spacer()
            if let value { Text(value).font(.footnote).foregroundStyle(Theme.secondary) }
        }
    }
}
