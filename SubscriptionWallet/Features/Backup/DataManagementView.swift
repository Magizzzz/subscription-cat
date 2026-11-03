import SwiftUI
import UniformTypeIdentifiers

struct DataManagementView: View {
    @Environment(WalletRepository.self) private var repository
    @Environment(NotificationCoordinator.self) private var notifications
    let onCleared: () -> Void
    @State private var importer = false
    @State private var importing = false
    @State private var candidate: ValidatedBackup?
    @State private var error: String?
    @State private var clearPreview = false
    @State private var requestFinalClear = false
    @State private var clearFinal = false
    @State private var clearing = false
    var body: some View {
        List {
            Section {
                BackupExportButton()
                if let date = repository.preferences.lastBackupExportedAt { LabeledContent("上次导出", value: LocalDate(date: date).description) }
                Text("备份包含会员记录、偏好、体检草稿、待确认区与最近结果，不包含系统通知授权。保存位置由你选择。").font(.footnote).foregroundStyle(Theme.secondary)
            } header: { Text("文件备份") }
            Section {
                Button(importing ? "正在读取与校验…" : "选择备份文件") { importer = true }.accessibilityIdentifier("importBackup")
                Text("仅支持完整替换。先校验、再预览，确认前不改动本机记录。最多 10MB、2000 条记录。").font(.footnote).foregroundStyle(Theme.secondary)
            } header: { Text("恢复") }
            Section {
                Button("清空本机数据", role: .destructive) { clearPreview = true }.accessibilityIdentifier("clearWallet")
                Text("清空会移除记录、偏好、体检数据和本 App 通知。已经导出的备份文件会保留。").font(.footnote).foregroundStyle(Theme.secondary)
            } header: { Text("清空") }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("备份与恢复").navigationBarTitleDisplayMode(.inline)
        .disabled(importing || clearing)
        .fileImporter(isPresented: $importer, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { load(url) }
            case .failure(let failure): if !BackupExportButton.isCancellation(failure) { error = failure.localizedDescription }
            }
        }
        .sheet(item: $candidate) { backup in RestorePreviewView(backup: backup) }
        .sheet(isPresented: $clearPreview, onDismiss: { if requestFinalClear { requestFinalClear = false; clearFinal = true } }) {
            NavigationStack {
                List {
                    Section {
                        Text("将移除 \(repository.records.count) 条会员记录、体检数据及全部偏好，并撤销本 App 待发和已送达的通知。")
                        Text("已导出的文件会保留；系统通知授权不变。清空不会取消原平台订阅。").foregroundStyle(Theme.secondary)
                    }
                    Section { BackupExportButton(title: "先导出当前数据") }
                    Section { Button("继续清空", role: .destructive) { requestFinalClear = true; clearPreview = false }.accessibilityIdentifier("continueClear") }
                }
                .scrollContentBackground(.hidden).background(Theme.background)
                .navigationTitle("清空前请确认").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { clearPreview = false } } }
            }
        }
        .alert("最后确认：清空本机数据？", isPresented: $clearFinal) {
            Button("清空", role: .destructive) { clear() }
            Button("取消", role: .cancel) {}
        } message: { Text("确认后无法直接撤销，可用之前导出的备份恢复。") }
        .alert("操作未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(error ?? "") }
        .interactiveDismissDisabled(importing || clearing)
    }
    private func load(_ url: URL) {
        importing = true
        Task {
            do {
                let validated = try await Task.detached(priority: .userInitiated) { try BackupCodec.decode(BackupFileReader.read(url)) }.value
                candidate = validated
            } catch { self.error = error.localizedDescription }
            importing = false
        }
    }
    private func clear() {
        clearing = true
        Task {
            do { try await DataProtectionService.clear(repository: repository, notifications: notifications); onCleared() }
            catch { self.error = error.localizedDescription }
            clearing = false
        }
    }
}
struct RestorePreviewView: View {
    let backup: ValidatedBackup
    @Environment(WalletRepository.self) private var repository
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false
    @State private var restoring = false
    @State private var error: String?
    @State private var success = false
    private var envelope: BackupEnvelope { backup.envelope }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("校验已通过", systemImage: "checkmark.shield").foregroundStyle(Theme.accent)
                    LabeledContent("记录数量", value: "\(envelope.subscriptions.count) 条（含归档）")
                    LabeledContent("导出日期（北京时间）", value: LocalDate(date: envelope.exportedAt).description)
                    LabeledContent("导出 App 版本", value: envelope.appVersion)
                    LabeledContent("本机当前记录", value: "\(repository.records.count) 条")
                    LabeledContent("体检草稿", value: envelope.checkup?.session.map { "已看 \($0.currentIndex)/20" } ?? "无")
                    LabeledContent("待确认项", value: "\(envelope.checkup?.pending.count ?? 0) 项")
                    Text(envelope.checkup?.latest == nil ? "无最近体检结果" : "含最近一次体检结果").font(.caption)
                    if envelope.formatVersion == 1 { Text("旧版备份不含体检数据；恢复后本机体检草稿、待确认区与结果将清空。").font(.caption).foregroundStyle(Theme.warning) }
                }
                Section {
                    Text("将完整替换本机现有记录、偏好与体检数据，不进行合并。确认前，本机数据和提醒不会改变。").foregroundStyle(Theme.warning)
                    Text("通知仍使用这台设备的真实系统权限；不会因为备份写着要提醒就伪造授权。")
                    BackupExportButton(title: "先导出本机当前数据")
                }
                Section {
                    MoneySummary(summary: CostCalculator.summary(envelope.subscriptions, preferences: envelope.preferences, today: LocalDate(date: Date())))
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                } header: { Text("备份内容预览") }
                Section { Button(restoring ? "正在恢复…" : "替换本机数据", role: .destructive) { confirm = true }.accessibilityIdentifier("confirmRestore") }
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("恢复预览").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(restoring) } }
            .disabled(restoring)
            .alert("替换本机全部数据？", isPresented: $confirm) {
                Button("确认替换", role: .destructive) { restore() }; Button("返回检查", role: .cancel) {}
            } message: { Text("将用备份中的 \(envelope.subscriptions.count) 条记录替换本机数据，请确认已保留需要的备份。") }
            .alert("恢复完成", isPresented: $success) { Button("完成") { dismiss() } } message: { Text("数据已恢复，提醒状态已按当前系统权限重新核对。可到提醒中心检查。") }
            .alert("恢复未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(error ?? "") }
            .interactiveDismissDisabled(restoring)
        }
    }
    private func restore() {
        restoring = true
        Task {
            do { try await DataProtectionService.restore(backup, repository: repository, notifications: notifications); success = true }
            catch { self.error = error.localizedDescription }
            restoring = false
        }
    }
}
