import Foundation

enum WalletOrdering {
    /// 首页叠卡的顺序：用户拖过就按他的；没出现在顺序里的（拖完之后新加的）排最前，彼此仍按“最近事件”。
    static func apply(_ records: [Subscription], order: [UUID]?) -> [Subscription] {
        let base = records.sorted(by: memberOrder)
        guard let order, !order.isEmpty else { return base }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return base.filter { rank[$0.id] == nil } + base.filter { rank[$0.id] != nil }.sorted { rank[$0.id]! < rank[$1.id]! }
    }
}
