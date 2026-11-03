import SwiftUI
import UIKit

/// Brand-colour monograms for catalog services. These are placeholders in each
/// service's familiar colour, not official logos. A bundled image named
/// `brand-<serviceID>` (with a recorded source/licence) takes precedence.
struct BrandStyle {
    enum Glyph { case symbol(String), text(String) }
    let background: [UInt32]
    let foreground: UInt32
    let glyph: Glyph
    /// Card paper tint; dark brands get a dark wallet pass.
    var darkPass = false
    /// Deep colour for the detail header.
    var hero: UInt32? = nil
    /// Dominant colour of the official icon when bundled, else the placeholder colour.
    var tint: UInt32 = 0xEFEAFE
    /// Header colour: explicit hero, else the tint darkened toward near-black.
    var heroColor: UInt32 {
        if let hero { return hero }
        func ch(_ shift: UInt32) -> UInt32 { UInt32(Double((tint >> shift) & 255) * 0.42) }
        return (ch(16) << 16) | (ch(8) << 8) | ch(0)
    }

    static func of(_ serviceID: String?, name: String, category: Category?) -> BrandStyle {
        var style = base(serviceID, name: name, category: category)
        style.tint = serviceID.flatMap { BrandTints.table[$0] } ?? style.background.last ?? style.tint
        return style
    }
    private static func base(_ serviceID: String?, name: String, category: Category?) -> BrandStyle {
        if let id = serviceID, let style = table[id] { return style }
        let fallback: (UInt32, UInt32) = switch category {
        case .aiCreation: (0x1E2A27, 0xFFFFFF)
        case .entertainment: (0xFFE9EC, 0xD6334A)
        case .storageEfficiency: (0xE6F3FF, 0x1677D2)
        case .readingLearning: (0xF0EAFB, 0x6B4BC4)
        case .lifeShopping: (0xFFF1E0, 0xE07A10)
        default: (0xEFEAFE, 0x6B46E5)
        }
        let initial = name.trimmingCharacters(in: .whitespaces).prefix(1).uppercased()
        return BrandStyle(background: [fallback.0], foreground: fallback.1, glyph: .text(initial.isEmpty ? "?" : initial), darkPass: category == .aiCreation)
    }

    private static func s(_ bg: UInt32, _ fg: UInt32, _ symbol: String, dark: Bool = false, hero: UInt32? = nil) -> BrandStyle {
        BrandStyle(background: [bg], foreground: fg, glyph: .symbol(symbol), darkPass: dark, hero: hero)
    }
    private static func t(_ bg: UInt32, _ fg: UInt32, _ text: String, dark: Bool = false, hero: UInt32? = nil) -> BrandStyle {
        BrandStyle(background: [bg], foreground: fg, glyph: .text(text), darkPass: dark, hero: hero)
    }
    private static let table: [String: BrandStyle] = [
        "chatgpt": s(0x101211, 0xFFFFFF, "sparkle", dark: true, hero: 0x0E4A3A),
        "claude": s(0xF4EFE6, 0xD97757, "asterisk", hero: 0x7A3B22),
        "midjourney": s(0xFFFFFF, 0x1B2B5A, "sailboat.fill", hero: 0x1B2B5A),
        "cursor": s(0x141414, 0xFFFFFF, "cursorarrow", dark: true),
        "doubao": t(0xE8F0FF, 0x2F6BFF, "豆"),
        "kimi": t(0x111111, 0xFFFFFF, "K", dark: true),
        "jianying": s(0x111111, 0xFFFFFF, "scissors", dark: true),
        "adobe": t(0xFA0F00, 0xFFFFFF, "A", hero: 0x7A0B05),
        "canva": BrandStyle(background: [0x00C4CC, 0x7D2AE8], foreground: 0xFFFFFF, glyph: .text("C"), hero: 0x3B1F7A),
        "artlist": t(0x111111, 0xFFD400, "A", dark: true),
        "stash": t(0x1F2A44, 0xFFFFFF, "S", dark: true),
        "apple_creator_studio": s(0x111111, 0xFFFFFF, "film", dark: true),
        "jimeng": t(0x111111, 0xFFFFFF, "即", dark: true),
        "libtv": t(0x111111, 0xFFFFFF, "L", dark: true),
        "meitu": t(0xFF4D88, 0xFFFFFF, "美"),
        "xingtu": t(0x111111, 0xFFFFFF, "醒", dark: true),
        "apple_icloud": BrandStyle(background: [0xFFFFFF], foreground: 0x2F9BFF, glyph: .symbol("cloud.fill"), hero: 0x15497A),
        "apple_one": t(0x111111, 0xFFFFFF, "1", dark: true),
        "apple_music": BrandStyle(background: [0xFF5E6C, 0xFA2D48], foreground: 0xFFFFFF, glyph: .symbol("music.note"), hero: 0x7A1626),
        "qq_music": BrandStyle(background: [0xFFE45C, 0xFFC300], foreground: 0x1AAD5B, glyph: .symbol("music.note"), hero: 0x6B5200),
        "netease_music": s(0xE60026, 0xFFFFFF, "music.note", hero: 0x6E0012),
        "tencent_video": s(0x1F8BFF, 0xFFFFFF, "play.fill", hero: 0x17426B),
        "iqiyi": t(0x00BE06, 0xFFFFFF, "iQ", hero: 0x0B5A10),
        "bilibili": s(0xFB7299, 0xFFFFFF, "tv", hero: 0x7A2541),
        "youku": s(0x1F9BFF, 0xFFFFFF, "play.fill"),
        "mango_tv": t(0xFF6A00, 0xFFFFFF, "M"),
        "migu_video": t(0xF25C05, 0xFFFFFF, "咪"),
        "tencent_sports": s(0x0B5FFF, 0xFFFFFF, "sportscourt.fill"),
        "game_accelerator": s(0x1E1E2A, 0x48F5A0, "gamecontroller.fill", dark: true),
        "baidu_netdisk": s(0x2468F2, 0xFFFFFF, "cloud.fill"),
        "quark": t(0x3A6FFF, 0xFFFFFF, "Q"),
        "aliyun_drive": s(0xFF6A00, 0xFFFFFF, "cloud.fill"),
        "xunlei": s(0x1A8CFF, 0xFFFFFF, "bolt.fill"),
        "drive_115": t(0x2E7CF6, 0xFFFFFF, "115"),
        "tencent_weiyun": s(0x3D8BFF, 0xFFFFFF, "cloud"),
        "wps": t(0xE8352F, 0xFFFFFF, "W"),
        "tencent_meeting": s(0x0A6CFF, 0xFFFFFF, "video.fill"),
        "taobao_88vip": t(0xFF5000, 0xFFFFFF, "88"),
        "jd_plus": t(0xE1251B, 0xFFFFFF, "JD"),
        "meituan": t(0xFFD100, 0x222222, "美"),
        "eleme": t(0x0097FF, 0xFFFFFF, "饿"),
        "sams_club": t(0x0067A0, 0xFFFFFF, "S"),
        "keep": t(0x24263A, 0xFFFFFF, "K", dark: true),
        "weread": s(0x1E8CFF, 0xFFFFFF, "book.fill"),
        "ximalaya": s(0xF4513D, 0xFFFFFF, "headphones"),
        "zhihu": t(0x1772F6, 0xFFFFFF, "知"),
        "baidu_wenku": s(0x2F6BFF, 0xFFFFFF, "doc.text.fill"),
        "dedao": t(0xFF6B00, 0xFFFFFF, "得"),
        "qq_vip": t(0x12B7F5, 0xFFFFFF, "Q"),
        "weibo": t(0xE6162D, 0xFFFFFF, "微")
    ]
}

extension Subscription {
    var brand: BrandStyle { BrandStyle.of(serviceID, name: name, category: category) }
}

struct BrandMark: View {
    let style: BrandStyle
    var assetID: String? = nil
    var size: CGFloat = 46
    init(_ member: Subscription, size: CGFloat = 46) { style = member.brand; assetID = member.serviceID; self.size = size }
    init(style: BrandStyle, assetID: String? = nil, size: CGFloat = 46) { self.style = style; self.assetID = assetID; self.size = size }
    var body: some View {
        let radius = size * 0.28
        ZStack {
            if let assetID, let image = UIImage(named: "brand-\(assetID)") {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: style.background.map(Theme.fixed), startPoint: .topLeading, endPoint: .bottomTrailing)
                switch style.glyph {
                case .symbol(let name): Image(systemName: name).font(.system(size: size * 0.46, weight: .semibold))
                case .text(let text): Text(text).font(.system(size: size * (text.count > 2 ? 0.30 : 0.42), weight: .bold, design: .rounded)).minimumScaleFactor(0.5)
                }
            }
        }
        .foregroundStyle(Theme.fixed(style.foreground))
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

struct StatusPill: View {
    let status: MemberStatus
    var body: some View {
        let (fg, bg): (Color, Color) = switch status {
        case .active: (Theme.positive, Theme.positiveSoft)
        case .trial: (Theme.accent, Theme.soft)
        case .needsReview: (Theme.warning, Theme.warningSoft)
        case .expired, .archived: (Theme.secondary, Theme.border.opacity(0.6))
        }
        Text(status == .active ? "进行中" : status.title).font(.caption2.weight(.semibold)).foregroundStyle(fg)
            .padding(.horizontal, 9).padding(.vertical, 4).background(bg, in: Capsule())
    }
}

extension Money {
    /// "¥30" for whole amounts, "¥30.50" otherwise. Display only; storage and parsing unchanged.
    static func display(_ value: Decimal, currency: Currency = .CNY) -> String {
        let full = format(value, currency: currency)
        return full.hasSuffix(".00") ? String(full.dropLast(3)) : full
    }
    /// Compact amount line for cards and rows: "¥30 / 月". Falls back to the full label
    /// for trials, next-period prices, gifts and unknown values so nothing is hidden.
    static func short(_ s: Subscription) -> String {
        guard s.acquisition == .paid, !s.isTrial, s.nextPeriodAmountMinor == nil, let minor = s.amountMinor,
              s.cycle != .unknown, s.cycle != .oneOff else { return label(s) }
        return "\(display(decimal(minor, s.currency), currency: s.currency)) / \(s.cycle.title)"
    }
}

extension LocalDate {
    func days(until other: LocalDate) -> Int {
        Self.calendar.dateComponents([.day], from: at(hour: 12), to: other.at(hour: 12)).day ?? 0
    }
    /// "今天" / "明天" / "3天后" / "已过2天"
    func relative(from today: LocalDate) -> String {
        let n = today.days(until: self)
        switch n {
        case 0: return "今天"
        case 1: return "明天"
        case 2...: return "\(n)天后"
        default: return "已过\(-n)天"
        }
    }
}

/// White rounded content card used across pages.
struct CardBackground: ViewModifier {
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        content.background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 3)
    }
}
extension View {
    func card(radius: CGFloat = 22) -> some View { modifier(CardBackground(radius: radius)) }
}

/// Underlined text tabs; the accent bar slides between items.
struct UnderlineTabs<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    @Namespace private var bar
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(items, id: \.0) { item in
                    let on = selection == item.0
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = item.0 } } label: {
                        VStack(spacing: 6) {
                            Text(item.1).font(.subheadline.weight(on ? .semibold : .regular))
                            ZStack {
                                Capsule().fill(.clear).frame(width: 18, height: 3)
                                if on { Capsule().fill(Theme.accent).frame(width: 18, height: 3).matchedGeometryEffect(id: "bar", in: bar) }
                            }
                        }.frame(minHeight: 40).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(on ? Theme.text : Theme.secondary)
                        .accessibilityAddTraits(on ? .isSelected : [])
                }
            }.padding(.horizontal, 2)
        }.sensoryFeedback(.selection, trigger: selection)
    }
}

/// Horizontal row that stacks vertically at accessibility text sizes (title above value), like Settings.
struct AdaptiveRow<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var size
    var body: some View {
        let layout = size.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .center, spacing: spacing))
        layout { content() }
    }
}

extension View {
    /// Wraps in a vertical ScrollView only when `enabled` (e.g. accessibility text sizes),
    /// so fixed, centred layouts stay untouched at normal sizes.
    @ViewBuilder func scrollableWhen(_ enabled: Bool) -> some View {
        if enabled { ScrollView(.vertical) { self }.scrollBounceBehavior(.basedOnSize) } else { self }
    }
}
