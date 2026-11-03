import Foundation

/// 用户自己的会员（2026-10-25 他亲口报的价格）。正式包首次启动时补进钱包，免去逐个体检。
/// 只补钱包里还没有的 serviceID，已有记录一律不动。美元按目录统一汇率 7.25 折人民币并标为“估算”；
/// 他说“好像”的价格在备注里写明待核对。没有说过的金额和日期不填，不当零。
enum MyMemberships {
    /// 第一版的一次性标记；只用来识别“前 12 项已经预置过”。
    static let seedKey = "mine.seed.v1"
    /// 已经处理过的 serviceID（预置过或本来就有）。以后新增的会员只补没处理过的，用户删掉的不会被加回来。
    static let doneKey = "mine.seed.ids"
    static let v1IDs = ["claude", "chatgpt", "artlist", "stash", "jimeng", "libtv", "apple_creator_studio", "aigei", "wps", "jianying", "gemini", "xingtu"]
    static let seedBundleID = "local.magi.SubscriptionWallet"

    /// 把还没处理过的预置会员补进钱包；全部成功后才记账，失败下次再试。
    @MainActor static func seedPending(into repo: WalletRepository, defaults: UserDefaults = .standard) {
        var done = Set(defaults.stringArray(forKey: doneKey) ?? [])
        if defaults.bool(forKey: seedKey) { done.formUnion(v1IDs) }
        let pending = all().filter { !done.contains($0.serviceID ?? "") }
        guard !pending.isEmpty, (try? repo.addMissing(pending)) != nil else { return }
        defaults.set(Array(done.union(pending.compactMap(\.serviceID))).sorted(), forKey: doneKey)
    }

    static func all() -> [Subscription] {
        [
            make("claude", "Claude", .aiCreation, plan: "Pro", minor: 14500, .monthly, estimated: true, renews: true,
                 chargeOn: "2026-10-28", anchorOn: "2026-09-28",
                 notes: "日区 Apple ID 订阅，¥3,000 日元/月，每月 28 日续；人民币按 $20×7.25 估算。2026-10-18 苹果提示付款方式有问题，10-28 续费可能失败。"),
            make("chatgpt", "ChatGPT", .aiCreation, plan: "Plus", minor: 14500, .monthly, estimated: true, renews: true,
                 chargeOn: "2026-11-12", anchorOn: "2026-09-12",
                 notes: "日区 Apple ID 订阅，¥3,000 日元/月，每月 12 日续；人民币按 $20×7.25 估算。2026-10-12 那次扣款失败，之后没看到补扣成功的邮件，11-12 能否续上待确认。"),
            make("artlist", "Artlist", .aiCreation, plan: "Music & SFX Pro", minor: 216_775, .yearly, estimated: true,
                 chargeOn: "2027-07-19", anchorOn: "2026-07-19", notes: "原价 $299/年，按 7.25 折算；订阅于 2026-07-19，续费日按一年推算。"),
            make("stash", "Stash 机场", .other, plan: "年付", minor: 20_000, .yearly),
            make("jimeng", "即梦AI", .aiCreation, plan: "年付", minor: 50_000, .yearly),
            make("libtv", "LibTV", .aiCreation, plan: "年付", minor: 399_900, .yearly),
            make("apple_creator_studio", "Apple Creator Studio", .aiCreation, plan: "月付", minor: 1_800, .monthly, renews: true,
                 chargeOn: "2026-11-07", notes: "国区 Apple ID 订阅，11 月 7 日续；含 Final Cut Pro、Logic Pro 等。"),
            make("apple_icloud", "iCloud+", .storageEfficiency, plan: "iCloud+", minor: 6_800, .monthly, renews: true,
                 chargeOn: "2026-11-19", notes: "国区 Apple ID 订阅，每月 19 日续；容量档位未记录。"),
            make("bilibili", "哔哩哔哩大会员", .entertainment, plan: "大会员", minor: 14_800, .yearly, renews: true,
                 chargeOn: "2027-08-22", notes: "国区 Apple ID 订阅，2027-08-22 续；按年付记录（据续费日推断）。"),
            make("aigei", "爱给网", .aiCreation, plan: "铜牌会员", minor: nil, .unknown, endsOn: "2029-05-13", notes: "有效期至 2029-05-13（官网账号页）。实付金额和周期待补；官网价目：月付 ¥39、年付 ¥129。"),
            make("wps", "WPS", .storageEfficiency, plan: "超级会员", minor: nil, .unknown, endsOn: "2027-09-26", notes: "金额未记录。"),
            make("jianying", "剪映", .aiCreation, plan: "年费", minor: 16_800, .yearly, estimated: true, endsOn: "2027-03-22", notes: "金额凭印象，待核对；到期日 2027-03-22。"),
            make("gemini", "Gemini", .aiCreation, plan: "AI Pro 年付", minor: 5_800, .yearly, estimated: true, notes: "原价 $8/年，按 7.25 折算；金额凭印象，待核对。"),
            make("xingtu", "醒图", .aiCreation, plan: "会员", minor: 1_000, .monthly, estimated: true, notes: "按月付记录，周期待核对。"),
            make("baidu_netdisk", "百度网盘", .storageEfficiency, plan: "SVIP", minor: nil, .unknown, endsOn: "2027-12-16", notes: "SVIP9，5T 空间，有效期至 2027-12-16（账号页）。金额和周期未记录。"),
        ]
    }

    static let upgradeKey = "mine.seed.v3"

    /// 第一版预置里后来补了日期的六项（2026-10-26 他给了到期日和 Apple 订阅页的续费日）。手机上若已预置过第一版，且这几项他没动过，就更新成新值。
    private static let v1: [String: (plan: String, minor: Int64, cycle: Cycle, notes: String)] = [
        "artlist": ("年付", 216_775, .yearly, "原价 $299/年，按 7.25 折算。"),
        "aigei": ("铜牌会员", 12_900, .yearly, "按年付 ¥129 记录（月付 ¥39），具体周期待核对。"),
        "jianying": ("年费", 16_800, .yearly, "金额凭印象，待核对。"),
        "claude": ("Pro", 14_500, .monthly, "原价 $20/月，按 7.25 折算。"),
        "chatgpt": ("Plus", 14_500, .monthly, "原价 $20/月，按 7.25 折算。"),
        "apple_creator_studio": ("月付", 1_800, .monthly, "含 Final Cut Pro、Logic Pro 等。"),
    ]
    /// 返回应更新成的新记录；不是未改动的第一版预置就返回 nil。
    static func upgraded(_ r: Subscription) -> Subscription? {
        guard let id = r.serviceID, let old = v1[id], let new = all().first(where: { $0.serviceID == id }),
              r.planLabel == old.plan, r.amountMinor == old.minor, r.cycle == old.cycle, r.notes == old.notes,
              r.nextChargeOn == nil, r.accessEndsOn == nil, r.recurrenceAnchorOn == nil, r.autoRenew == .unknown, !r.isArchived else { return nil }
        var u = r
        u.planLabel = new.planLabel; u.amountMinor = new.amountMinor; u.cycle = new.cycle; u.amountConfidenceRaw = new.amountConfidenceRaw
        u.autoRenew = new.autoRenew; u.nextChargeOn = new.nextChargeOn; u.recurrenceAnchorOn = new.recurrenceAnchorOn; u.accessEndsOn = new.accessEndsOn; u.notes = new.notes
        return u
    }

    private static func make(_ serviceID: String, _ name: String, _ category: Category, plan: String, minor: Int64?, _ cycle: Cycle,
                             estimated: Bool = false, renews: Bool = false, endsOn: String? = nil, chargeOn: String? = nil, anchorOn: String? = nil, notes: String = "") -> Subscription {
        var s = Subscription()
        s.serviceID = serviceID; s.name = name; s.planLabel = plan; s.category = category
        s.acquisition = .paid; s.amountMinor = minor; s.cycle = cycle; s.accessEndsOn = endsOn
        s.nextChargeOn = chargeOn; s.recurrenceAnchorOn = anchorOn; s.autoRenew = renews ? .on : .unknown
        s.amountConfidenceRaw = minor == nil ? "unknown" : (estimated ? "estimated" : "actual")
        s.notes = notes
        return s
    }
}

extension WalletRepository {
    /// Applies `MyMemberships.upgraded` to untouched first-version seeds; one transaction. Returns how many changed.
    @discardableResult func upgradeSeeds(now: Date = Date()) throws -> Int {
        var next = records, changed = 0
        for i in next.indices { if var u = MyMemberships.upgraded(next[i]) { u.updatedAt = now; next[i] = u; changed += 1 } }
        for value in next { try Validator.validate(value, all: next) }
        if changed > 0 { try replaceAll(records: next, preferences: preferences, checkup: checkup) }
        return changed
    }

    /// Adds only the seeds whose serviceID is not in the wallet yet; one transaction. Returns how many were added.
    @discardableResult func addMissing(_ seeds: [Subscription], now: Date = Date()) throws -> Int {
        var next = records, added: [Subscription] = []
        for var seed in seeds where !next.contains(where: { $0.serviceID == seed.serviceID }) {
            seed.createdAt = now; seed.updatedAt = now
            next.append(seed); added.append(seed)
        }
        for value in added { try Validator.validate(value, all: next) }
        if !added.isEmpty { try replaceAll(records: next, preferences: preferences, checkup: checkup) }
        return added.count
    }
}
