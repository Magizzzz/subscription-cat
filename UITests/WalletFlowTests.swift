import XCTest
final class WalletFlowTests: XCTestCase {
    override func setUp() { super.setUp();continueAfterFailure=false;executionTimeAllowance=120 }
    func reveal(_ app: XCUIApplication, _ element: XCUIElement, bottomMargin: CGFloat = 130) {
        for _ in 0..<16 {
            if element.exists && element.isHittable && element.frame.minY > 150 && element.frame.maxY < app.frame.height - bottomMargin { return }
            let down = element.exists && element.frame.minY < 150
            app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:down ? 0.48 : 0.72)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:down ? 0.72 : 0.48)))
        }
    }
    func shot(_ name: String) { let a=XCTAttachment(screenshot:XCUIApplication().screenshot());a.name=name;a.lifetime = .keepAlways;add(a) }
    func start() -> XCUIApplication { let app=XCUIApplication();app.launchArguments=["-ui-testing"];app.launch();XCTAssertTrue(app.buttons["addFirst"].waitForExistence(timeout:10));return app }
    func addUnknown(_ app: XCUIApplication) {
        app.buttons["addFirst"].tap();let name=app.descendants(matching: .any).matching(identifier: "memberName").firstMatch;XCTAssertTrue(name.waitForExistence(timeout:5));name.tap();name.typeText("测试会员");app.buttons["其他"].tap();if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() };shot("02-editor-light-test-data");app.buttons["saveMember"].tap();XCTAssertTrue(app.buttons["walletAdd"].waitForExistence(timeout:8))
    }
    func testAddEditStatsArchiveRestore() {
        let app=start();shot("01-empty-light");addUnknown(app);XCTAssertTrue(app.staticTexts["待补充"].exists);shot("03-wallet-unknown-test-data")
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "测试会员，")).firstMatch.tap();XCTAssertTrue(app.buttons["编辑"].waitForExistence(timeout:5));app.buttons["编辑"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "memberName").firstMatch.waitForExistence(timeout:5))
        reveal(app,app.buttons["billingCycle"]);app.buttons["billingCycle"].tap();app.buttons["月"].tap()
        let amount=app.textFields["amount"];reveal(app,amount);amount.tap();amount.typeText("30");if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() };app.buttons["saveMember"].tap()
        XCTAssertTrue(app.staticTexts["¥30 / 月"].firstMatch.waitForExistence(timeout:8));shot("04-detail-paid-test-data")
        app.swipeUp();let archive=app.buttons["归档这项记录"];XCTAssertTrue(archive.waitForExistence(timeout:5));archive.tap();app.alerts.buttons["归档"].tap()
        XCTAssertTrue(app.buttons["恢复这项记录"].waitForExistence(timeout:5));app.buttons["恢复这项记录"].tap();app.alerts.buttons["恢复"].tap();XCTAssertTrue(app.buttons["归档这项记录"].waitForExistence(timeout:5))
        app.navigationBars.buttons.element(boundBy:0).tap();XCTAssertTrue(app.buttons["walletAdd"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["¥30"].exists);shot("05-wallet-paid-test-data")
    }
    func testCatalogAliasAndDuplicate() {
        let app=start();app.buttons["addFirst"].tap();let name=app.descendants(matching: .any).matching(identifier: "memberName").firstMatch;name.tap();name.typeText("网易云");let suggestion=app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "网易云音乐")).firstMatch;XCTAssertTrue(suggestion.waitForExistence(timeout:5));suggestion.tap();app.buttons["saveMember"].tap();XCTAssertTrue(app.buttons["walletAdd"].waitForExistence(timeout:8));app.buttons["添加会员"].tap();app.descendants(matching: .any).matching(identifier: "memberName").firstMatch.tap();app.descendants(matching: .any).matching(identifier: "memberName").firstMatch.typeText("网易云");app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "网易云音乐")).firstMatch.tap();XCTAssertTrue(app.alerts["钱包里可能已有这项会员"].waitForExistence(timeout:5));app.alerts.buttons["打开已有"].tap();XCTAssertTrue(app.buttons["编辑"].waitForExistence(timeout:5))
    }
    func testForceQuitKeepsDiskRecord() {
        let app=XCUIApplication();app.launchArguments=["-ui-testing-disk","-ui-reset-store"];app.launch()
        XCTAssertTrue(app.buttons["addFirst"].waitForExistence(timeout:10));addUnknown(app)
        app.terminate();app.launchArguments=["-ui-testing-disk"];app.launch()
        XCTAssertTrue(app.buttons["walletAdd"].waitForExistence(timeout:10));XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "测试会员，")).firstMatch.exists)
    }
    func testAccessibilityLabelsHitRegionsAndClipping() throws {
        let app = start()
        // Contrast remains a separate diagnostic: the iOS 27 audit also flags the
        // native glass Cancel button with near-black text. Preserve that finding
        // in the report rather than treating it as a passing contrast audit.
        let checks: XCUIAccessibilityAuditType = [.hitRegion, .sufficientElementDescription, .trait, .textClipped]
        try app.performAccessibilityAudit(for: checks)
        app.buttons["addFirst"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "memberName").firstMatch.waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: checks)
        app.buttons["取消"].tap()
        addUnknown(app)
        try app.performAccessibilityAudit(for: checks)
        app.tabBars.buttons["我的"].tap(); app.buttons["profileReminders"].tap()
        try app.performAccessibilityAudit(for: checks)
    }
    func testEditorKeyboardFocusAndCancel() {
        let app = start()
        app.buttons["addFirst"].tap()
        let name = app.descendants(matching: .any).matching(identifier: "memberName").firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("键盘测试")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertEqual(name.value as? String, "键盘测试")
        let dismissKeyboard = app.buttons["收起键盘"]
        XCTAssertTrue(dismissKeyboard.isHittable)
        XCTAssertLessThanOrEqual(dismissKeyboard.frame.maxY, app.keyboards.firstMatch.frame.minY + 2)
        shot("keyboard-name-focused")
        dismissKeyboard.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertEqual(name.value as? String, "键盘测试")
        name.tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["addFirst"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }
    func testDeniedNotificationKeepsRecord() {
        let app=start()
        let handler=addUIInterruptionMonitor(withDescription:"通知权限") { alert in
            for title in ["不允许", "Don’t Allow", "Don't Allow"] { if alert.buttons[title].exists { alert.buttons[title].tap();return true } };return false
        }
        defer { removeUIInterruptionMonitor(handler) }
        app.buttons["addFirst"].tap();let name=app.descendants(matching: .any).matching(identifier: "memberName").firstMatch;name.tap();name.typeText("提醒测试");app.buttons["其他"].tap();if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        let toggle=app.switches["dateToggle-下次预计续费日"]
        reveal(app,toggle)
        XCTAssertTrue(toggle.isHittable);print("DATE TOGGLE: \(toggle.debugDescription)");shot("before-date-tap");toggle.coordinate(withNormalizedOffset:CGVector(dx:0.93,dy:0.5)).tap();XCTAssertEqual(toggle.value as? String,"1");shot("date-enabled-test-data")
        app.buttons["saveMember"].tap()
        if app.buttons["允许系统通知"].waitForExistence(timeout:3) { app.buttons["允许系统通知"].tap();app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.02)).tap() }
        XCTAssertTrue(app.buttons["walletAdd"].waitForExistence(timeout:8))
        app.tabBars.buttons["我的"].tap(); app.buttons["profileReminders"].tap();XCTAssertTrue(app.staticTexts["系统通知已关闭"].firstMatch.waitForExistence(timeout:5));shot("07-reminders-denied-test-data")
    }
    func testVisualAccessibilityEntryAndEditor() {
        let app=start();shot("visual-empty")
        app.buttons["添加会员"].firstMatch.tap();let name=app.descendants(matching: .any).matching(identifier: "memberName").firstMatch;XCTAssertTrue(name.waitForExistence(timeout:5));name.tap();name.typeText("大字体测试");if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        let category=app.buttons["其他"]
        reveal(app,category)
        XCTAssertTrue(category.isHittable);category.tap();shot("visual-editor-category");app.buttons["saveMember"].tap();XCTAssertTrue(app.buttons["walletAdd"].waitForExistence(timeout:8));shot("visual-wallet")
    }
    func testSharePrivacyDefaultsAndCancel() {
        let app = start()
        XCTAssertFalse(app.buttons["openShare"].exists)
        addUnknown(app)
        reveal(app, app.buttons["openShare"]); app.buttons["openShare"].tap()
        let amounts = app.switches["shareAmounts"], categories = app.switches["shareCategories"], services = app.switches["shareServices"]
        XCTAssertTrue(amounts.waitForExistence(timeout: 5))
        XCTAssertEqual(amounts.value as? String, "0"); XCTAssertEqual(categories.value as? String, "1"); XCTAssertEqual(services.value as? String, "0")
        XCTAssertTrue(app.images["sharePosterPreview"].exists); shot("stage4-private-preview")
        amounts.switches.firstMatch.exists ? amounts.switches.firstMatch.tap() : amounts.tap()
        services.switches.firstMatch.exists ? services.switches.firstMatch.tap() : services.tap()
        XCTAssertEqual(amounts.value as? String, "1"); XCTAssertEqual(services.value as? String, "1")
        shot("stage4-full-preview")
        amounts.tap(); XCTAssertEqual(amounts.value as? String, "0")
        let share = app.buttons["shareImage"]; reveal(app, share); share.tap()
        let close = app.descendants(matching: .any).matching(identifier: "PopoverDismissRegion").firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 8)); shot("stage4-system-share")
        close.tap()
        XCTAssertTrue(app.switches["shareAmounts"].waitForExistence(timeout: 5))
        app.navigationBars["分享预览"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["walletAdd"].waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["待补充"].exists)
        reveal(app, app.buttons["openShare"]); app.buttons["openShare"].tap()
        XCTAssertTrue(app.switches["shareAmounts"].waitForExistence(timeout: 5)); XCTAssertEqual(app.switches["shareAmounts"].value as? String, "0")
    }
    func beginCheckup(_ app: XCUIApplication) {
        app.buttons["walletStartCheckup"].tap()
        XCTAssertTrue(app.buttons["startCheckup"].waitForExistence(timeout: 5)); app.buttons["startCheckup"].tap()
        XCTAssertTrue(app.staticTexts["checkupProgress"].waitForExistence(timeout: 5))
    }
    func answerCard(_ app: XCUIApplication, choice: String, nextIndex: Int) {
        let button = app.buttons["checkup-" + choice]; reveal(app, button); button.tap()
        if nextIndex < 20 {
            let progress = app.staticTexts["checkupProgress"]
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "已看 \(nextIndex)/20"), object: progress)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
        } else { XCTAssertTrue(app.staticTexts["checkupReview"].waitForExistence(timeout: 5)) }
    }
    func testCheckupFullFlowPreviewCommitPendingAndShare() {
        executionTimeAllowance = 240
        let app = start(); beginCheckup(app); shot("stage5-first-card")
        app.buttons["checkup-paid"].tap()
        let tier = app.buttons["checkupTier-0"]; XCTAssertTrue(tier.waitForExistence(timeout: 5)); shot("stage5-paid-tiers"); tier.tap()
        let progressOne = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "已看 1/20"), object: app.staticTexts["checkupProgress"])
        XCTAssertEqual(XCTWaiter.wait(for: [progressOne], timeout: 5), .completed)
        for index in 1..<20 { answerCard(app, choice: "none", nextIndex: index + 1) }
        shot("stage5-review")
        app.buttons["commitCheckup"].tap(); XCTAssertTrue(app.alerts["确认写入钱包？"].waitForExistence(timeout: 5)); app.alerts.buttons["返回检查"].tap()
        XCTAssertTrue(app.buttons["commitCheckup"].waitForExistence(timeout: 5))
        app.buttons["commitCheckup"].tap(); app.alerts.buttons["确认提交"].tap()
        let result = app.staticTexts["checkupResult"]; XCTAssertTrue(result.waitForExistence(timeout: 5)); XCTAssertTrue(result.label.contains("本次新增 1 项；钱包当前共 1 项"))
        reveal(app, result); shot("stage5-result")
        let share = app.buttons["checkupShare"]; reveal(app, share); share.tap(); XCTAssertTrue(app.switches["shareAmounts"].waitForExistence(timeout: 5)); XCTAssertEqual(app.switches["shareAmounts"].value as? String, "0")
    }
    func testCheckupEightAnswersForceQuitContinueAndUndo() {
        executionTimeAllowance = 180
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing-disk", "-ui-reset-store"]; app.launch()
        XCTAssertTrue(app.buttons["addFirst"].waitForExistence(timeout: 10)); beginCheckup(app)
        for index in 0..<8 { answerCard(app, choice: "none", nextIndex: index + 1) }
        app.terminate(); app.launchArguments = ["-ui-testing-disk"]; app.launch()
        XCTAssertTrue(app.buttons["addFirst"].waitForExistence(timeout: 10))
        let tab = app.tabBars.buttons["体检"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5)); tab.tap()
        XCTAssertTrue(app.staticTexts["checkupProgress"].waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["checkupProgress"].label.contains("已看 8/20")); shot("stage5-resume-eight")
        let back = app.buttons["checkupBack"]; reveal(app, back); back.tap()
        XCTAssertTrue(app.staticTexts["checkupProgress"].label.contains("已看 7/20"))
        answerCard(app, choice: "none", nextIndex: 8)
        app.tabBars.buttons["钱包"].tap(); XCTAssertTrue(app.buttons["addFirst"].waitForExistence(timeout: 5))
    }
    func testCheckupCustomAmountAndCollapse() {
        let app = start(); beginCheckup(app)
        app.buttons["checkup-paid"].tap(); XCTAssertTrue(app.buttons["checkupTierCustom"].waitForExistence(timeout: 5))
        app.buttons["checkupCollapse"].tap(); XCTAssertTrue(app.buttons["checkup-none"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["checkupProgress"].label.contains("已看 0/20"))
        app.buttons["checkup-paid"].tap(); let custom = app.buttons["checkupTierCustom"]; XCTAssertTrue(custom.waitForExistence(timeout: 5)); custom.tap()
        let field = app.textFields["checkupCustomAmount"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.typeText("33.5"); shot("stage5-custom-amount")
        app.buttons["checkupCustomDone"].tap()
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "已看 1/20"), object: app.staticTexts["checkupProgress"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
        app.tabBars.buttons["钱包"].tap(); XCTAssertTrue(app.buttons["addFirst"].waitForExistence(timeout: 5))
    }
    func testCheckupExistingAmountBlankIsPreserved() {
        executionTimeAllowance = 180
        let app = start(); app.buttons["addFirst"].tap()
        let name = app.descendants(matching: .any).matching(identifier: "memberName").firstMatch; name.tap(); name.typeText("iCloud")
        let suggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "iCloud+")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5)); suggestion.tap(); if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        let cycle = app.buttons["billingCycle"]; reveal(app, cycle); cycle.tap(); app.buttons["月"].tap()
        let amount = app.textFields["amount"]; reveal(app, amount); amount.tap(); amount.typeText("30"); if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }; app.buttons["saveMember"].tap()
        XCTAssertTrue(app.buttons["walletAdd"].waitForExistence(timeout: 5))
        app.tabBars.buttons["体检"].tap(); app.buttons["startCheckup"].tap()
        XCTAssertTrue(app.staticTexts["checkupProgress"].waitForExistence(timeout: 5))
        let icloud = 7 // apple_icloud position in CheckupEngine.primaryIDs
        for index in 0..<icloud { answerCard(app, choice: "none", nextIndex: index + 1) }
        app.buttons["checkup-paid"].tap()
        let keep = app.buttons["checkupKeep"]; XCTAssertTrue(keep.waitForExistence(timeout: 5)); XCTAssertTrue(keep.label.contains("¥30 / 月")); shot("stage5-existing-keep")
        keep.tap()
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "已看 \(icloud + 1)/20"), object: app.staticTexts["checkupProgress"])
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
        app.buttons["checkupBack"].tap(); app.buttons["checkup-paid"].tap()
        XCTAssertTrue(app.buttons["checkupKeep"].waitForExistence(timeout: 5)); shot("stage5-existing-blank-preserved")
        app.tabBars.buttons["钱包"].tap(); XCTAssertTrue(app.staticTexts["¥30"].waitForExistence(timeout: 5))
    }
    func testWalletRedesignStackAndSimplifiedEditor() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-wallet-demo"]; app.launch()
        XCTAssertTrue(app.staticTexts["界面演示 · 金额为虚构示例"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["¥361"].exists)
        shot("redesign-wallet-stack")
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "walletPass-"))
        XCTAssertEqual(cards.count, 12)
        let first = cards.element(boundBy: 0)
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertTrue(app.buttons["编辑"].waitForExistence(timeout: 5))
        shot("redesign-pass-detail")
        app.buttons["编辑"].tap()
        let amount = app.textFields["amount"]; reveal(app, amount)
        XCTAssertTrue(amount.exists); XCTAssertFalse(app.buttons["币种"].exists)
        XCTAssertFalse(app.switches["试用中"].exists); XCTAssertFalse(app.switches["differentNext"].exists)
        XCTAssertFalse(app.textFields["nextAmount"].exists); XCTAssertFalse(app.buttons["金额依据"].exists)
        shot("redesign-single-rmb-amount")
        app.buttons["取消"].tap(); app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["统计"].tap()
        XCTAssertTrue(app.staticTexts["分类统计"].waitForExistence(timeout: 5)); shot("redesign-statistics")
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["profileReminders"].waitForExistence(timeout: 5)); shot("redesign-profile")
    }
    func testCheckupSwipeThresholdAndPaidShortcut() {
        let app = start(); beginCheckup(app)
        let card = app.otherElements["checkupCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        func drag(_ from: CGFloat, _ to: CGFloat) {
            let frame = card.frame
            let y = min(app.frame.height - 140, max(180, frame.minY + 60))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: frame.minX + frame.width * from, dy: y)).press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: frame.minX + frame.width * to, dy: y)))
        }
        drag(0.6, 0.48)
        XCTAssertTrue(app.staticTexts["checkupProgress"].label.contains("已看 0/20"))
        drag(0.75, 0.25)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "已看 1/20"), object: app.staticTexts["checkupProgress"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
        drag(0.25, 0.75)
        XCTAssertTrue(app.buttons["checkupTier-0"].waitForExistence(timeout: 5)); shot("stage5-swipe-paid-tiers"); app.buttons["checkupCollapse"].tap()
        XCTAssertTrue(app.staticTexts["checkupProgress"].waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["checkupProgress"].label.contains("已看 1/20"))
    }
    func openDataManagement(_ app: XCUIApplication) {
        app.tabBars.buttons["我的"].tap(); app.buttons["设置与偏好"].tap();let link=app.buttons["dataManagement"];reveal(app,link);link.tap()
        XCTAssertTrue(app.buttons["importBackup"].waitForExistence(timeout:5))
    }
    func testBackupCancellationAndClearConfirmations() {
        let app=start();addUnknown(app);openDataManagement(app);shot("stage3-data-management")
        app.buttons["exportBackup"].tap();app.alerts.buttons["取消"].tap();XCTAssertFalse(app.staticTexts["上次导出"].exists)
        app.buttons["exportBackup"].tap();app.alerts.buttons["继续导出"].tap()
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForExistence(timeout:8))
        shot("stage3-export-before-cancel")
        if !app.buttons["取消"].firstMatch.exists && app.buttons["浏览"].exists { app.buttons["浏览"].tap() }
        let cancel=app.buttons["取消"].firstMatch
        if !cancel.waitForExistence(timeout:5) { XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout:5)) }
        shot("stage3-export-system-picker");
        if cancel.exists { cancel.tap() } else { app.buttons["Cancel"].tap() }
        XCTAssertTrue(app.buttons["importBackup"].waitForExistence(timeout:5));XCTAssertFalse(app.staticTexts["上次导出"].exists)
        app.buttons["importBackup"].tap()
        let pickerReady=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in app.buttons["取消"].exists || app.buttons["Cancel"].exists || app.buttons["浏览"].exists },object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[pickerReady],timeout:8),.completed)
        if !app.buttons["取消"].firstMatch.exists && app.buttons["浏览"].exists { app.buttons["浏览"].tap() }
        let cancelImport=app.buttons["取消"].firstMatch
        if !cancelImport.waitForExistence(timeout:5) { XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout:5)) }
        shot("stage3-import-system-picker")
        if cancelImport.exists { cancelImport.tap() } else { app.buttons["Cancel"].tap() }
        XCTAssertTrue(app.buttons["clearWallet"].waitForExistence(timeout:5));app.buttons["clearWallet"].tap();shot("stage3-clear-review")
        app.buttons["取消"].tap();XCTAssertTrue(app.buttons["clearWallet"].waitForExistence(timeout:5))
        app.buttons["clearWallet"].tap();app.buttons["continueClear"].tap();XCTAssertTrue(app.alerts["最后确认：清空本机数据？"].waitForExistence(timeout:5));app.alerts.buttons["取消"].tap()
        app.buttons["clearWallet"].tap();app.buttons["continueClear"].tap();XCTAssertTrue(app.alerts["最后确认：清空本机数据？"].waitForExistence(timeout:5));app.alerts.buttons["清空"].tap()
        XCTAssertTrue(app.buttons["addFirst"].waitForExistence(timeout:8));shot("stage3-cleared-wallet")
    }
    func testExportThenImportBackupEndToEnd() {
        let app=start();addUnknown(app);openDataManagement(app)
        app.buttons["exportBackup"].tap();app.alerts.buttons["继续导出"].tap()
        let save=app.buttons["DOCPicker.actionButton"];XCTAssertTrue(save.waitForExistence(timeout:8))
        let filename="WalletBackup-" + String(UUID().uuidString.prefix(8))
        let field=app.textFields["DOCPicker.filenameTextField"];field.tap()
        if let value=field.value as? String { field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:value.count)) }
        field.typeText(filename);save.tap()
        XCTAssertTrue(app.alerts["备份导出"].waitForExistence(timeout:8));XCTAssertTrue(app.alerts.staticTexts["备份已导出，请妥善保管文件。"].exists);app.alerts.buttons["知道了"].tap();shot("stage3-export-complete")
        app.buttons["clearWallet"].tap();app.buttons["continueClear"].tap();XCTAssertTrue(app.alerts["最后确认：清空本机数据？"].waitForExistence(timeout:5));app.alerts.buttons["清空"].tap();XCTAssertTrue(app.buttons["addFirst"].waitForExistence(timeout:8))
        openDataManagement(app);app.buttons["importBackup"].tap()
        let importedFile=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", filename)).firstMatch
        if !importedFile.waitForExistence(timeout:5) {
            let search=app.searchFields.firstMatch
            if search.exists { search.tap();search.typeText(filename) }
        }
        
        XCTAssertTrue(importedFile.waitForExistence(timeout:8))
        let fileCell=app.collectionViews.cells.matching(NSPredicate(format:"label CONTAINS %@", filename)).firstMatch
        XCTAssertTrue(fileCell.exists);fileCell.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.25)).tap()
        XCTAssertTrue(app.navigationBars["恢复预览"].waitForExistence(timeout:8));shot("stage3-restore-preview")
        reveal(app,app.buttons["confirmRestore"],bottomMargin:50);app.buttons["confirmRestore"].tap();XCTAssertTrue(app.alerts["替换本机全部数据？"].waitForExistence(timeout:5));app.alerts.buttons["确认替换"].tap()
        XCTAssertTrue(app.alerts["恢复完成"].waitForExistence(timeout:8));app.alerts.buttons["完成"].tap()
        XCTAssertTrue(app.navigationBars["备份与恢复"].waitForExistence(timeout:5));app.navigationBars["备份与恢复"].buttons["设置"].tap();XCTAssertTrue(app.buttons["关闭"].waitForExistence(timeout:5));app.buttons["关闭"].tap();app.tabBars.buttons["钱包"].tap();XCTAssertTrue(app.buttons["walletAdd"].waitForExistence(timeout:8));shot("stage3-restored-wallet")
    }

}
