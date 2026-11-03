import SwiftUI

/// “已找到 N 项” tray: brand icons pop in as services are found. Honest by design — it shows what
/// was found, never a completion percentage.
struct FoundTray: View {
    @Environment(FindProgress.self) private var progress
    @Environment(WalletRepository.self) private var repo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var compact = false
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("已找到").font(.caption).foregroundStyle(Theme.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(progress.items.count)").font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
                        .contentTransition(.numericText(value: Double(progress.items.count)))
                    Text("项").font(.subheadline.weight(.semibold))
                }
            }
            Spacer(minLength: 4)
            if progress.items.isEmpty {
                Text("找到的会员会出现在这里").font(.caption).foregroundStyle(Theme.secondary)
            } else {
                HStack(spacing: -10) {
                    ForEach(progress.items.suffix(compact ? 5 : 7)) { item in
                        BrandMark(style: BrandStyle.of(item.serviceID, name: name(item.serviceID), category: nil), assetID: item.serviceID, size: 34)
                            .overlay(RoundedRectangle(cornerRadius: 34 * 0.28, style: .continuous).stroke(Theme.surface, lineWidth: 2))
                            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 0.2).combined(with: .offset(y: 30)).combined(with: .opacity), removal: .opacity))
                    }
                }
                if progress.items.count > (compact ? 5 : 7) {
                    Text("+\(progress.items.count - (compact ? 5 : 7))").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                }
            }
            if !progress.badges.isEmpty {
                PawMedal(level: progress.badges.last!).frame(width: 30, height: 30)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: progress.items)
        .padding(14).card(radius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("已找到 \(progress.items.count) 项").accessibilityIdentifier("foundTray")
    }
    private func name(_ id: String) -> String { repo.catalog.first { $0.id == id }?.name ?? id }
}

/// Bronze / silver / gold / purple paw medal for 5 / 10 / 15 / 20 finds.
struct PawMedal: View {
    let level: Int
    private var colors: [Color] {
        switch level {
        case ..<10: [Theme.fixed(0xE9B98A), Theme.fixed(0xB97A45)]
        case ..<15: [Theme.fixed(0xE6E8EE), Theme.fixed(0x9AA1AE)]
        case ..<20: [Theme.fixed(0xFFE08A), Theme.fixed(0xE0A31C)]
        default: [Theme.fixed(0xB9A6FF), Theme.fixed(0x6B46E5)]
        }
    }
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(.white.opacity(0.6), lineWidth: 1.5).padding(2)
            Image(systemName: "pawprint.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
        }.shadow(color: colors[1].opacity(0.4), radius: 4, y: 2).accessibilityLabel("找到 \(level) 项徽章")
    }
}

/// One-shot toast when a milestone is crossed. Doesn't block; dismisses itself.
struct BadgeToast: ViewModifier {
    @Environment(FindProgress.self) private var progress
    @State private var shown: Int?
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let level = shown {
                HStack(spacing: 10) {
                    PawMedal(level: level).frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("解锁徽章").font(.caption2).foregroundStyle(Theme.secondary)
                        Text("已经找到 \(level) 项").font(.subheadline.weight(.semibold))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule()).shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                .transition(.move(edge: .top).combined(with: .scale(scale: 0.8)).combined(with: .opacity))
                .padding(.top, 8).accessibilityAddTraits(.isStaticText)
            }
        }
        .onChange(of: progress.newBadge) { _, level in
            guard let level else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { shown = level }
            progress.newBadge = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { withAnimation(.easeOut(duration: 0.3)) { shown = nil } }
        }
        .sensoryFeedback(.success, trigger: shown) { _, new in new != nil }
    }
}
extension View { func badgeToast() -> some View { modifier(BadgeToast()) } }

/// Money that rolls up from 0 (Animatable), e.g. the yearly total in the reveal.
struct RollingMoney: View, Animatable {
    var value: Double
    var font: Font = .system(size: 40, weight: .bold, design: .rounded)
    var animatableData: Double { get { value } set { value = newValue } }
    var body: some View {
        Text(Money.display(Decimal(Int(value.rounded())))).font(font).monospacedDigit()
    }
}

/// “+¥25 / 月” that floats up and fades, next to a newly found item.
struct MoneyBubble: View {
    let text: String
    @State private var up = false
    var body: some View {
        Text(text).font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(Theme.accent)
            .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.soft, in: Capsule())
            .offset(y: up ? -26 : 0).opacity(up ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 1.1).delay(0.25)) { up = true } }
            .accessibilityHidden(true)
    }
}
