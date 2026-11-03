import XCTest
@testable import SubscriptionWallet

final class SimpleFeeEntryTests: XCTestCase {
    func original() -> Subscription { var s = Subscription(); s.amountMinor = 3000; s.cycle = .monthly; return s }
    func testNewEntryUsesSingleRMBAmount() throws {
        var s = original(); s.currency = .USD; s.isTrial = true; s.nextPeriodAmountMinor = 9900
        let result = try SimpleFeeEntry.resolve(s, text: "25.50", original: nil, preserveBlank: false)
        XCTAssertEqual(result.currency, .CNY); XCTAssertEqual(result.amountMinor, 2550)
        XCTAssertNil(result.nextPeriodAmountMinor); XCTAssertFalse(result.isTrial)
    }
    func testForeignBlankPreservesOriginalFee() throws {
        var s = original(); s.currency = .USD; s.isTrial = true; s.nextPeriodAmountMinor = 4000
        XCTAssertEqual(SimpleFeeEntry.displayAmount(s), "")
        let result = try SimpleFeeEntry.resolve(s, text: "", original: s, preserveBlank: false)
        XCTAssertEqual(result, s)
    }
    func testForeignReplacementRequiresExplicitConfirmation() throws {
        var s = original(); s.currency = .USD
        XCTAssertTrue(try SimpleFeeEntry.needsConfirmation(s, text: "30", original: s))
        XCTAssertThrowsError(try SimpleFeeEntry.resolve(s, text: "30", original: s, preserveBlank: false))
        let result = try SimpleFeeEntry.resolve(s, text: "30", original: s, preserveBlank: false, allowLegacyReplacement: true)
        XCTAssertEqual(result.currency, .CNY); XCTAssertEqual(result.amountMinor, 3000)
    }
    func testExistingFuturePriceRemainsWhenUntouched() throws {
        var s = original(); s.nextPeriodAmountMinor = 4000; s.isTrial = true
        let result = try SimpleFeeEntry.resolve(s, text: SimpleFeeEntry.displayAmount(s), original: s, preserveBlank: false)
        XCTAssertEqual(result, s)
    }
    func testConfirmedFutureReplacementRemovesOldSemantics() throws {
        var s = original(); s.nextPeriodAmountMinor = 4000; s.isTrial = true
        let result = try SimpleFeeEntry.resolve(s, text: "50", original: s, preserveBlank: false, allowLegacyReplacement: true)
        XCTAssertEqual(result.amountMinor, 5000); XCTAssertNil(result.nextPeriodAmountMinor); XCTAssertFalse(result.isTrial)
    }
    func testCheckupBlankPreservesAmount() throws {
        let s = original()
        XCTAssertEqual(try SimpleFeeEntry.resolve(s, text: "", original: s, preserveBlank: true).amountMinor, 3000)
    }
    func testOrdinaryEditBlankClearsAmount() throws {
        let s = original()
        let result = try SimpleFeeEntry.resolve(s, text: "", original: s, preserveBlank: false)
        XCTAssertNil(result.amountMinor); XCTAssertEqual(result.amountConfidenceRaw, "unknown")
    }
}
