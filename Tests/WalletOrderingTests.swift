import XCTest
import SwiftData
@testable import SubscriptionWallet

@MainActor final class WalletOrderingTests: XCTestCase {
    private func member(_ name: String, charge: String? = nil, updated: TimeInterval = 0) -> Subscription {
        var s = Subscription(); s.name = name; s.category = .other; s.amountMinor = 1000; s.cycle = .monthly
        s.autoRenew = .on; s.nextChargeOn = charge; s.updatedAt = Date(timeIntervalSince1970: updated); return s
    }
    func testDefaultOrderWithoutCustomOrder() {
        let soon = member("近", charge: "2030-01-05"), late = member("远", charge: "2030-03-05"), none = member("无日期")
        XCTAssertEqual(WalletOrdering.apply([none, late, soon], order: nil).map(\.name), ["近", "远", "无日期"])
        XCTAssertEqual(WalletOrdering.apply([none, late, soon], order: []).map(\.name), ["近", "远", "无日期"])
    }
    func testCustomOrderWinsAndNewMembersGoFirst() {
        let a = member("A", charge: "2030-01-05"), b = member("B", charge: "2030-02-05"), c = member("C", charge: "2030-03-05")
        XCTAssertEqual(WalletOrdering.apply([a, b, c], order: [c.id, a.id, b.id]).map(\.name), ["C", "A", "B"])
        let fresh = member("新", charge: "2030-06-05")
        XCTAssertEqual(WalletOrdering.apply([a, b, c, fresh], order: [c.id, a.id, b.id]).map(\.name), ["新", "C", "A", "B"])
    }
    func testStaleAndDuplicateIDsAreHarmless() {
        let a = member("A"), b = member("B")
        XCTAssertEqual(WalletOrdering.apply([a, b], order: [UUID(), b.id, b.id, a.id]).map(\.name), ["B", "A"])
    }
    func testOrderPersistsAndSurvivesBackup() throws {
        let container = try WalletRepository.container(inMemory: true), repo = try WalletRepository(container: container)
        var a = member("A"), b = member("B"); a.serviceID = nil; b.serviceID = nil
        try repo.save(a); try repo.save(b)
        try repo.saveWalletOrder([b.id, a.id])
        XCTAssertEqual(try WalletRepository(container: container).preferences.walletOrder, [b.id, a.id])
        let data = try BackupCodec.encode(records: repo.records, preferences: repo.preferences)
        XCTAssertEqual(try BackupCodec.decode(data).envelope.preferences.walletOrder, [b.id, a.id])
    }
}
