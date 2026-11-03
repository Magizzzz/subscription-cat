import Foundation

enum Category: String, CaseIterable, Codable, Identifiable {
    case entertainment, aiCreation, storageEfficiency, readingLearning, lifeShopping, other
    var id: String { rawValue }
    var title: String { switch self { case .entertainment: "影音娱乐"; case .aiCreation: "AI与创作"; case .storageEfficiency: "网盘与效率"; case .readingLearning: "阅读与学习"; case .lifeShopping: "生活与购物"; case .other: "其他" } }
    var shortTitle: String { switch self { case .entertainment: "影音娱乐"; case .aiCreation: "AI 创作"; case .storageEfficiency: "网盘效率"; case .readingLearning: "阅读"; case .lifeShopping: "生活"; case .other: "其他" } }
    var symbol: String { switch self { case .entertainment: "play.rectangle"; case .aiCreation: "sparkles"; case .storageEfficiency: "externaldrive"; case .readingLearning: "book"; case .lifeShopping: "bag"; case .other: "square.grid.2x2" } }
}
enum Acquisition: String, CaseIterable, Codable, Identifiable {
    case paid, bundled, gifted, unknown
    var id: String { rawValue }
    var title: String { switch self { case .paid: "自费"; case .bundled: "联名"; case .gifted: "他人赠送"; case .unknown: "来源不明" } }
}
enum Cycle: String, CaseIterable, Codable, Identifiable {
    case monthly, quarterly, semiannual, yearly, oneOff, unknown
    var id: String { rawValue }
    var title: String { switch self { case .monthly: "月"; case .quarterly: "季"; case .semiannual: "半年"; case .yearly: "年"; case .oneOff: "一次性"; case .unknown: "记不清" } }
    var months: Int? { switch self { case .monthly: 1; case .quarterly: 3; case .semiannual: 6; case .yearly: 12; default: nil } }
}
enum AutoRenew: String, CaseIterable, Codable, Identifiable {
    case on, off, unknown
    var id: String { rawValue }
    var title: String { switch self { case .on: "开启"; case .off: "关闭"; case .unknown: "不确定" } }
}
enum Currency: String, CaseIterable, Codable, Identifiable {
    case CNY, USD, EUR, GBP, HKD, JPY
    var id: String { rawValue }
    var divisor: Decimal { self == .JPY ? 1 : 100 }
    var symbol: String { switch self { case .CNY: "¥"; case .USD: "$"; case .EUR: "€"; case .GBP: "£"; case .HKD: "HK$"; case .JPY: "JP¥" } }
}
enum MemberStatus: String, CaseIterable, Identifiable {
    case active, trial, needsReview, expired, archived
    var id: String { rawValue }
    var title: String { switch self { case .active: "当前持有"; case .trial: "试用中"; case .needsReview: "日期待核对"; case .expired: "已到期"; case .archived: "已归档" } }
    var held: Bool { self != .expired && self != .archived }
}

struct LocalDate: Codable, Hashable, Comparable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return c }
    init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }
    init?(_ raw: String) {
        let p = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard p.count == 3, p[0].count == 4, p[1].count == 2, p[2].count == 2,
              let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]), (1900...2200).contains(y) else { return nil }
        self.init(year: y, month: m, day: d)
        guard let date = Self.calendar.date(from: DateComponents(year: y, month: m, day: d)), Self(date: date) == self else { return nil }
    }
    init(date: Date) { let c = Self.calendar.dateComponents([.year, .month, .day], from: date); year = c.year!; month = c.month!; day = c.day! }
    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var short: String { "\(month)月\(day)日" }
    func at(hour: Int = 9) -> Date { Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))! }
    func adding(days: Int) -> LocalDate { LocalDate(date: Self.calendar.date(byAdding: .day, value: days, to: at())!) }
    // Always calculate from the original anchor, never from a clamped previous date.
    func occurrence(monthOffset: Int) -> LocalDate {
        let first = Self.calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let target = Self.calendar.date(byAdding: .month, value: monthOffset, to: first)!
        let parts = Self.calendar.dateComponents([.year, .month], from: target)
        let days = Self.calendar.range(of: .day, in: .month, for: target)!.count
        return LocalDate(year: parts.year!, month: parts.month!, day: min(day, days))
    }
    static func < (a: Self, b: Self) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }
}

struct Subscription: Codable, Identifiable, Equatable {
    var id = UUID()
    var serviceID: String?
    var name = ""
    var planLabel = ""
    var categoryRaw = ""
    var acquisitionRaw = Acquisition.paid.rawValue
    var amountMinor: Int64?
    var nextPeriodAmountMinor: Int64?
    var currencyCode = Currency.CNY.rawValue
    var amountConfidenceRaw = "actual"
    var billingCycleRaw = Cycle.unknown.rawValue
    var isTrial = false
    var isLifetime = false
    var autoRenewRaw = AutoRenew.unknown.rawValue
    var nextChargeOn: String?
    var recurrenceAnchorOn: String?
    var accessEndsOn: String?
    var sourceSubscriptionID: UUID?
    var sourceName = ""
    var reminderEnabled = false
    var reminderLeadDays = 3
    var preferredEventRaw = "earliest"
    var notes = ""
    var isArchived = false
    var createdAt = Date()
    var updatedAt = Date()
    var category: Category? { get { Category(rawValue: categoryRaw) } set { categoryRaw = newValue?.rawValue ?? "" } }
    var acquisition: Acquisition { get { Acquisition(rawValue: acquisitionRaw) ?? .unknown } set { acquisitionRaw = newValue.rawValue } }
    var cycle: Cycle { get { Cycle(rawValue: billingCycleRaw) ?? .unknown } set { billingCycleRaw = newValue.rawValue } }
    var currency: Currency { get { Currency(rawValue: currencyCode) ?? .CNY } set { currencyCode = newValue.rawValue } }
    var autoRenew: AutoRenew { get { AutoRenew(rawValue: autoRenewRaw) ?? .unknown } set { autoRenewRaw = newValue.rawValue } }
    var chargeDate: LocalDate? { nextChargeOn.flatMap(LocalDate.init) }
    var endDate: LocalDate? { accessEndsOn.flatMap(LocalDate.init) }
    var anchor: LocalDate? { recurrenceAnchorOn.flatMap(LocalDate.init) ?? chargeDate }
    var hasDate: Bool { EventResolver.event(self) != nil }
}
struct Preferences: Codable, Equatable {
    var businessTimeZone = "Asia/Shanghai"
    var defaultLeadDays = 3
    var notificationShowsServiceName = true
    var exchangeRates: [String: String] = [:]
    var rateUpdatedAt: [String: Date] = [:]
    var schemaVersion = 1
    var lastBackupExportedAt: Date?
    /// 首页叠卡的自定义顺序（用户拖动排序后保存）。nil = 按“最近事件”默认顺序。
    var walletOrder: [UUID]?
}
struct CatalogItem: Codable, Identifiable {
    let id: String
    let name: String
    let category: String
    let aliases: [String]
    var tags: [String]? = nil
    /// Common monthly price points (RMB). Reference only, not official quotes.
    var tiers: [Tier]? = nil
    struct Tier: Codable, Equatable {
        let amount: String
        let label: String
        var minor: Int64? { try? Money.parse(amount, currency: .CNY) }
    }
    func matches(_ term: String) -> Bool { ([name] + aliases).contains { $0.localizedCaseInsensitiveContains(term) } }
}

enum WalletError: LocalizedError {
    case invalid(String), duplicate(UUID), storage(String)
    var errorDescription: String? { switch self { case .invalid(let s), .storage(let s): s; case .duplicate: "这项服务已在钱包中，请打开已有记录。" } }
}
