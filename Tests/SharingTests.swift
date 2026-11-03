import XCTest
import SwiftUI
import Vision
@testable import SubscriptionWallet

final class SharingTests: XCTestCase {
    let today = LocalDate("2026-10-17")!
    func fixture() -> [Subscription] {
        var main = Subscription(); main.name = "测试主会员"; main.category = .lifeShopping; main.amountMinor = 28800; main.cycle = .yearly
        var bundled = Subscription(); bundled.name = "测试联名权益"; bundled.category = .entertainment; bundled.acquisition = .bundled; bundled.sourceSubscriptionID = main.id; bundled.sourceName = "秘密来源人"; bundled.notes = "秘密备注"; bundled.planLabel = "秘密套餐"; bundled.accessEndsOn = "2027-08-13"
        var trial = Subscription(); trial.name = "测试试用"; trial.category = .aiCreation; trial.isTrial = true; trial.nextPeriodAmountMinor = 17900; trial.cycle = .monthly
        var foreign = Subscription(); foreign.name = "测试外币"; foreign.category = .readingLearning; foreign.amountMinor = 1000; foreign.currency = .USD; foreign.cycle = .monthly; foreign.amountConfidenceRaw = "estimated"
        var unknown = Subscription(); unknown.name = "测试待确认"; unknown.acquisition = .unknown; unknown.category = .other
        var missing = Subscription(); missing.name = "测试待补"; missing.category = .storageEfficiency; missing.autoRenew = .on; missing.nextChargeOn = "2020-01-01"
        var one = Subscription(); one.name = "测试一次性"; one.cycle = .oneOff; one.amountMinor = 9900; one.isLifetime = true
        var expired = main; expired.id = UUID(); expired.name = "已到期秘密"; expired.autoRenew = .off; expired.accessEndsOn = "2020-01-01"
        var archived = main; archived.id = UUID(); archived.name = "已归档秘密"; archived.isArchived = true
        return [main, bundled, trial, foreign, unknown, missing, one, expired, archived]
    }
    func make(_ options: ShareOptions = ShareOptions(), _ records: [Subscription]? = nil, _ prefs: Preferences = Preferences()) -> ShareSnapshot? {
        ShareSnapshot.make(records: records ?? fixture(), preferences: prefs, today: today, options: options)
    }
    func testDefaultsProjectNoMoneyOrNames() throws {
        let s = try XCTUnwrap(make())
        XCTAssertNil(s.monthly); XCTAssertNil(s.annual); XCTAssertTrue(s.services.isEmpty)
        XCTAssertEqual(s.held, 7); XCTAssertEqual(s.paid, 5); XCTAssertEqual(s.gifted, 1); XCTAssertEqual(s.unknown, 1)
        XCTAssertEqual(s.categories.reduce(0) { $0 + $1.value }, 7)
        let text = String(reflecting: s)
        for secret in ["¥", "$", "179", "288", "秘密", "2027-08-13", "已到期", "已归档"] { XCTAssertFalse(text.contains(secret), secret) }
        XCTAssertTrue(s.notices.contains { $0.contains("试用") }); XCTAssertTrue(s.notices.contains { $0.contains("估算") })
        XCTAssertTrue(s.notices.contains { $0.contains("外币") }); XCTAssertTrue(s.notices.contains { $0.contains("汇率待补") })
    }
    func testToggleAmountsUsesWalletCalculatorAndCanRemoveAgain() throws {
        var p = Preferences(); p.exchangeRates["USD"] = "7"
        let records = fixture(), original = records
        let on = try XCTUnwrap(make(ShareOptions(showsAmounts: true), records, p))
        let summary = CostCalculator.summary(records, preferences: p, today: today)
        XCTAssertEqual(on.monthly, summary.mainLabel); XCTAssertEqual(on.annual, Money.format(summary.annual))
        XCTAssertEqual(summary.monthly, 94)
        XCTAssertNil(make(ShareOptions(), records, p)?.monthly); XCTAssertEqual(records, original)
    }
    func testCategoriesCanBeOmittedAndWallOnlyContainsNames() throws {
        let s = try XCTUnwrap(make(ShareOptions(showsAmounts: false, showsCategories: false, showsServices: true)))
        XCTAssertTrue(s.categories.isEmpty); XCTAssertEqual(s.services.count, 4); XCTAssertEqual(s.omittedServices, 3)
        XCTAssertTrue(s.services.allSatisfy { fixture().filter { StatusResolver.status($0, today: today).held }.map(\.name).contains($0) })
        for value in ["秘密备注", "秘密来源人", "秘密套餐", "2027-08-13", "¥", "179.00"] { XCTAssertFalse(String(reflecting: s).contains(value)) }
    }
    func testNoCurrentHoldingsProducesNoPoster() {
        XCTAssertNil(make(ShareOptions(), []))
        XCTAssertNil(make(ShareOptions(), Array(fixture().suffix(2))))
    }
    func testUnknownNeverBecomesZero() {
        var s = Subscription(); s.name = "测试未知"; s.category = .other
        XCTAssertEqual(make(ShareOptions(showsAmounts: true), [s])?.monthly, "待补充")
    }
    @MainActor func testPNGDimensionsAndPrivacyVariants() throws {
        for (name, options) in [("stage4-private-poster", ShareOptions()), ("stage4-full-poster", ShareOptions(showsAmounts: true, showsCategories: true, showsServices: true)), ("stage4-wall-no-money", ShareOptions(showsAmounts: false, showsCategories: false, showsServices: true))] {
            let data = try ShareImageRenderer.png(XCTUnwrap(make(options)))
            let request = VNRecognizeTextRequest()
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.recognitionLevel = .accurate
            try VNImageRequestHandler(data: data).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            XCTAssertTrue(text.contains("数字生活账单"), text); XCTAssertTrue(text.contains("看清每一份付费"), text)
            if !options.showsAmounts {
                for amount in ["¥", "$", "179.00", "288.00", "24.00", "99.00"] { XCTAssertFalse(text.contains(amount), text) }
            }
            for secret in ["秘密备注", "秘密来源人", "秘密套餐", "2027-08-13"] { XCTAssertFalse(text.contains(secret), text) }
            let image = try XCTUnwrap(UIImage(data: data)), cg = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(cg.width,1080); XCTAssertEqual(cg.height,1440)
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png"); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
