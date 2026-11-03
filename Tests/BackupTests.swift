import XCTest
import SwiftData
@testable import SubscriptionWallet

final class BackupCodecTests: XCTestCase {
    func member(_ name: String = "测试会员") -> Subscription { var s = Subscription(); s.name = name; s.category = .other; return s }
    func envelope(_ records: [Subscription]? = nil) -> BackupEnvelope { BackupEnvelope(exportedAt: Date(), appVersion: "0.1.1 (2)", subscriptions: records ?? [member()], preferences: Preferences()) }
    func raw(_ envelope: BackupEnvelope) throws -> Data { try JSONEncoder().encode(envelope) }
    func testRoundTripPreservesEveryFieldAndPreferences() throws {
        var parent = member("88VIP"); parent.serviceID = "taobao_88vip"; parent.category = .lifeShopping; parent.amountMinor = 28800; parent.cycle = .yearly; parent.autoRenew = .off; parent.accessEndsOn = "2027-01-01"
        var child = member("优酷"); child.acquisition = .bundled; child.sourceSubscriptionID = parent.id; child.sourceName = parent.name; child.accessEndsOn = "2027-01-01"
        var unknown = member("未知金额"); unknown.isArchived = true; unknown.notes = "保留这段备注"; unknown.planLabel = "套餐记录"
        var foreign = member("外币试用"); foreign.currency = .USD; foreign.isTrial = true; foreign.cycle = .monthly; foreign.nextPeriodAmountMinor = 2000; foreign.amountConfidenceRaw = "estimated"; foreign.nextChargeOn = "2026-11-01"; foreign.recurrenceAnchorOn = foreign.nextChargeOn; foreign.reminderEnabled = true
        var p = Preferences(); p.exchangeRates["USD"] = "7.2000"; p.rateUpdatedAt["USD"] = Date(); p.lastBackupExportedAt = Date(); p.notificationShowsServiceName = false; p.defaultLeadDays = 7
        let records = [parent, child, unknown, foreign]
        let data = try BackupCodec.encode(records: records, preferences: p)
        let backup = try BackupCodec.decode(data)
        XCTAssertEqual(backup.envelope.subscriptions, records); XCTAssertEqual(backup.envelope.preferences, p)
        let today = LocalDate("2026-10-17")!
        let before = CostCalculator.summary(records, preferences: p, today: today)
        let after = CostCalculator.summary(backup.envelope.subscriptions, preferences: backup.envelope.preferences, today: today)
        XCTAssertEqual(after.monthly, before.monthly); XCTAssertEqual(after.held, before.held)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("authorization")); XCTAssertFalse(text.contains("scheduledCount"))
    }
    func testFixedAcceptanceDatasetRoundTrip() throws {
        var main = member("88VIP"); main.serviceID = "taobao_88vip"; main.category = .lifeShopping; main.amountMinor = 28800; main.cycle = .yearly; main.autoRenew = .off; main.accessEndsOn = "2027-01-01"
        var music = member("网易云音乐"); music.category = .entertainment; music.acquisition = .bundled; music.sourceSubscriptionID = main.id; music.sourceName = main.name; music.accessEndsOn = "2027-01-01"
        var video = music; video.id = UUID(); video.name = "优酷"
        var disk = member("百度网盘"); disk.category = .storageEfficiency; disk.amountMinor = 12000; disk.cycle = .yearly; disk.autoRenew = .on; disk.nextChargeOn = "2026-11-01"
        var qq = member("QQ音乐"); qq.category = .entertainment; qq.cycle = .monthly
        var wps = member("WPS"); wps.category = .storageEfficiency; wps.acquisition = .unknown
        var tool = member("临时工具"); tool.category = .aiCreation; tool.amountMinor = 9900; tool.cycle = .oneOff; tool.isLifetime = true
        var old = member("旧视频会员"); old.category = .entertainment; old.amountMinor = 3000; old.cycle = .monthly; old.autoRenew = .off; old.accessEndsOn = "2026-10-01"
        let records = [main, music, video, disk, qq, wps, tool, old]
        let imported = try BackupCodec.decode(BackupCodec.encode(records: records, preferences: Preferences()))
        XCTAssertEqual(imported.envelope.subscriptions, records)
        let summary = CostCalculator.summary(imported.envelope.subscriptions, preferences: imported.envelope.preferences, today: LocalDate("2026-10-17")!)
        XCTAssertEqual(summary.held, 7); XCTAssertEqual(summary.monthly, 34); XCTAssertEqual(summary.annual, 408); XCTAssertEqual(summary.missing, 1); XCTAssertEqual(summary.oneOff, 99)
    }
    func testCorruptEmptyAndWrongTypesRejected() {
        for text in ["", "not json", "[]", "{}", "{\"formatVersion\":\"1\"}"] { XCTAssertThrowsError(try BackupCodec.decode(Data(text.utf8))) }
    }
    func testFutureVersionRejectedBeforeMissingFields() {
        XCTAssertThrowsError(try BackupCodec.decode(Data("{\"formatVersion\":3}".utf8))) { XCTAssertTrue($0.localizedDescription.contains("版本")) }
    }
    func testTooManyBytesRejected() { XCTAssertThrowsError(try BackupCodec.decode(Data(repeating: 32, count: BackupCodec.maxBytes + 1))) }
    func testExactlyTenMBPassesSizeGate() throws {
        var data = try raw(envelope()); data.append(contentsOf: repeatElement(UInt8(32), count: BackupCodec.maxBytes - data.count))
        XCTAssertNoThrow(try BackupCodec.decode(data))
    }
    func testRecordLimit() throws {
        let records = (0..<2001).map { member("会员\($0)") }
        XCTAssertThrowsError(try BackupCodec.decode(raw(envelope(records))))
        XCTAssertNoThrow(try BackupCodec.decode(raw(envelope(Array(records.prefix(2000))))))
    }
    func testDuplicateRecordIDRejected() throws { let s = member(); XCTAssertThrowsError(try BackupCodec.decode(raw(envelope([s, s])))) }
    func testDuplicateServiceIDIncludingArchiveRejected() throws { var a = member(); a.serviceID = "qq_music"; var b = member("已归档"); b.serviceID = a.serviceID; b.isArchived = true; XCTAssertThrowsError(try BackupCodec.decode(raw(envelope([a, b])))) }
    func testAllRawEnumsRejectFallback() throws {
        let paths: [WritableKeyPath<Subscription, String>] = [\.categoryRaw, \.acquisitionRaw, \.billingCycleRaw, \.currencyCode, \.amountConfidenceRaw, \.autoRenewRaw, \.preferredEventRaw]
        for path in paths { var s = member(); s[keyPath: path] = "future-case"; XCTAssertThrowsError(try BackupCodec.decode(raw(envelope([s])))) }
    }
    func testInvalidAmountsRejected() throws {
        for amount: Int64 in [-1, 0, 100_000_000] { var s = member(); s.amountMinor = amount; XCTAssertThrowsError(try BackupCodec.decode(raw(envelope([s])))) }
        var json = try JSONSerialization.jsonObject(with: raw(envelope())) as! [String: Any]
        var records = json["subscriptions"] as! [[String: Any]]; records[0]["amountMinor"] = 1.5; json["subscriptions"] = records
        XCTAssertThrowsError(try BackupCodec.decode(JSONSerialization.data(withJSONObject: json)))
    }
    func testInvalidBusinessDatesRejected() throws {
        for path: WritableKeyPath<Subscription, String?> in [\.nextChargeOn, \.accessEndsOn, \.recurrenceAnchorOn] { var s = member(); s[keyPath: path] = "2026-02-30"; XCTAssertThrowsError(try BackupCodec.decode(raw(envelope([s])))) }
    }
    func testInvalidReferencesRejected() throws {
        var s = member(); s.acquisition = .bundled; s.sourceSubscriptionID = UUID(); XCTAssertThrowsError(try BackupCodec.decode(raw(envelope([s]))))
        s.sourceSubscriptionID = s.id; XCTAssertThrowsError(try BackupCodec.decode(raw(envelope([s]))))
        var parent = member(); parent.acquisition = .gifted; s.sourceSubscriptionID = parent.id; XCTAssertThrowsError(try BackupCodec.decode(raw(envelope([parent, s]))))
    }
    func testRemovedCatalogEntryCanBeRestored() throws { var s = member(); s.serviceID = "retired_service"; XCTAssertNoThrow(try BackupCodec.decode(raw(envelope([s])))) }
    func testInvalidPreferencesAndRatesRejected() throws {
        var e = envelope(); e.preferences.businessTimeZone = "UTC"; XCTAssertThrowsError(try BackupCodec.validate(e))
        e = envelope(); e.preferences.defaultLeadDays = 99; XCTAssertThrowsError(try BackupCodec.validate(e))
        e = envelope(); e.preferences.schemaVersion = 2; XCTAssertThrowsError(try BackupCodec.validate(e))
        for pair in [("USD", "0"), ("USD", "NaN"), ("USD", "7.12345"), ("XYZ", "1"), ("CNY", "1")] { e = envelope(); e.preferences.exchangeRates[pair.0] = pair.1; XCTAssertThrowsError(try BackupCodec.validate(e)) }
    }
    func testOptionalBackupDateDecodesOldPreferencesPayload() throws {
        let p = try JSONDecoder().decode(Preferences.self, from: Data("{\"businessTimeZone\":\"Asia/Shanghai\",\"defaultLeadDays\":3,\"notificationShowsServiceName\":true,\"exchangeRates\":{},\"rateUpdatedAt\":{},\"schemaVersion\":1}".utf8))
        XCTAssertNil(p.lastBackupExportedAt)
    }
    func testOneOffAndNonpaidInvariants() throws {
        var s = member(); s.cycle = .oneOff; XCTAssertThrowsError(try BackupCodec.validate(envelope([s])))
        s.isLifetime = true; XCTAssertNoThrow(try BackupCodec.validate(envelope([s])))
        s.cycle = .monthly; XCTAssertThrowsError(try BackupCodec.validate(envelope([s])))
        s = member(); s.acquisition = .gifted; s.amountMinor = 100; XCTAssertThrowsError(try BackupCodec.validate(envelope([s])))
    }
    func testBoundedFileReaderAndDirectoryRejection() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("backup.json"), data = try raw(envelope())
        try data.write(to: url); XCTAssertEqual(try BackupFileReader.read(url), data)
        XCTAssertThrowsError(try BackupFileReader.read(dir))
        try Data(repeating: 32, count: BackupCodec.maxBytes + 1).write(to: url); XCTAssertThrowsError(try BackupFileReader.read(url))
    }
}

@MainActor final class BackupTransactionTests: XCTestCase {
    let now = LocalDate("2026-10-17")!.at(hour: 10)
    func member(_ name: String, date: String) -> Subscription { var s = Subscription(); s.name = name; s.category = .other; s.nextChargeOn = date; s.reminderEnabled = true; return s }
    func backup(_ record: Subscription, preferences: Preferences = Preferences()) throws -> ValidatedBackup { try BackupCodec.decode(BackupCodec.encode(records: [record], preferences: preferences)) }
    func testRestoreReplacesRecordsAndReplansOnlyNewRequests() async throws {
        let repo = try WalletRepository(container: WalletRepository.container(inMemory: true)), client = FakeNotifications()
        let c = NotificationCoordinator(client: client), old = member("原记录", date: "2026-11-01"), new = member("恢复记录", date: "2026-12-01")
        try repo.save(old); await c.reconcile(repo.records, preferences: repo.preferences, now: now)
        let oldIDs = Set(client.pending.map(\.identifier))
        try await DataProtectionService.restore(backup(new), repository: repo, notifications: c, now: now)
        XCTAssertEqual(repo.records, [new]); XCTAssertEqual(client.pending.count, 1); XCTAssertTrue(oldIDs.isDisjoint(with: client.pending.map(\.identifier)))
        XCTAssertEqual(client.deliveredClears, 1); XCTAssertEqual(c.states[new.id], "已安排")
    }
    func testRestoreKeepsDeniedSystemPermission() async throws {
        let repo = try WalletRepository(container: WalletRepository.container(inMemory: true)), client = FakeNotifications(); client.permission = .denied
        let c = NotificationCoordinator(client: client), new = member("恢复记录", date: "2026-12-01")
        try await DataProtectionService.restore(backup(new), repository: repo, notifications: c, now: now)
        XCTAssertTrue(repo.records[0].reminderEnabled); XCTAssertEqual(c.states[new.id], "系统通知已关闭"); XCTAssertTrue(client.pending.isEmpty); XCTAssertEqual(client.requestsPermission, 0)
    }
    func testFailedRestoreRollsBackAndDoesNotTouchNotifications() async throws {
        var fail = false
        let repo = try WalletRepository(container: WalletRepository.container(inMemory: true), commit: { if fail { throw WalletError.storage("磁盘写入失败") }; try $0.save() })
        let old = member("保留原数据", date: "2026-11-01"); try repo.save(old)
        var prefs = Preferences(); prefs.exchangeRates["USD"] = "7.2"; try repo.savePreferences(prefs)
        let client = FakeNotifications()
        let coordinator = NotificationCoordinator(client: client); await coordinator.reconcile(repo.records, preferences: prefs, now: now)
        let requests = client.pending.map(\.identifier); let originalRecords = repo.records; fail = true
        do { try await DataProtectionService.restore(backup(member("新数据", date: "2026-12-01")), repository: repo, notifications: coordinator, now: now); XCTFail("应写入失败") } catch { }
        try repo.reload(); XCTAssertEqual(repo.records, originalRecords); XCTAssertEqual(repo.preferences, prefs); XCTAssertEqual(client.pending.map(\.identifier), requests); XCTAssertEqual(client.deliveredClears, 0)
    }
    func testClearResetsRecordsPreferencesAndNotificationsButKeepsExportedFile() async throws {
        let repo = try WalletRepository(container: WalletRepository.container(inMemory: true)), client = FakeNotifications()
        let coordinator = NotificationCoordinator(client: client); try repo.save(member("清空测试", date: "2026-11-01"))
        var prefs = Preferences(); prefs.lastBackupExportedAt = Date(); prefs.exchangeRates["USD"] = "7.2"; prefs.notificationShowsServiceName = false; try repo.savePreferences(prefs)
        await coordinator.reconcile(repo.records, preferences: prefs, now: now)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try BackupCodec.encode(records: repo.records, preferences: prefs).write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        try await DataProtectionService.clear(repository: repo, notifications: coordinator)
        try repo.reload(); XCTAssertTrue(repo.records.isEmpty); XCTAssertEqual(repo.preferences, Preferences()); XCTAssertTrue(client.pending.isEmpty); XCTAssertEqual(client.deliveredClears, 1); XCTAssertEqual(coordinator.authorization, .authorized); XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
    func testFailedClearPreservesDataAndNotifications() async throws {
        var fail = false
        let repo = try WalletRepository(container: WalletRepository.container(inMemory: true), commit: { if fail { throw WalletError.storage("磁盘写入失败") }; try $0.save() })
        let old = member("保留", date: "2026-11-01"); try repo.save(old)
        let client = FakeNotifications()
        let c = NotificationCoordinator(client: client); await c.reconcile(repo.records, preferences: repo.preferences, now: now); let pending = client.pending.map(\.identifier); let originalRecords = repo.records; fail = true
        do { try await DataProtectionService.clear(repository: repo, notifications: c); XCTFail("应清空失败") } catch { }
        try repo.reload(); XCTAssertEqual(repo.records, originalRecords); XCTAssertEqual(client.pending.map(\.identifier), pending); XCTAssertEqual(client.deliveredClears, 0)
    }
}
