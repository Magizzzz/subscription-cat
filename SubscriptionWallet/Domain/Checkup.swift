import Foundation

enum CheckupChoice: String, Codable, CaseIterable {
    case paid, benefit, none, unsure
    var title: String { switch self { case .paid: "自己付费"; case .benefit: "赠送或联名"; case .none: "没有"; case .unsure: "不确定" } }
    var hasMembership: Bool { self == .paid || self == .benefit }
}
struct CheckupAnswer: Codable, Equatable {
    var serviceID: String
    var choice: CheckupChoice
    var member: Subscription?
    var baseID: UUID?
    var baseUpdatedAt: Date?
}
struct CheckupSession: Codable, Equatable, Identifiable {
    enum Status: String, Codable { case draft, completed }
    var id = UUID()
    var status = Status.draft
    var primaryQueue: [String]
    var secondaryQueue: [String]?
    var answers: [CheckupAnswer] = []
    var currentIndex = 0
    var archiveServiceIDs: [String] = []
    /// Services skipped because they were already found this run; never asked in round two either.
    var excluded: [String]? = nil
    var createdAt = Date()
    var updatedAt = Date()
    var queue: [String] { primaryQueue + (secondaryQueue ?? []) }
    var currentServiceID: String? { queue.indices.contains(currentIndex) ? queue[currentIndex] : nil }
}
struct PendingService: Codable, Equatable, Identifiable {
    var serviceID: String
    var name: String
    var updatedAt = Date()
    var id: String { serviceID }
}
struct CheckupResult: Codable, Equatable, Identifiable {
    var sessionID: UUID
    var added: Int
    var updated: Int
    var restored: Int
    var archived: Int
    var currentCount: Int
    var summary: CostSummary
    var completedAt: Date
    var id: UUID { sessionID }
}
struct CheckupState: Codable, Equatable {
    var session: CheckupSession?
    var pending: [PendingService] = []
    var latest: CheckupResult?
    // Only identifiers are kept for past sessions; full result history is not stored.
    var committedSessionIDs: [UUID] = []
}
struct CheckupPlan {
    struct Change: Identifiable {
        let member: Subscription
        let kind: String
        var id: UUID { member.id }
    }
    let records: [Subscription]
    let changes: [Change]
    let pending: [PendingService]
    let result: CheckupResult
}
enum CheckupEngine {
    /// First round: the ten most widely paid memberships in mainland China (2025–26 public reports).
    static let primaryIDs = ["tencent_video", "iqiyi", "qq_music", "taobao_88vip", "netease_music", "baidu_netdisk", "bilibili", "apple_icloud", "jd_plus", "youku"]
    /// `excluding`: services already found this run (e.g. by screenshot) — skipped, and the first
    /// round is topped up with the next most common services so it still has ten cards.
    static func start(catalog: [CatalogItem], excluding: Set<String> = []) throws -> CheckupSession {
        guard primaryIDs.allSatisfy({ id in catalog.contains { $0.id == id } }), catalog.count >= 20 + excluding.count else { throw WalletError.invalid("体检目录不足，请更新 App。") }
        guard !excluding.isEmpty else { return CheckupSession(primaryQueue: primaryIDs) }
        let pool = (primaryIDs + catalog.map(\.id)).reduce(into: [String]()) { if !$0.contains($1) && !excluding.contains($1) { $0.append($1) } }
        var session = CheckupSession(primaryQueue: Array(pool.prefix(10)))
        session.excluded = Array(excluding)
        return session
    }
    static func secondary(_ session: CheckupSession, catalog: [CatalogItem]) -> [String] {
        var weights: [String: Int] = [:]
        for answer in session.answers where session.primaryQueue.contains(answer.serviceID) && answer.choice.hasMembership {
            for tag in catalog.first(where: { $0.id == answer.serviceID })?.tags ?? [] { weights[tag, default: 0] += 1 }
        }
        let skip = Set(session.excluded ?? [])
        return Array(catalog.enumerated().filter { !session.primaryQueue.contains($0.element.id) && !skip.contains($0.element.id) }.sorted { a, b in
            let sa = (a.element.tags ?? []).reduce(0) { $0 + weights[$1, default: 0] }
            let sb = (b.element.tags ?? []).reduce(0) { $0 + weights[$1, default: 0] }
            if sa != sb { return sa > sb }
            if a.offset != b.offset { return a.offset < b.offset }
            return a.element.id < b.element.id
        }.prefix(10).map { $0.element.id })
    }
    static func answering(_ input: CheckupSession, answer: CheckupAnswer, catalog: [CatalogItem]) throws -> CheckupSession {
        guard input.status == .draft, input.currentServiceID == answer.serviceID else { throw WalletError.invalid("题目已变化，请重新打开体检。") }
        var s = input
        s.answers.removeAll { $0.serviceID == answer.serviceID }; s.answers.append(answer)
        s.archiveServiceIDs.removeAll { $0 == answer.serviceID }
        s.currentIndex += 1; s.updatedAt = Date()
        if s.currentIndex == 10 && s.secondaryQueue == nil { s.secondaryQueue = secondary(s, catalog: catalog) }
        return s
    }
    static func preservingBlanks(_ input: Subscription, original: Subscription, preserveNextPeriodAmount: Bool = true) throws -> Subscription {
        guard input.acquisition == original.acquisition else { return input }
        var value = input
        guard value.currency == original.currency || ((value.isTrial || original.amountMinor == nil || value.amountMinor != nil) && (!preserveNextPeriodAmount || original.nextPeriodAmountMinor == nil || value.nextPeriodAmountMinor != nil)) else {
            throw WalletError.invalid("更改币种时，请填写新币种的金额，避免沿用原币数值。")
        }
        if !value.isTrial { value.amountMinor = value.amountMinor ?? original.amountMinor }
        if preserveNextPeriodAmount { value.nextPeriodAmountMinor = value.nextPeriodAmountMinor ?? original.nextPeriodAmountMinor }
        if value.isLifetime {
            value.nextChargeOn = nil; value.recurrenceAnchorOn = nil; value.accessEndsOn = nil; value.reminderEnabled = false
        } else {
            if !value.hasDate && original.hasDate { value.reminderEnabled = original.reminderEnabled }
            value.nextChargeOn = value.nextChargeOn ?? original.nextChargeOn
            value.accessEndsOn = value.accessEndsOn ?? original.accessEndsOn
            value.recurrenceAnchorOn = value.recurrenceAnchorOn ?? original.recurrenceAnchorOn
        }
        if value.planLabel.isEmpty { value.planLabel = original.planLabel }
        if value.notes.isEmpty { value.notes = original.notes }
        if value.sourceName.isEmpty { value.sourceName = original.sourceName }
        return value
    }
    static func plan(session: CheckupSession, records: [Subscription], pending: [PendingService], catalog: [CatalogItem], preferences: Preferences, now: Date = Date()) throws -> CheckupPlan {
        guard session.status == .draft, session.currentIndex == 20, session.queue.count == 20,
              Set(session.queue).count == 20, Set(session.answers.map(\.serviceID)) == Set(session.queue), session.answers.count == 20 else { throw WalletError.invalid("请先完成全部 20 张卡片。") }
        var next = records, changes: [CheckupPlan.Change] = [], waiting = pending
        for answer in session.answers {
            guard let item = catalog.first(where: { $0.id == answer.serviceID }) else { throw WalletError.invalid("体检服务目录已变化，请重新核对。") }
            let existing = records.first { $0.serviceID == answer.serviceID }
            waiting.removeAll { $0.serviceID == answer.serviceID }
            if answer.choice == .unsure {
                waiting.append(PendingService(serviceID: item.id, name: existing?.name ?? item.name, updatedAt: now)); continue
            }
            if answer.choice == .none {
                if var value = existing, !value.isArchived, session.archiveServiceIDs.contains(item.id) {
                    value.isArchived = true; value.updatedAt = now
                    next[next.firstIndex { $0.id == value.id }!] = value
                    changes.append(.init(member: value, kind: "归档"))
                }
                continue
            }
            guard var value = answer.member, value.serviceID == item.id,
                  answer.choice == .paid ? value.acquisition == .paid : [.bundled, .gifted].contains(value.acquisition) else { throw WalletError.invalid("体检回答与资料不一致。") }
            // A wallet edit made after answering must be re-reviewed, never silently overwritten.
            guard existing?.id == answer.baseID, existing?.updatedAt == answer.baseUpdatedAt else { throw WalletError.invalid("\(item.name) 的钱包资料已变化，请返回这张卡片重新核对。") }
            if let existing {
                value.id = existing.id; value.createdAt = existing.createdAt
                // The editor resolves an empty future-price field before saving the answer.
                // Here nil is authoritative: the user may have disabled the future price.
                value = try preservingBlanks(value, original: existing, preserveNextPeriodAmount: false)
            }
            if value.isLifetime { value.nextChargeOn = nil; value.recurrenceAnchorOn = nil; value.accessEndsOn = nil; value.reminderEnabled = false }
            if existing == nil && next.contains(where: { $0.id == value.id }) { throw WalletError.invalid("体检记录 ID 冲突，未提交。") }
            value.isArchived = false; value.updatedAt = now
            if let i = next.firstIndex(where: { $0.id == value.id }) { next[i] = value } else { next.append(value) }
            changes.append(.init(member: value, kind: existing == nil ? "新增" : existing!.isArchived ? "恢复" : "更新"))
        }
        // Changing a paid parent must preserve the child benefit, detaching only the reference.
        let changedParents = Set(records.filter { old in old.acquisition == .paid && next.contains { $0.id == old.id && $0.acquisition != .paid } }.map(\.id))
        for i in next.indices {
            if let parent = next[i].sourceSubscriptionID, changedParents.contains(parent) {
                if next[i].sourceName.isEmpty { next[i].sourceName = records.first { $0.id == parent }?.name ?? "" }
                next[i].sourceSubscriptionID = nil; next[i].updatedAt = now
                if !changes.contains(where: { $0.id == next[i].id }) { changes.append(.init(member: next[i], kind: "解除来源关联")) }
            }
        }
        for value in next { try Validator.validate(value, all: next) }
        let summary = CostCalculator.summary(next, preferences: preferences, today: LocalDate(date: now))
        let result = CheckupResult(sessionID: session.id, added: changes.filter { $0.kind == "新增" }.count, updated: changes.filter { ["更新", "解除来源关联"].contains($0.kind) }.count,
                                   restored: changes.filter { $0.kind == "恢复" }.count, archived: changes.filter { $0.kind == "归档" }.count,
                                   currentCount: summary.held, summary: summary, completedAt: now)
        return CheckupPlan(records: next, changes: changes, pending: waiting, result: result)
    }
}
