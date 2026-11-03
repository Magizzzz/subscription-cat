import SwiftUI
import UIKit

enum Theme {
    static func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static func fixed(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
    // 订阅猫 purple. Light/dark tuned separately; white on `action` stays above 5:1.
    static let onAccent = color(0xFFFFFF, 0xFFFFFF)
    static let background = color(0xF6F5FA, 0x0F0E14)
    static let surface = color(0xFFFFFF, 0x1B1924)
    static let text = color(0x1A1726, 0xF3F1F8)
    static let secondary = color(0x5F5A70, 0xA8A3B8)
    static let accent = color(0x6B46E5, 0xA68CFF)
    static let action = color(0x7150F0, 0x7C5CF6)
    static let actionDeep = color(0x5B37E0, 0x6744EA)
    static let fill = color(0xEFEDF5, 0x25232F)
    static let soft = color(0xEFEAFE, 0x2A2142)
    static let border = color(0xE6E3EE, 0x2E2B3A)
    /// Status colours keep Apple's semantics: green = active.
    static let positive = color(0x1E8E50, 0x4CC38A)
    static let positiveSoft = color(0xE5F5EC, 0x15301F)
    static let warning = color(0x8A5700, 0xF2B84B)
    static let warningSoft = color(0xFFF5DE, 0x3A2C10)
    static let destructive = color(0xB42318, 0xFF6B5E)
    /// Soft lavender used by the cat accents (ears, tail, paws).
    static let catAccent = color(0xDCD2FF, 0x3B3160)
    static var actionGradient: LinearGradient { LinearGradient(colors: [action, actionDeep], startPoint: .top, endPoint: .bottom) }
}
struct PrimaryButton: View {
    let title: String
    var symbol: String = "plus"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 54)
                .background(Theme.actionGradient, in: Capsule())
                .shadow(color: Theme.action.opacity(0.28), radius: 12, y: 6).contentShape(Capsule())
        }.buttonStyle(PressScale())
    }
}
struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.fill, in: Capsule()).contentShape(Capsule())
        }.buttonStyle(PressScale())
    }
}
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1).opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
struct ServiceIcon: View {
    let subscription: Subscription
    var body: some View {
        BrandMark(subscription, size: 46)
    }
}
struct SubscriptionCard: View {
    let subscription: Subscription
    let today: LocalDate
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 24) {
            HStack(spacing: 12) {
                ServiceIcon(subscription: subscription)
                VStack(alignment: .leading, spacing: 4) {
                    Text(subscription.name).font(.headline).foregroundStyle(Theme.text)
                    Text(subscription.category?.title ?? "分类待补").font(.caption).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
            }
            if !compact {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Money.label(subscription)).font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                    if !subscription.planLabel.isEmpty { Text(subscription.planLabel).font(.subheadline).foregroundStyle(Theme.secondary) }
                    Text(EventResolver.dateLabel(subscription, today: today)).font(.subheadline).foregroundStyle(StatusResolver.status(subscription, today: today) == .needsReview ? Theme.warning : Theme.secondary)
                }
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(subscription.name)，\(subscription.category?.title ?? "")，\(subscription.acquisition.title)，\(Money.label(subscription))，\(EventResolver.dateLabel(subscription, today: today))")
    }
}
struct MoneySummary: View {
    let summary: CostSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("月均折算").font(.subheadline); Spacer(); Image(systemName: "info.circle") }.foregroundStyle(Theme.secondary)
            Text(summary.mainLabel).font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            if summary.eligible > 0 { Text("年化折算 \(Money.format(summary.annual))").font(.subheadline).foregroundStyle(Theme.secondary) }
            Text("共 \(summary.held) 项权益 · \(summary.paid) 项自费 · \(summary.gifted) 项赠送/联名").font(.footnote).foregroundStyle(Theme.secondary)
            ForEach(summary.notices, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.warning) }
            if let label = summary.oneOffLabel { Text(label).font(.footnote).foregroundStyle(Theme.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22).background(Theme.soft, in: RoundedRectangle(cornerRadius: 24))
    }
}
struct CategoryPicker: View {
    @Binding var selected: String
    @Environment(\.dynamicTypeSize) var size
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: size.isAccessibilitySize ? 1 : 2), spacing: 8) {
            ForEach(Category.allCases) { c in
                Button { selected = c.rawValue } label: {
                    Label(c.title, systemImage: c.symbol).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selected == c.rawValue ? Theme.accent : Theme.secondary)
                        .background(selected == c.rawValue ? Theme.soft : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected == c.rawValue ? Theme.accent : Theme.border))
                }.buttonStyle(.plain).accessibilityAddTraits(selected == c.rawValue ? .isSelected : [])
            }
        }
    }
}
