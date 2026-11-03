import SwiftUI

extension CostSummary {
    /// Same meaning as `mainLabel`, without trailing ".00" for whole yuan.
    var monthlyDisplay: String { eligible > 0 ? Money.display(monthly) : mainLabel }
    var annualDisplay: String { Money.display(annual) }
}

struct WalletPass: View {
    let member: Subscription
    let today: LocalDate
    var expanded = false
    private var brand: BrandStyle { member.brand }
    private var dark: Bool { brand.darkPass }
    private var ink: Color { dark ? .white : Theme.text }
    private var secondary: Color { dark ? .white.opacity(0.72) : Theme.secondary }
    private var status: MemberStatus { StatusResolver.status(member, today: today) }
    private var paper: some ShapeStyle {
        if dark {
            return AnyShapeStyle(LinearGradient(colors: [Theme.fixed(0x2A302E), Theme.fixed(0x111413)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        let tint = Theme.fixed(brand.tint)
        return AnyShapeStyle(LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.05)], startPoint: .topTrailing, endPoint: .bottomLeading))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdaptiveRow {
                BrandMark(member, size: 34)
                    .shadow(color: .black.opacity(dark ? 0 : 0.08), radius: 3, y: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name).font(.subheadline.weight(.semibold)).foregroundStyle(ink).lineLimit(expanded ? nil : 1)
                    Text(dateLine).font(.caption2).foregroundStyle(status == .needsReview ? (dark ? Color.orange : Theme.warning) : secondary).lineLimit(expanded ? nil : 1)
                }
                if !expanded { Spacer(minLength: 8) }
                Text(Money.short(member)).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(ink).lineLimit(expanded ? nil : 1).minimumScaleFactor(expanded ? 1 : 0.7)
            }
            Spacer(minLength: expanded ? 0 : 8)
            AdaptiveRow(spacing: 6) {
                Text(member.category?.title ?? "分类待补")
                if !member.planLabel.isEmpty { Text("· \(member.planLabel)").lineLimit(1) }
                if !expanded { Spacer() }
                Text(member.acquisition.title)
            }.font(.caption).foregroundStyle(secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: expanded ? nil : 150, alignment: .topLeading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
            ZStack { shape.fill(Theme.surface); shape.fill(paper) }
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -2)
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(member.name)，\(member.acquisition.title)，\(Money.label(member))，\(EventResolver.dateLabel(member, today: today))")
    }
    /// "10月21日续费" style, honest about review/expiry states.
    private var dateLine: String {
        guard status == .active || status == .trial, let event = EventResolver.event(member) else { return EventResolver.dateLabel(member, today: today) }
        let suffix = event.kind == "trial" ? "试用结束" : event.kind == "renewal" ? "续费" : "到期"
        return "\(event.date.short)\(suffix) · \(event.date.relative(from: today))"
    }
}

struct WalletPassStack: View {
    /// Visible (and tappable) strip of each stacked pass; ~12 passes fit on one screen and a half.
    static let peek: CGFloat = 54
    let records: [Subscription]
    let today: LocalDate
    /// 长按后上下拖动卡片，松手时给出新的顺序；nil = 这一页不支持拖动排序。
    var onReorder: (([Subscription]) -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var openID: UUID?
    /// 正在拖的卡：原位置、手指拖过的距离、此刻应该落在的位置。
    @State private var dragging: UUID?
    @State private var fromIndex = 0
    @State private var targetIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var swallowTap = false

    /// 拖动过程中把被拖的卡先挪到目标位置，其余卡让位（带动画）。
    private var shown: [Subscription] {
        guard dragging != nil, records.indices.contains(fromIndex) else { return records }
        var list = records; let moved = list.remove(at: fromIndex); list.insert(moved, at: min(max(targetIndex, 0), list.count)); return list
    }
    var body: some View {
        let list = shown
        VStack(spacing: textSize.isAccessibilitySize ? 16 : 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, member in
                let lifted = dragging == member.id
                Button { if !swallowTap { openID = member.id } } label: {
                    WalletPass(member: member, today: today, expanded: textSize.isAccessibilitySize)
                        .offset(y: appeared || reduceMotion ? 0 : 40).opacity(appeared || reduceMotion ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(Double(index) * 0.035), value: appeared)
                        .frame(height: textSize.isAccessibilitySize ? nil : (index == list.count - 1 ? 150 : WalletPassStack.peek), alignment: .top)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScale())
                .scaleEffect(lifted ? 1.03 : 1).shadow(color: .black.opacity(lifted ? 0.22 : 0), radius: 14, y: 6)
                // 被拖的卡跟着手指：它在 VStack 里的位置已经换了，用偏移补回来。
                .offset(y: lifted ? dragOffset - CGFloat(targetIndex - fromIndex) * WalletPassStack.peek : 0)
                .zIndex(lifted ? 1000 : Double(index))
                .accessibilityIdentifier("walletPass-\(member.id)")
                .accessibilityAction(named: "上移一位") { move(member, by: -1) }
                .accessibilityAction(named: "下移一位") { move(member, by: 1) }
            }
        }
        .background(StackDragHost(isEnabled: onReorder != nil && !textSize.isAccessibilitySize, count: records.count, peek: WalletPassStack.peek,
                                  onBegan: beginDrag, onMoved: moveDrag, onEnded: endDrag))
        .onAppear { appeared = true }
        .navigationDestination(item: $openID) { SubscriptionDetailView(id: $0) }
    }

    private func beginDrag(_ index: Int) {
        guard onReorder != nil, records.indices.contains(index) else { return }
        swallowTap = true
        fromIndex = index; targetIndex = index; dragOffset = 0
        withAnimation(.snappy(duration: 0.2)) { dragging = records[index].id }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    private func moveDrag(_ dy: CGFloat) {
        guard dragging != nil else { return }
        dragOffset = dy
        let target = min(max(fromIndex + Int((dy / WalletPassStack.peek).rounded()), 0), records.count - 1)
        if target != targetIndex {
            withAnimation(.snappy(duration: 0.22)) { targetIndex = target }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
    private func endDrag() {
        guard dragging != nil else { swallowTap = false; return }
        let result = shown
        withAnimation(.snappy(duration: 0.2)) { dragging = nil; dragOffset = 0 }
        if result.map(\.id) != records.map(\.id) { onReorder?(result) }
        // 长按松手不算点一下：吞掉紧跟着的那次点击。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { swallowTap = false }
    }
    private func move(_ member: Subscription, by step: Int) {
        guard let onReorder, let from = records.firstIndex(where: { $0.id == member.id }), records.indices.contains(from + step) else { return }
        var list = records; list.swapAt(from, from + step); onReorder(list)
    }
}

struct WalletOverview: View {
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 40
    let summary: CostSummary
    /// Monthly equivalents of individual paid members (real records only).
    var bars: [Decimal] = []
    var title = "月均折算"
    /// Two ears on the card's top-right edge, in the card colour.
    var ears = false
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text(title).font(.subheadline).foregroundStyle(Theme.secondary)
                    Image(systemName: "info.circle").font(.caption2).foregroundStyle(Theme.secondary.opacity(0.7))
                }
                Text(summary.monthlyDisplay).font(.system(size: amountSize, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1).monospacedDigit().foregroundStyle(Theme.text)
                Text("\(summary.held) 个订阅" + (summary.eligible > 0 ? " · 年化约 \(summary.annualDisplay)" : ""))
                    .font(.footnote).foregroundStyle(Theme.secondary)
                if let notice = summary.notices.first { Text(notice).font(.caption).foregroundStyle(Theme.warning) }
            }
            Spacer(minLength: 0)
            if bars.count > 1 { MiniBars(values: bars).frame(width: 64, height: 34).accessibilityHidden(true) }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            if ears {
                HStack(spacing: 18) {
                    CatEar().fill(Theme.surface).frame(width: 30, height: 30).rotationEffect(.degrees(-14))
                    CatEar().fill(Theme.surface).frame(width: 30, height: 30).rotationEffect(.degrees(14))
                }.offset(x: -26, y: -22).accessibilityHidden(true)
            }
        }
        .card(radius: 24)
    }
}

/// Tiny bar strip; tallest bar highlighted in the accent. Purely decorative summary of real values.
struct MiniBars: View {
    let values: [Decimal]
    var body: some View {
        let nums = values.map { NSDecimalNumber(decimal: $0).doubleValue }
        let top = max(nums.max() ?? 1, 0.01)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(nums.enumerated()), id: \.offset) { _, v in
                RoundedRectangle(cornerRadius: 2.5).fill(v == top ? Theme.action : Theme.action.opacity(0.18))
                    .frame(maxWidth: .infinity).frame(height: max(5, 34 * v / top))
            }
        }
    }
}
