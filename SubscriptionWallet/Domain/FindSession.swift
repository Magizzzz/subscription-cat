import Foundation
import Observation

/// Lightweight state of one "找订阅" run (RD v1.2 §6): which services were found, from where, and
/// which milestone badges were reached. Kept in UserDefaults only — never in the wallet or backups,
/// and it never claims the search is complete.
@MainActor @Observable final class FindProgress {
    struct Item: Codable, Equatable, Identifiable {
        enum Source: String, Codable { case checkup }
        var serviceID: String
        var source: Source
        var monthlyMinor: Int64?
        var id: String { serviceID }
    }
    static let milestones = [5, 10, 15, 20]
    private(set) var items: [Item] = []
    private(set) var startedAt: Date?
    /// Latest milestone just crossed, for a one-shot badge toast.
    var newBadge: Int?
    private let defaults: UserDefaults
    private let key = "findProgress.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(Saved.self, from: data),
           Date().timeIntervalSince(saved.startedAt) < 24 * 3600 {
            items = saved.items; startedAt = saved.startedAt
        }
    }
    var foundIDs: Set<String> { Set(items.map(\.serviceID)) }
    var badges: [Int] { Self.milestones.filter { items.count >= $0 } }

    /// Adds newly found services; returns how many were actually new.
    @discardableResult func add(_ new: [Item]) -> Int {
        if startedAt == nil { startedAt = Date() }
        let before = items.count
        for item in new where !items.contains(where: { $0.serviceID == item.serviceID }) { items.append(item) }
        if let crossed = Self.milestones.last(where: { before < $0 && items.count >= $0 }) { newBadge = crossed }
        save()
        return items.count - before
    }
    func reset() { items = []; startedAt = nil; newBadge = nil; defaults.removeObject(forKey: key) }

    private struct Saved: Codable { var items: [Item]; var startedAt: Date }
    private func save() {
        guard let startedAt, let data = try? JSONEncoder().encode(Saved(items: items, startedAt: startedAt)) else { return }
        defaults.set(data, forKey: key)
    }
}
