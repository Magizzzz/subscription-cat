import SwiftUI
import UniformTypeIdentifiers

struct JSONBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= BackupCodec.maxBytes else { throw WalletError.invalid("文件为空或超过 10MB。") }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct BackupExportButton: View {
    @Environment(WalletRepository.self) private var repository
    var title = "导出备份"
    @State private var privacy = false
    @State private var exporter = false
    @State private var document: JSONBackupDocument?
    @State private var message: String?
    var body: some View {
        Button(title) { privacy = true }.accessibilityIdentifier("exportBackup")
            .alert("备份包含个人记录", isPresented: $privacy) {
                Button("继续导出") { prepare() }
                Button("取消", role: .cancel) {}
            } message: { Text("文件包含会员名称、金额、备注和体检草稿，请妥善保存。建议保存在你控制的位置。") }
            .fileExporter(isPresented: $exporter, document: document, contentType: .json, defaultFilename: "订阅猫备份-\(LocalDate(date: Date()).description)") { result in
                switch result {
                case .success:
                    do {
                        var p = repository.preferences; p.lastBackupExportedAt = Date()
                        try repository.savePreferences(p)
                        message = "备份已导出，请妥善保管文件。"
                    } catch { message = "文件已导出，但未能保存上次备份时间：\(error.localizedDescription)" }
                case .failure(let error):
                    if !Self.isCancellation(error) { message = "备份未导出：\(error.localizedDescription)" }
                }
                document = nil
            }
            .alert("备份导出", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(message ?? "") }
    }
    private func prepare() {
        do {
            document = JSONBackupDocument(data: try BackupCodec.encode(records: repository.records, preferences: repository.preferences, checkup: repository.checkup))
            exporter = true
        } catch { message = error.localizedDescription }
    }
    static func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
    }
}
