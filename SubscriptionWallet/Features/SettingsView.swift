import SwiftUI

struct SettingsView: View {
    @Environment(WalletRepository.self) var repo
    @Environment(NotificationCoordinator.self) var notifications
    @Environment(\.dismiss) var dismiss
    @Environment(\.showWallet) var showWallet
    @State var preferences = Preferences()
    @State var error: String?
    @State var saved = false
    var usedCurrencies: [Currency] { Currency.allCases.filter { c in c != .CNY && (repo.records.contains { $0.currency == c } || preferences.exchangeRates[c.rawValue] != nil) } }
    var body: some View {
        Form {
            Section("通知") {
                Text(notifications.permissionLabel)
                if notifications.authorization == .denied { Button("去系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }
                Picker("默认提前", selection: $preferences.defaultLeadDays) { ForEach([0,1,3,7], id: \.self) { Text($0 == 0 ? "当天" : "\($0)天").tag($0) } }
                Toggle("通知显示服务名", isOn: $preferences.notificationShowsServiceName)
                Text("关闭后仅显示会员数量；任何情况下不显示金额、来源人和备注。").font(.caption).foregroundStyle(Theme.secondary)
            }
            if !usedCurrencies.isEmpty {
                Section("旧记录") {
                    Text("旧外币记录与汇率继续保留。新增会员统一使用人民币。").font(.footnote).foregroundStyle(Theme.secondary)
                }
            }
            Section("数据保护") {
                NavigationLink("备份与恢复") { DataManagementView(onCleared: { dismiss(); showWallet() }) }.accessibilityIdentifier("dataManagement")
            }
            Section("隐私与数据") {
                Text("无需登录，记录仅保存在这台设备。核心功能离线可用，不接入第三方统计或广告 SDK。")
                Text("可手动导出备份。删除 App 会移除本机数据，已经导出的文件不受影响。").font(.footnote).foregroundStyle(Theme.warning)
                Text("本 App 不能取消原平台订阅，也不会读取其他 App 或支付账户。")
                Text("日期和提醒按北京时间计算。").font(.footnote).foregroundStyle(Theme.secondary)
            }
            Section("关于") {
                LabeledContent("版本", value: AppVersion.display)
                Text("钱包、提醒与文件备份 · 本地开发版").font(.caption).foregroundStyle(Theme.secondary)
            }
            if let error { Section { Text(error).foregroundStyle(Theme.destructive) } }
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } } }
        .onAppear { preferences = repo.preferences }
        .onChange(of: repo.preferences) { _, value in preferences = value }
        .alert("设置已保存", isPresented: $saved) { Button("知道了", role: .cancel) {} }
    }
    func save() {
        do {
            try repo.savePreferences(preferences)
            Task { await notifications.reconcile(repo.records, preferences: repo.preferences); saved = true }
        } catch { self.error = error.localizedDescription }
    }
}
