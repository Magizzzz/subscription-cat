import XCTest
@testable import SubscriptionWallet

final class DomainTests: XCTestCase {
    let today = LocalDate("2026-10-17")!
    func paid(_ name: String = "测试", _ amount: Int64? = nil, _ cycle: Cycle = .monthly) -> Subscription {
        var s = Subscription(); s.name = name; s.category = .entertainment; s.amountMinor = amount; s.cycle = cycle; return s
    }
    func sum(_ values: [Subscription], _ p: Preferences = Preferences()) -> CostSummary { CostCalculator.summary(values, preferences: p, today: today) }
    func testM01AcceptanceDataset() {
        var main = paid("88VIP", 28800, .yearly); main.category = .lifeShopping; main.autoRenew = .off; main.accessEndsOn = "2027-01-01"
        var music = paid("网易云音乐"); music.acquisition = .bundled; music.sourceSubscriptionID = main.id; music.sourceName = main.name; music.accessEndsOn = "2027-01-01"
        var video = music; video.id = UUID(); video.name = "优酷"
        var disk = paid("百度网盘", 12000, .yearly); disk.category = .storageEfficiency; disk.autoRenew = .on; disk.nextChargeOn = "2026-11-01"
        let qq = paid("QQ音乐")
        var wps = paid("WPS"); wps.category = .storageEfficiency; wps.acquisition = .unknown
        var tool = paid("临时工具", 9900, .oneOff); tool.isLifetime = true; tool.category = .aiCreation
        var old = paid("旧视频会员", 3000); old.autoRenew = .off; old.accessEndsOn = "2026-10-01"
        let all = [main,music,video,disk,qq,wps,tool,old], r = sum(all)
        XCTAssertEqual(r.held,7); XCTAssertEqual(r.paid,4); XCTAssertEqual(r.gifted,2); XCTAssertEqual(r.unknownSource,1)
        XCTAssertEqual(r.monthly,34); XCTAssertEqual(r.annual,408); XCTAssertEqual(r.missing,1); XCTAssertEqual(r.oneOffCount,1); XCTAssertEqual(r.oneOff,99)
        XCTAssertEqual(sum(all.filter { $0.category == .entertainment }).held,3)
        XCTAssertEqual(sum(all.filter { $0.category == .storageEfficiency }).monthly,10)
    }
    func testM02CycleNormalization() { let r = sum([paid("1",3000,.monthly),paid("2",9000,.quarterly),paid("3",18000,.semiannual),paid("4",36000,.yearly)]); XCTAssertEqual(r.monthly,120); XCTAssertEqual(r.annual,1440) }
    func testM03RoundOnlyAfterAnnualSum() { let r = sum([paid("1",100,.quarterly),paid("2",100,.quarterly),paid("3",100,.quarterly)]); XCTAssertEqual(r.monthly,1); XCTAssertEqual(Money.format(r.monthly),"¥1.00") }
    func testM04UnknownCycle() { let r = sum([paid("x",100,.unknown)]); XCTAssertEqual(r.missing,1); XCTAssertEqual(r.mainLabel,"待补充") }
    func testM05UnknownNotZero() { XCTAssertEqual(sum([paid()]).mainLabel,"待补充") }
    func testM06GiftIsKnownZero() { var s = paid(); s.acquisition = .gifted; XCTAssertEqual(sum([s]).mainLabel,"¥0.00") }
    func testM07UnknownSourceNotFree() { var s = paid(); s.acquisition = .unknown; XCTAssertEqual(sum([s]).mainLabel,"费用待确认") }
    func testM08Estimated() { var s = paid("x",100); s.amountConfidenceRaw = "estimated"; XCTAssertTrue(sum([s]).estimated) }
    func testM09RejectInvalidAmounts() { for text in ["-1","0","1.001","1000000","1e3","abc","NaN"] { XCTAssertThrowsError(try Money.parse(text,currency:.CNY)) }; XCTAssertThrowsError(try Money.parse("1.1",currency:.JPY)); XCTAssertNil(try Money.parse("",currency:.CNY)); XCTAssertEqual(try Money.parse("9.99",currency:.CNY),999) }
    func testM10BundledNotCharged() { var s = paid("x",3000); s.acquisition = .bundled; XCTAssertEqual(sum([s]).annual,0) }
    func testM11FX() { var s = paid("USD",2000); s.currency = .USD; var p = Preferences(); p.exchangeRates["USD"]="7.20"; XCTAssertEqual(sum([s],p).monthly,144); XCTAssertTrue(sum([s],p).foreign) }
    func testM12MissingFX() { var s = paid("USD",2000); s.currency = .USD; XCTAssertEqual(sum([s]).missingRate,1); XCTAssertEqual(sum([s]).mainLabel,"待补充") }
    func testM13PromoUsesNextAmount() { var s = paid("优惠",600); s.nextPeriodAmountMinor=2500; XCTAssertEqual(sum([s]).monthly,25) }
    func testM14TrialSeparate() { var s = paid(); s.isTrial=true; s.nextPeriodAmountMinor=3000; let r=sum([s]); XCTAssertEqual(r.annual,0); XCTAssertEqual(r.trialAnnual/12,30); XCTAssertEqual(r.trials,1) }
    func testOneOffNeedsExpiryOrLifetime() { var s=paid("x",9900,.oneOff); XCTAssertThrowsError(try Validator.validate(s,all:[])); s.isLifetime=true; XCTAssertNoThrow(try Validator.validate(s,all:[])) }
    func testCategoryRequired() { var s=paid(); s.category=nil; XCTAssertThrowsError(try Validator.validate(s,all:[])) }
    func testBundledConstraints() { var parent=paid(); var child=paid(); child.acquisition = .bundled; child.sourceSubscriptionID=parent.id; XCTAssertNoThrow(try Validator.validate(child,all:[parent])); parent.acquisition = .bundled; XCTAssertThrowsError(try Validator.validate(child,all:[parent])); child.sourceSubscriptionID=child.id; XCTAssertThrowsError(try Validator.validate(child,all:[])) }
    func testInvalidDates() { for text in ["2026-02-29","2026-13-01","2026-01-00","2026-1-01","2026-10-17junk"] { XCTAssertNil(LocalDate(text)) }; XCTAssertNotNil(LocalDate("2028-02-29")) }
    func testN01MonthEndAnchor() { let d=LocalDate("2027-01-31")!; XCTAssertEqual(d.occurrence(monthOffset:1).description,"2027-02-28"); XCTAssertEqual(d.occurrence(monthOffset:2).description,"2027-03-31"); XCTAssertEqual(d.occurrence(monthOffset:3).description,"2027-04-30") }
    func testN02LeapAnchor() { let d=LocalDate("2028-02-29")!; XCTAssertEqual(d.occurrence(monthOffset:12).description,"2029-02-28"); XCTAssertEqual(d.occurrence(monthOffset:48).description,"2032-02-29") }
    func testN03ExpiryTodayInclusive() { var s=paid(); s.autoRenew = .off; s.accessEndsOn=today.description; XCTAssertEqual(StatusResolver.status(s,today:today),.active); XCTAssertEqual(StatusResolver.status(s,today:today.adding(days:1)),.expired) }
    func testN04PastRenewalNotPayment() { var s=paid("x",100); s.autoRenew = .on; s.nextChargeOn="2026-10-16"; XCTAssertEqual(StatusResolver.status(s,today:today),.needsReview); XCTAssertEqual(sum([s]).held,1); XCTAssertEqual(sum([s]).monthly,1) }
    func testN10BudgetAfterMerge() { let now=today.at(hour:10); let records=(1...70).map { n in var s=paid("\(n)"); s.autoRenew = .unknown; s.nextChargeOn=today.adding(days:n+3).description; s.reminderEnabled=true; return s }; let plan=NotificationPlanner.plan(records,now:now); XCTAssertEqual(plan.requests.count,60); XCTAssertEqual(plan.outsideBudget.count,10) }
    func testN11FallbackNext9AM() { var s=paid(); s.nextChargeOn=today.adding(days:2).description; s.reminderEnabled=true; let plan=NotificationPlanner.plan([s],now:today.at(hour:10),changedIDs:[s.id]); XCTAssertEqual(plan.requests.first?.triggerAt,today.adding(days:1).at()) }
    func testN11FallbackTodayBefore9() { var s=paid(); s.nextChargeOn=today.adding(days:2).description; s.reminderEnabled=true; let plan=NotificationPlanner.plan([s],now:today.at(hour:8),changedIDs:[s.id]); XCTAssertEqual(plan.requests.first?.triggerAt,today.at()) }
    func testN12SameDayCatchupOnlyOnceOnSave() { var s=paid(); s.nextChargeOn=today.description; s.reminderEnabled=true; let now=today.at(hour:10); let p=NotificationPlanner.plan([s],now:now,changedIDs:[s.id]); XCTAssertEqual(p.requests.count,1); XCTAssertGreaterThan(p.requests[0].triggerAt,now); XCTAssertLessThanOrEqual(p.requests[0].triggerAt.timeIntervalSince(now),120) }
    func testN13ForegroundNeverCatchup() { var s=paid(); s.nextChargeOn=today.description; s.reminderEnabled=true; XCTAssertTrue(NotificationPlanner.plan([s],now:today.at(hour:10)).requests.isEmpty) }
    func testN14SameTimeMerged() { var a=paid("A"), b=paid("B"); a.nextChargeOn="2026-11-01"; b.nextChargeOn=a.nextChargeOn; a.reminderEnabled=true;b.reminderEnabled=true; let p=NotificationPlanner.plan([a,b],now:today.at()); XCTAssertEqual(p.requests.count,1); XCTAssertEqual(p.requests[0].events.count,2) }
    func testN15Privacy() { var s=paid("PRIVATE",12345);s.nextChargeOn="2026-11-01";s.reminderEnabled=true;s.notes="SECRET";let plan=NotificationPlanner.plan([s],now:today.at()).requests[0]; let hidden=NotificationPlanner.body(plan,showNames:false); XCTAssertFalse(hidden.contains("PRIVATE")); for body in [hidden,NotificationPlanner.body(plan,showNames:true)] { XCTAssertFalse(body.contains("123"));XCTAssertFalse(body.contains("SECRET")); XCTAssertFalse(body.contains("¥")) } }
    func testN16RenewalWithOnlyExpiryDoesNotRecur() { var s=paid(); s.autoRenew = .on;s.accessEndsOn="2026-11-01";s.reminderEnabled=true;let p=NotificationPlanner.plan([s],now:today.at());XCTAssertEqual(p.requests.count,1);XCTAssertEqual(p.requests.first?.events.first?.kind,"renewal") }
    func testN17UncertainNoRecurrence() { var s=paid();s.nextChargeOn="2026-11-01";s.reminderEnabled=true;XCTAssertEqual(NotificationPlanner.plan([s],now:today.at()).requests.count,1) }
    func testN18TrialPastReview() { var s=paid();s.isTrial=true;s.nextChargeOn="2026-10-16";XCTAssertEqual(StatusResolver.status(s,today:today),.needsReview) }
    func testN19BusinessTimeZone() { let d=ISO8601DateFormatter().date(from:"2026-10-16T20:00:00Z")!;XCTAssertEqual(LocalDate(date:d).description,"2026-10-17");XCTAssertEqual(LocalDate.calendar.timeZone.identifier,"Asia/Shanghai") }
    func testPastEventsNeverScheduled() { var s=paid();s.autoRenew = .on;s.nextChargeOn="2026-10-01";s.reminderEnabled=true;XCTAssertTrue(NotificationPlanner.plan([s],now:today.at(),changedIDs:[s.id]).requests.isEmpty) }
    func testArchivedNeverScheduled() { var s=paid();s.nextChargeOn="2026-11-01";s.reminderEnabled=true;s.isArchived=true;XCTAssertTrue(NotificationPlanner.plan([s],now:today.at()).requests.isEmpty) }
    func testUncertainEventSelection() { var s=paid();s.nextChargeOn="2026-11-02";s.accessEndsOn="2026-11-01";XCTAssertEqual(EventResolver.event(s)?.kind,"expiry");s.preferredEventRaw="renewal";XCTAssertEqual(EventResolver.event(s)?.date.description,"2026-11-02") }
    func testFXValidation() { XCTAssertThrowsError(try Money.rate("1e2"));XCTAssertThrowsError(try Money.rate("0"));XCTAssertThrowsError(try Money.rate("7.12345"));XCTAssertEqual(try Money.rate("7.2000"),Decimal(string:"7.2")) }
    func testUnknownOneOffNeverDisplaysZero() { var s=paid("未知买断",nil,.oneOff);s.isLifetime=true;let r=sum([s]);XCTAssertEqual(r.mainLabel,"待补充");XCTAssertFalse(r.oneOffLabel!.contains("¥0"));XCTAssertEqual(r.knownOneOffCount,0) }
    func testUnknownTrialFutureNeverDisplaysZero() { var s=paid();s.isTrial=true;let r=sum([s]);XCTAssertEqual(r.knownTrialCount,0);XCTAssertFalse(r.notices.joined().contains("¥0"));XCTAssertTrue(r.notices.joined().contains("转正费用待补")) }
}
