import XCTest
import SwiftData
@testable import SubscriptionWallet

@MainActor final class MyMembershipsTests: XCTestCase {
    private func repo() throws -> WalletRepository { try WalletRepository(container: WalletRepository.container(inMemory: true)) }

    func testSeedsAreValidAndInCatalog() throws {
        let r = try repo(), seeds = MyMemberships.all()
        XCTAssertEqual(Set(seeds.compactMap(\.serviceID)).count, seeds.count)
        for s in seeds {
            XCTAssertTrue(r.catalog.contains { $0.id == s.serviceID }, "\(s.serviceID ?? "?") 不在目录里")
            XCTAssertNoThrow(try Validator.validate(s, all: seeds), s.name)
        }
    }
    func testAddsOnceAndOnlyOnce() throws {
        let r = try repo()
        XCTAssertEqual(try r.addMissing(MyMemberships.all()), MyMemberships.all().count)
        XCTAssertEqual(try r.addMissing(MyMemberships.all()), 0)
        XCTAssertEqual(r.records.count, MyMemberships.all().count)
    }
    func testExistingRecordIsNeverOverwritten() throws {
        let r = try repo()
        var mine = Subscription(); mine.serviceID = "claude"; mine.name = "我的 Claude"; mine.category = .aiCreation
        mine.amountMinor = 99_900; mine.cycle = .yearly; try r.save(mine)
        XCTAssertEqual(try r.addMissing(MyMemberships.all()), MyMemberships.all().count - 1)
        let kept = r.records.first { $0.serviceID == "claude" }
        XCTAssertEqual(kept?.name, "我的 Claude"); XCTAssertEqual(kept?.amountMinor, 99_900); XCTAssertEqual(kept?.cycle, .yearly)
    }
    func testAmountsAndUnknowns() throws {
        let r = try repo(); try r.addMissing(MyMemberships.all())
        func rec(_ id: String) -> Subscription { r.records.first { $0.serviceID == id }! }
        XCTAssertEqual(rec("artlist").amountMinor, 216_775); XCTAssertEqual(rec("artlist").cycle, .yearly)
        XCTAssertEqual(rec("artlist").nextChargeOn, "2027-07-19"); XCTAssertEqual(rec("artlist").planLabel, "Music & SFX Pro")
        XCTAssertEqual(rec("jianying").accessEndsOn, "2027-03-22")
        XCTAssertNil(rec("aigei").amountMinor, "爱给的实付金额没确认，不猜"); XCTAssertEqual(rec("aigei").accessEndsOn, "2029-05-13")
        XCTAssertEqual(rec("claude").nextChargeOn, "2026-10-28"); XCTAssertEqual(rec("claude").autoRenew, .on)
        XCTAssertEqual(rec("chatgpt").nextChargeOn, "2026-11-12"); XCTAssertEqual(rec("apple_creator_studio").nextChargeOn, "2026-11-07")
        XCTAssertEqual(rec("apple_icloud").amountMinor, 6_800); XCTAssertEqual(rec("apple_icloud").cycle, .monthly)
        XCTAssertEqual(rec("bilibili").amountMinor, 14_800); XCTAssertEqual(rec("bilibili").cycle, .yearly); XCTAssertEqual(rec("bilibili").nextChargeOn, "2027-08-22")
        XCTAssertEqual(rec("libtv").amountMinor, 399_900)
        XCTAssertNil(rec("wps").amountMinor, "没说过的金额不当零"); XCTAssertEqual(rec("wps").accessEndsOn, "2027-09-26")
        XCTAssertEqual(rec("claude").amountConfidenceRaw, "estimated"); XCTAssertEqual(rec("stash").amountConfidenceRaw, "actual")
        XCTAssertTrue(r.records.allSatisfy { $0.acquisition == .paid && $0.currency == .CNY && !$0.reminderEnabled })
    }

    func testUpgradeOnlyTouchesUntouchedFirstVersionSeeds() throws {
        let r = try repo()
        var oldArtlist = Subscription(); oldArtlist.serviceID = "artlist"; oldArtlist.name = "Artlist"; oldArtlist.category = .aiCreation
        oldArtlist.planLabel = "年付"; oldArtlist.amountMinor = 216_775; oldArtlist.cycle = .yearly; oldArtlist.notes = "原价 $299/年，按 7.25 折算。"
        var edited = Subscription(); edited.serviceID = "jianying"; edited.name = "剪映"; edited.category = .aiCreation
        edited.planLabel = "年费"; edited.amountMinor = 19_900; edited.cycle = .yearly; edited.notes = "金额凭印象，待核对。"   // 他改过金额
        try r.save(oldArtlist); try r.save(edited)
        XCTAssertEqual(try r.upgradeSeeds(), 1)
        XCTAssertEqual(r.records.first { $0.serviceID == "artlist" }?.nextChargeOn, "2027-07-19")
        XCTAssertEqual(r.records.first { $0.serviceID == "artlist" }?.id, oldArtlist.id)
        XCTAssertNil(r.records.first { $0.serviceID == "jianying" }?.accessEndsOn); XCTAssertEqual(r.records.first { $0.serviceID == "jianying" }?.amountMinor, 19_900)
        XCTAssertEqual(try r.upgradeSeeds(), 0)
    }
    func testFirstVersionClaudeGetsRenewalDate() throws {
        let r = try repo()
        var old = Subscription(); old.serviceID = "claude"; old.name = "Claude"; old.category = .aiCreation
        old.planLabel = "Pro"; old.amountMinor = 14_500; old.cycle = .monthly; old.notes = "原价 $20/月，按 7.25 折算。"
        try r.save(old)
        XCTAssertEqual(try r.upgradeSeeds(), 1)
        let u = r.records.first { $0.serviceID == "claude" }
        XCTAssertEqual(u?.nextChargeOn, "2026-10-28"); XCTAssertEqual(u?.autoRenew, .on); XCTAssertEqual(u?.id, old.id)
    }

    private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "mine-seed-test-\(UUID())")! }
    func testSeedPendingRunsOnceAndNeverReAddsDeleted() throws {
        let r = try repo(), d = freshDefaults()
        MyMemberships.seedPending(into: r, defaults: d)
        XCTAssertEqual(r.records.count, MyMemberships.all().count)
        try r.delete(r.records.first { $0.serviceID == "wps" }!)
        MyMemberships.seedPending(into: r, defaults: d)
        XCTAssertEqual(r.records.count, MyMemberships.all().count - 1, "他删掉的不能被加回来")
    }
    func testSeedPendingAddsOnlyNewlyListedAfterV1() throws {
        let r = try repo(), d = freshDefaults()
        try r.addMissing(MyMemberships.all().filter { MyMemberships.v1IDs.contains($0.serviceID ?? "") })   // 手机上第一版预置的结果
        d.set(true, forKey: MyMemberships.seedKey)
        MyMemberships.seedPending(into: r, defaults: d)
        let added = MyMemberships.all().filter { !MyMemberships.v1IDs.contains($0.serviceID ?? "") }.compactMap(\.serviceID)
        XCTAssertEqual(Set(added), ["baidu_netdisk", "apple_icloud", "bilibili"])
        XCTAssertEqual(r.records.count, MyMemberships.v1IDs.count + added.count)
        XCTAssertNotNil(r.records.first { $0.serviceID == "baidu_netdisk" }?.accessEndsOn)
    }
}
