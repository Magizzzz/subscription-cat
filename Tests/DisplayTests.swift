import XCTest
@testable import SubscriptionWallet

final class DisplayTests: XCTestCase {
    let today = LocalDate(year: 2026, month: 10, day: 18)
    func paid(_ minor: Int64, _ cycle: Cycle, next: String) -> Subscription {
        var s = Subscription(); s.name = "测试"; s.category = .other; s.acquisition = .paid
        s.amountMinor = minor; s.cycle = cycle; s.autoRenew = .on; s.nextChargeOn = next; return s
    }
    func testDisplayTrimsOnlyWholeYuan() {
        XCTAssertEqual(Money.display(30), "¥30")
        XCTAssertEqual(Money.display(Decimal(string: "30.5")!), "¥30.50")
        XCTAssertEqual(Money.short(paid(14500, .monthly, next: "2026-10-21")), "¥145 / 月")
    }
    func testShortFallsBackForTrialAndUnknown() {
        var s = paid(3000, .monthly, next: "2026-10-21"); s.isTrial = true; s.nextPeriodAmountMinor = 3000
        XCTAssertEqual(Money.short(s), Money.label(s))
        s = paid(3000, .unknown, next: "2026-10-21")
        XCTAssertEqual(Money.short(s), Money.label(s))
    }
    func testRelativeDays() {
        XCTAssertEqual(LocalDate(year: 2026, month: 10, day: 21).relative(from: today), "3天后")
        XCTAssertEqual(today.relative(from: today), "今天")
        XCTAssertEqual(LocalDate(year: 2026, month: 10, day: 16).relative(from: today), "已过2天")
    }
    func testProjectionUsesRealCyclesOnly() {
        let monthly = paid(3000, .monthly, next: "2026-10-21")
        let yearly = paid(12000, .yearly, next: "2027-02-01")
        var gift = Subscription(); gift.name = "赠送"; gift.category = .other; gift.acquisition = .gifted
        var unknownAmount = paid(3000, .monthly, next: "2026-10-25"); unknownAmount.amountMinor = nil
        let months = RenewalProjection.months([monthly, yearly, gift, unknownAmount], preferences: Preferences(), today: today)
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months[0].month, 10)
        XCTAssertEqual(months[0].amount, 30)
        XCTAssertEqual(months[4].amount, 150) // Feb: monthly 30 + yearly 120
        XCTAssertEqual(months.reduce(0) { $0 + $1.amount }, 30 * 12 + 120)
    }
    func testProjectionSkipsPastDatesNeedingReview() {
        let overdue = paid(3000, .monthly, next: "2026-10-01")
        XCTAssertEqual(RenewalProjection.months([overdue], preferences: Preferences(), today: today).reduce(0) { $0 + $1.amount }, 0)
    }
    func testCatalogTiersParseAndPrimaryQueueIsListed() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "json"))
        let catalog = try JSONDecoder().decode([CatalogItem].self, from: Data(contentsOf: url))
        XCTAssertEqual(Set(catalog.map(\.id)).count, catalog.count)
        for item in catalog { for tier in item.tiers ?? [] { XCTAssertNotNil(tier.minor, "\(item.id) \(tier.amount)"); XCTAssertFalse(tier.label.isEmpty) } }
        XCTAssertEqual(Array(catalog.prefix(10).map(\.id)), CheckupEngine.primaryIDs)
    }
}
