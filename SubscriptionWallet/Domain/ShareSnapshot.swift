import Foundation

struct ShareOptions: Equatable {
    var showsAmounts = false
    var showsCategories = true
    var showsServices = false
}

// An allow-list projection: the renderer never receives subscriptions, notes,
// dates, relationships, rates, or unselected amounts.
struct ShareSnapshot: Equatable {
    struct Count: Equatable, Identifiable {
        let id: String
        let label: String
        let value: Int
    }
    let held: Int
    let paid: Int
    let gifted: Int
    let unknown: Int
    let categories: [Count]
    let monthly: String?
    let annual: String?
    let notices: [String]
    let services: [String]
    /// Catalog ids for the same services (nil for custom), only to draw brand-colour marks.
    var serviceIDs: [String?] = []
    var omittedServices: Int { max(0, held - services.count) }

    static func make(records: [Subscription], preferences: Preferences, today: LocalDate, options: ShareOptions) -> Self? {
        let held = records.filter { StatusResolver.status($0, today: today).held }
        guard !held.isEmpty else { return nil }
        let summary = CostCalculator.summary(held, preferences: preferences, today: today)
        var notices: [String] = []
        if summary.missing > 0 { notices.append("\(summary.missing) 项金额或周期待补") }
        if summary.missingRate > 0 { notices.append("\(summary.missingRate) 项汇率待补") }
        if summary.unknownSource > 0 { notices.append("\(summary.unknownSource) 项来源待确认") }
        if summary.estimated { notices.append("含估算金额") }
        if held.contains(where: { $0.acquisition == .paid && $0.currency != .CNY }) { notices.append("含外币，按手填汇率折算") }
        if summary.trials > 0 { notices.append("试用 \(summary.trials) 项，未计入持续费用") }
        if summary.oneOffCount > 0 { notices.append("一次性 \(summary.oneOffCount) 项，未计入持续费用") }
        if summary.review > 0 { notices.append("\(summary.review) 项日期待核对") }
        let wall = options.showsServices ? Array(held.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.prefix(4)) : []
        var counts: [Count] = []
        if options.showsCategories {
            counts = Category.allCases.compactMap { category in
                let n = held.filter { $0.category == category }.count
                return n == 0 ? nil : Count(id: category.rawValue, label: category.title, value: n)
            }
            let missing = held.filter { $0.category == nil }.count
            if missing > 0 { counts.append(Count(id: "unclassified", label: "分类待补", value: missing)) }
        }
        return Self(held: summary.held, paid: summary.paid, gifted: summary.gifted, unknown: summary.unknownSource,
                    categories: counts, monthly: options.showsAmounts ? summary.mainLabel : nil,
                    annual: options.showsAmounts && summary.eligible > 0 ? Money.format(summary.annual) : nil,
                    notices: notices, services: wall.map(\.name), serviceIDs: wall.map(\.serviceID))
    }
}
