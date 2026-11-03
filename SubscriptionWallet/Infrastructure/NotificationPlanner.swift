import Foundation

struct ReminderPlan: Identifiable {
    var id: String
    var triggerAt: Date
    var events: [MemberEvent]
}
struct PlannedReminders {
    var requests: [ReminderPlan]
    var outsideBudget: Set<UUID>
}
enum NotificationPlanner {
    static func plan(_ records: [Subscription], now: Date, changedIDs: Set<UUID> = []) -> PlannedReminders {
        let today = LocalDate(date: now), horizon = today.adding(days: 365)
        var candidates: [(Date, MemberEvent)] = []
        for s in records where s.reminderEnabled && StatusResolver.status(s, today: today).held {
            guard let first = EventResolver.event(s), first.date >= today else { continue }
            var events = [first]
            if s.acquisition == .paid, !s.isTrial, s.autoRenew == .on, s.chargeDate != nil, let months = s.cycle.months, let anchor = s.anchor {
                for i in 1...400 {
                    let d = anchor.occurrence(monthOffset: months * i)
                    if d > horizon { break }
                    if d > first.date { var event = first; event.date = d; events.append(event) }
                }
            }
            for e in events where e.date <= horizon {
                var fire = e.date.adding(days: -s.reminderLeadDays).at()
                if fire <= now {
                    // Only a deliberate save may create a catch-up request. Foreground reconciliation never replays missed reminders.
                    guard changedIDs.contains(s.id) else { continue }
                    if today.at() > now { fire = today.at() }
                    else if e.date > today { fire = today.adding(days: 1).at() }
                    else { fire = now.addingTimeInterval(60) }
                }
                candidates.append((fire, e))
            }
        }
        let grouped = Dictionary(grouping: candidates, by: { $0.0 })
        let plans = grouped.keys.sorted().map { fire in
            let c = LocalDate.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            return ReminderPlan(id: String(format: "digest-%04d%02d%02d-%02d%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!), triggerAt: fire, events: grouped[fire]!.map { $0.1 }.sorted { $0.id < $1.id })
        }
        return PlannedReminders(requests: Array(plans.prefix(60)), outsideBudget: Set(plans.dropFirst(60).flatMap { $0.events.map(\.subscriptionID) }))
    }
    static func body(_ p: ReminderPlan, showNames: Bool) -> String {
        let names = Array(Set(p.events.map(\.name))).sorted(), count = Set(p.events.map(\.subscriptionID)).count
        guard showNames else { return "你记录的 \(count) 项会员近期需要处理，打开核对。" }
        if p.events.count == 1, let e = p.events.first { return "\(e.name) \(e.dateLabel)，\(e.kind == "trial" ? "之后可能开始扣费，" : "")打开核对。" }
        return "\(names.prefix(2).joined(separator: "、"))等 \(count) 项会员近期需要处理。"
    }
}
