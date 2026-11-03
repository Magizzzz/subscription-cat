#if DEBUG
import Foundation

/// Explicitly launched only in the separate preview bundle, never in a user's wallet.
enum PreviewFixtures {
    static var enabled: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".Preview") == true && ProcessInfo.processInfo.arguments.contains("-wallet-demo")
    }
    @MainActor static func populate(_ repo: WalletRepository) throws {
        guard enabled, repo.records.isEmpty else { return }
        let rows: [(String, String, Category, Int64)] = [
            ("tencent_video", "腾讯视频", .entertainment, 2500),
            ("qq_music", "QQ音乐", .entertainment, 1200),
            ("apple_icloud", "iCloud+", .storageEfficiency, 2100),
            ("chatgpt", "ChatGPT Plus", .aiCreation, 14500),
            ("iqiyi", "爱奇艺", .entertainment, 2500),
            ("baidu_netdisk", "百度网盘", .storageEfficiency, 3000),
            ("bilibili", "哔哩哔哩大会员", .entertainment, 1500),
            ("netease_music", "网易云音乐", .entertainment, 1500),
            ("wps", "WPS", .storageEfficiency, 1500),
            ("quark", "夸克", .storageEfficiency, 2000),
            ("weread", "微信读书", .readingLearning, 1900),
            ("keep", "Keep", .lifeShopping, 1900)
        ]
        let today = LocalDate(date: Date())
        for (index, row) in rows.enumerated() {
            var s = Subscription(); s.serviceID = row.0; s.name = row.1; s.category = row.2
            s.amountMinor = row.3; s.cycle = .monthly; s.autoRenew = .on
            s.nextChargeOn = today.adding(days: 2 + index * 3).description
            s.notes = "仅用于界面演示，金额为虚构示例，不代表官方价格。"
            try repo.save(s)
        }
    }
}
#endif
