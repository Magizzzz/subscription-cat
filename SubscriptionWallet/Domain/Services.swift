import Foundation

enum Money {
    static func parse(_ input: String, currency: Currency) throws -> Int64? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        let pattern = currency == .JPY ? "^[0-9]+$" : "^[0-9]+(?:\\.[0-9]{1,2})?$"
        guard s.range(of: pattern, options: .regularExpression) != nil,
              let n = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")), n > 0, n <= Decimal(string: "999999.99")! else {
            throw WalletError.invalid(currency == .JPY ? "日元金额须为正整数，且不超过 999,999。" : "金额须大于 0、不超过 999,999.99，最多两位小数。")
        }
        return NSDecimalNumber(decimal: n * currency.divisor).int64Value
    }
    static func rate(_ s: String) throws -> Decimal? {
        if s.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        guard s.range(of: "^[0-9]+(?:\\.[0-9]{1,4})?$", options: .regularExpression) != nil,
              let n = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")), n > 0, n <= 100000 else { throw WalletError.invalid("汇率须大于 0、不超过 100,000，最多四位小数。") }
        return n
    }
    static func decimal(_ minor: Int64, _ currency: Currency) -> Decimal { Decimal(minor) / currency.divisor }
    static func input(_ minor: Int64?, _ currency: Currency) -> String { minor.map { NSDecimalNumber(decimal: decimal($0, currency)).stringValue } ?? "" }
    static func format(_ value: Decimal, currency: Currency = .CNY) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.minimumFractionDigits = currency == .JPY ? 0 : 2; f.maximumFractionDigits = currency == .JPY ? 0 : 2; f.roundingMode = .halfUp; f.locale = Locale(identifier: "zh_CN")
        return currency.symbol + (f.string(from: NSDecimalNumber(decimal: value)) ?? "—")
    }
    static func label(_ s: Subscription) -> String {
        switch s.acquisition {
        case .bundled: return s.sourceName.isEmpty ? "联名权益 · 来源待补" : "来自 \(s.sourceName)"
        case .gifted: return "他人赠送"
        case .unknown: return "来源待确认"
        case .paid:
            let suffix = s.cycle == .unknown ? " · 周期待补" : (s.cycle == .oneOff ? " · 一次性" : "/\(s.cycle.title)")
            let next = s.nextPeriodAmountMinor.map { format(decimal($0, s.currency), currency: s.currency) + suffix }
            if s.isTrial { return "试用中 · 之后 \(next ?? "金额待补")" }
            let current = s.amountMinor.map { format(decimal($0, s.currency), currency: s.currency) } ?? "金额待补"
            return next.map { "本期 \(current) · 之后 \($0)" } ?? current + suffix
        }
    }
}

enum Validator {
    static func validate(_ s: Subscription, all: [Subscription]) throws {
        guard !s.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, s.name.count <= 40 else { throw WalletError.invalid("名称须为 1–40 字。") }
        guard s.category != nil else { throw WalletError.invalid("请选择一个分类。") }
        guard s.planLabel.count <= 60, s.notes.count <= 500 else { throw WalletError.invalid("套餐备注最多 60 字，备注最多 500 字。") }
        for raw in [s.nextChargeOn, s.accessEndsOn, s.recurrenceAnchorOn] { if let raw, LocalDate(raw) == nil { throw WalletError.invalid("日期无效，请重新选择。") } }
        for n in [s.amountMinor, s.nextPeriodAmountMinor].compactMap({ $0 }) {
            guard n > 0, Decimal(n) / s.currency.divisor <= Decimal(string: "999999.99")! else { throw WalletError.invalid("金额超出允许范围。") }
        }
        if s.acquisition == .paid, s.cycle == .oneOff, !s.isLifetime, s.endDate == nil { throw WalletError.invalid("一次性付费请选择买断/永久，或填写到期日。") }
        if s.isTrial && s.cycle == .oneOff { throw WalletError.invalid("一次性付费不适用试用，请选择持续周期或关闭试用。") }
        if let id = s.sourceSubscriptionID {
            guard s.acquisition == .bundled, id != s.id, let parent = all.first(where: { $0.id == id }), parent.acquisition == .paid else { throw WalletError.invalid("联名来源必须是另一项自费会员，只支持一层关联。") }
        }
        if s.acquisition != .paid && (s.amountMinor != nil || s.nextPeriodAmountMinor != nil || s.isTrial || s.autoRenew != .unknown || s.nextChargeOn != nil) { throw WalletError.invalid("非自费权益不能保留费用或续费设置。") }
        guard [0, 1, 3, 7].contains(s.reminderLeadDays) else { throw WalletError.invalid("提前天数无效。") }
    }
}

struct MemberEvent: Identifiable, Equatable {
    var subscriptionID: UUID
    var name: String
    var date: LocalDate
    var kind: String
    var id: String { "\(subscriptionID)-\(date)-\(kind)" }
    var title: String { kind == "trial" ? "试用结束" : kind == "renewal" ? "预计续费" : "权益到期" }
    var dateLabel: String { "\(date.short)\(kind == "trial" ? "试用结束" : kind == "renewal" ? "预计续费" : "到期")" }
}
enum EventResolver {
    static func event(_ s: Subscription) -> MemberEvent? {
        guard !s.isArchived, !(s.cycle == .oneOff && s.isLifetime) else { return nil }
        func make(_ d: LocalDate?, _ kind: String) -> MemberEvent? { d.map { MemberEvent(subscriptionID: s.id, name: s.name, date: $0, kind: kind) } }
        if s.acquisition != .paid { return make(s.endDate, "expiry") }
        if s.isTrial { return make(s.chargeDate, "trial") }
        if s.cycle == .oneOff { return make(s.endDate, "expiry") }
        if s.autoRenew == .on { return make(s.chargeDate ?? s.endDate, "renewal") }
        if s.autoRenew == .off { return make(s.endDate, "expiry") }
        if let charge = s.chargeDate, let end = s.endDate {
            if s.preferredEventRaw == "expiry" { return make(end, "expiry") }
            if s.preferredEventRaw == "renewal" { return make(charge, "renewal") }
            return charge <= end ? make(charge, "renewal") : make(end, "expiry")
        }
        return s.chargeDate != nil ? make(s.chargeDate, "renewal") : make(s.endDate, "expiry")
    }
    static func dateLabel(_ s: Subscription, today: LocalDate) -> String {
        let status = StatusResolver.status(s, today: today)
        if status == .archived || status == .expired { return status.title }
        if status == .needsReview { return s.isTrial ? "试用已结束，待核对" : "日期待核对" }
        if s.cycle == .oneOff && s.isLifetime { return "买断 / 永久" }
        return event(s)?.dateLabel ?? "日期待补"
    }
    static func suggestedNext(_ s: Subscription, today: LocalDate) -> LocalDate? {
        guard let anchor = s.anchor, let months = s.cycle.months else { return nil }
        for i in 1...2400 { let d = anchor.occurrence(monthOffset: months * i); if d > today && d > (s.chargeDate ?? anchor) { return d } }
        return nil
    }
}
enum StatusResolver {
    static func status(_ s: Subscription, today: LocalDate) -> MemberStatus {
        if s.isArchived { return .archived }
        if s.cycle == .oneOff && s.isLifetime { return .active }
        if let end = s.endDate, end < today {
            if [.bundled, .gifted].contains(s.acquisition) || (s.acquisition == .paid && (s.autoRenew == .off || s.cycle == .oneOff)) { return .expired }
        }
        if s.isTrial, let date = s.chargeDate, date < today { return .needsReview }
        if let event = EventResolver.event(s), event.date < today { return .needsReview }
        return s.isTrial ? .trial : .active
    }
}

struct CostSummary: Codable, Equatable {
    var held = 0, paid = 0, gifted = 0, unknownSource = 0, trials = 0, missing = 0, missingRate = 0, review = 0, oneOffCount = 0, eligible = 0
    var knownTrialCount = 0, knownOneOffCount = 0
    var annual: Decimal = 0
    var trialAnnual: Decimal = 0
    var oneOff: Decimal = 0
    var estimated = false, foreign = false
    var monthly: Decimal { annual / 12 }
    var mainLabel: String {
        if held == 0 { return "尚未记录" }
        if eligible > 0 { return Money.format(monthly) }
        if missing > 0 || missingRate > 0 { return "待补充" }
        if unknownSource > 0 { return "费用待确认" }
        if oneOffCount > 0 && trials == 0 { return "持续费用未折算" }
        return Money.format(0)
    }
    var oneOffLabel: String? {
        guard oneOffCount > 0 else { return nil }
        return knownOneOffCount > 0 ? "\(oneOffCount) 项一次性费用，已知 \(Money.format(oneOff))" : "\(oneOffCount) 项一次性费用，金额/汇率待补"
    }
    var notices: [String] {
        var result: [String] = []
        if missing > 0 { result.append("\(missing) 项自费金额/周期待补") }
        if missingRate > 0 { result.append("\(missingRate) 项需要设置汇率") }
        if unknownSource > 0 { result.append("\(unknownSource) 项来源待确认") }
        if estimated { result.append("含估算金额") }
        if foreign { result.append("含汇率换算") }
        if trials > 0 { result.append(knownTrialCount > 0 ? "试用中 \(trials) 项，已知转正后月均约 +\(Money.format(trialAnnual / 12))" : "试用中 \(trials) 项，转正费用待补") }
        return result
    }
}
enum CostCalculator {
    static func annual(_ s: Subscription, preferences: Preferences, includeTrial: Bool = false) -> Decimal? {
        guard s.acquisition == .paid, !s.isTrial || includeTrial, let months = s.cycle.months,
              let n = s.nextPeriodAmountMinor ?? s.amountMinor, let rate = exchange(s.currency, preferences) else { return nil }
        return Money.decimal(n, s.currency) * rate * Decimal(12 / months)
    }
    static func exchange(_ c: Currency, _ p: Preferences) -> Decimal? { c == .CNY ? 1 : p.exchangeRates[c.rawValue].flatMap { try? Money.rate($0) } }
    static func summary(_ records: [Subscription], preferences: Preferences, today: LocalDate) -> CostSummary {
        var r = CostSummary()
        for s in records {
            let status = StatusResolver.status(s, today: today)
            guard status.held else { continue }
            r.held += 1
            if status == .needsReview { r.review += 1 }
            switch s.acquisition {
            case .unknown: r.unknownSource += 1
            case .bundled, .gifted: r.gifted += 1
            case .paid:
                r.paid += 1
                if s.amountMinor != nil || s.nextPeriodAmountMinor != nil {
                    r.estimated = r.estimated || s.amountConfidenceRaw == "estimated"
                    r.foreign = r.foreign || (s.currency != .CNY && exchange(s.currency, preferences) != nil)
                }
                if s.isTrial {
                    r.trials += 1
                    if let a = annual(s, preferences: preferences, includeTrial: true) { r.trialAnnual += a; r.knownTrialCount += 1 }
                    if s.nextPeriodAmountMinor == nil || s.cycle.months == nil { r.missing += 1 }
                    else if exchange(s.currency, preferences) == nil { r.missingRate += 1 }
                    continue
                }
                if s.cycle == .oneOff {
                    r.oneOffCount += 1
                    if let n = s.amountMinor, let rate = exchange(s.currency, preferences) { r.oneOff += Money.decimal(n, s.currency) * rate; r.knownOneOffCount += 1 }
                    else if s.amountMinor == nil { r.missing += 1 } else { r.missingRate += 1 }
                    continue
                }
                guard let _ = s.nextPeriodAmountMinor ?? s.amountMinor, s.cycle.months != nil else { r.missing += 1; continue }
                guard let a = annual(s, preferences: preferences) else { r.missingRate += 1; continue }
                r.annual += a; r.eligible += 1
                r.estimated = r.estimated || s.amountConfidenceRaw == "estimated"
                r.foreign = r.foreign || s.currency != .CNY
            }
        }
        return r
    }
}
