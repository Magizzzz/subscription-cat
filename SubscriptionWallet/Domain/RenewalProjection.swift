import Foundation

/// Forward-looking renewal estimate built only from current records:
/// next renewal date + billing cycle + amount. Not a bill, not history.
enum RenewalProjection {
    struct Month: Equatable, Identifiable {
        let year: Int
        let month: Int
        var amount: Decimal
        var count: Int
        var id: String { "\(year)-\(month)" }
    }
    static func months(_ records: [Subscription], preferences: Preferences, today: LocalDate, span: Int = 12) -> [Month] {
        var result = (0..<span).map { offset -> Month in
            let d = LocalDate(year: today.year, month: today.month, day: 1).occurrence(monthOffset: offset)
            return Month(year: d.year, month: d.month, amount: 0, count: 0)
        }
        for s in records {
            guard StatusResolver.status(s, today: today) == .active, let event = EventResolver.event(s), event.kind == "renewal",
                  let months = s.cycle.months, let annual = CostCalculator.annual(s, preferences: preferences),
                  let first = s.chargeDate, first >= today else { continue }
            let perCharge = annual * Decimal(months) / 12
            let anchor = s.anchor ?? first
            var dates = [first]
            for i in 1...(span + 1) {
                let d = anchor.occurrence(monthOffset: months * i)
                if d > first { dates.append(d) }
            }
            for d in Set(dates) {
                let index = (d.year - today.year) * 12 + d.month - today.month
                guard (0..<span).contains(index) else { continue }
                result[index].amount += perCharge
                result[index].count += 1
            }
        }
        return result
    }
}
