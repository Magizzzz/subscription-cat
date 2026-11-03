import Foundation

/// Formats 1 and 2 use Codable's native Date encoding (seconds since 2001-01-01).
/// Business dates remain YYYY-MM-DD strings. No system notification authorization is exported.
struct BackupEnvelope: Codable, Equatable {
    var formatVersion = 2
    var exportedAt: Date
    var appVersion: String
    var subscriptions: [Subscription]
    var preferences: Preferences
    var checkup: CheckupState? = nil
}
struct ValidatedBackup: Identifiable {
    let id = UUID()
    let envelope: BackupEnvelope
    fileprivate init(_ envelope: BackupEnvelope) { self.envelope = envelope }
}
enum BackupCodec {
    static let maxBytes = 10 * 1024 * 1024
    static let maxRecords = 2000
    static func encode(records: [Subscription], preferences: Preferences, now: Date = Date(), appVersion: String = AppVersion.display, checkup: CheckupState? = nil) throws -> Data {
        let envelope = BackupEnvelope(exportedAt: now, appVersion: appVersion, subscriptions: records, preferences: preferences, checkup: checkup)
        _ = try validate(envelope)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(envelope)
        guard data.count <= maxBytes else { throw WalletError.invalid("备份超过 10MB，未导出。") }
        return data
    }
    static func decode(_ data: Data) throws -> ValidatedBackup {
        guard !data.isEmpty, data.count <= maxBytes else { throw WalletError.invalid("备份为空或超过 10MB，未导入。") }
        let decoder = JSONDecoder()
        // Check the envelope version before decoding fields introduced by a newer version.
        struct Header: Decodable { let formatVersion: Int }
        do {
            let header = try decoder.decode(Header.self, from: data)
            guard [1, 2].contains(header.formatVersion) else { throw WalletError.invalid("不支持此备份版本，请使用对应版本的 App。原数据未修改。") }
            return try validate(decoder.decode(BackupEnvelope.self, from: data))
        } catch let error as WalletError { throw error }
        catch { throw WalletError.invalid("备份文件损坏、字段缺失或类型不正确。原数据未修改。") }
    }
    static func validate(_ envelope: BackupEnvelope) throws -> ValidatedBackup {
        guard [1, 2].contains(envelope.formatVersion), envelope.preferences.schemaVersion == 1 else { throw WalletError.invalid("备份版本不受支持，原数据未修改。") }
        guard envelope.subscriptions.count <= maxRecords else { throw WalletError.invalid("备份最多允许 2000 条记录。") }
        guard !envelope.appVersion.isEmpty, envelope.appVersion.count <= 80, validTimestamp(envelope.exportedAt) else { throw WalletError.invalid("备份导出信息无效。") }
        let records = envelope.subscriptions
        guard Set(records.map(\.id)).count == records.count else { throw WalletError.invalid("备份有重复的记录 ID，整包未导入。") }
        let serviceIDs = records.compactMap(\.serviceID)
        guard Set(serviceIDs).count == serviceIDs.count else { throw WalletError.invalid("备份有重复的目录服务 ID（含归档），整包未导入。") }
        for s in records {
            guard Category(rawValue: s.categoryRaw) != nil,
                  Acquisition(rawValue: s.acquisitionRaw) != nil,
                  Cycle(rawValue: s.billingCycleRaw) != nil,
                  Currency(rawValue: s.currencyCode) != nil,
                  AutoRenew(rawValue: s.autoRenewRaw) != nil,
                  ["actual", "estimated", "unknown"].contains(s.amountConfidenceRaw),
                  ["earliest", "renewal", "expiry"].contains(s.preferredEventRaw) else { throw WalletError.invalid("备份含不支持的分类、币种或状态值。") }
            if let sid = s.serviceID, sid.isEmpty || sid.count > 100 || sid.trimmingCharacters(in: .whitespacesAndNewlines) != sid { throw WalletError.invalid("备份服务 ID 无效。") }
            guard validTimestamp(s.createdAt), validTimestamp(s.updatedAt) else { throw WalletError.invalid("备份记录时间无效。") }
            if s.isLifetime && (s.acquisition != .paid || s.cycle != .oneOff) { throw WalletError.invalid("买断标记仅适用于自费一次性记录。") }
            if s.acquisition != .paid && (s.cycle != .unknown || s.isLifetime || s.recurrenceAnchorOn != nil) { throw WalletError.invalid("非自费权益包含不适用的付费字段。") }
            try Validator.validate(s, all: records)
        }
        let p = envelope.preferences
        guard p.businessTimeZone == "Asia/Shanghai", [0,1,3,7].contains(p.defaultLeadDays) else { throw WalletError.invalid("备份的时区或提醒默认值无效。") }
        for (code, raw) in p.exchangeRates {
            guard let currency = Currency(rawValue: code), currency != .CNY, try Money.rate(raw) != nil else { throw WalletError.invalid("备份汇率无效。") }
        }
        for (code, date) in p.rateUpdatedAt {
            guard p.exchangeRates[code] != nil, validTimestamp(date) else { throw WalletError.invalid("汇率更新时间无效。") }
        }
        if let date = p.lastBackupExportedAt, !validTimestamp(date) { throw WalletError.invalid("上次备份时间无效。") }
        if envelope.formatVersion == 1 && envelope.checkup != nil { throw WalletError.invalid("旧备份版本不能包含体检数据。") }
        if let state = envelope.checkup { try CheckupBackupValidator.validate(state, records: records, preferences: p) }
        return ValidatedBackup(envelope)
    }
    static func validTimestamp(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && date >= LocalDate(year: 1900, month: 1, day: 1).at(hour: 0) && date < LocalDate(year: 2201, month: 1, day: 1).at(hour: 0)
    }
}
enum AppVersion {
    static var display: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "0.2.0") (\(info["CFBundleVersion"] as? String ?? "4"))"
    }
}
