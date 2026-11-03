import SwiftUI
import UniformTypeIdentifiers

struct SharePNG: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }.suggestedFileName("订阅猫分享.png")
    }
}

struct SharePreviewView: View {
    @Environment(WalletRepository.self) var repo
    @State private var options = ShareOptions()
    @State private var imageData: Data?
    @State private var error: String?
    var snapshot: ShareSnapshot? { ShareSnapshot.make(records: repo.records, preferences: repo.preferences, today: LocalDate(date: Date()), options: options) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let snapshot {
                    Text("分享前，选好你想公开的内容。").font(.subheadline).foregroundStyle(Theme.secondary)
                    VStack {
                        Toggle("显示金额", isOn: $options.showsAmounts).accessibilityIdentifier("shareAmounts")
                        Toggle("显示分类", isOn: $options.showsCategories).accessibilityIdentifier("shareCategories")
                        Toggle("显示服务图标墙", isOn: $options.showsServices).accessibilityIdentifier("shareServices")
                    }.tint(Theme.accent)
                    Text("图标墙展示名称缩写与名称，最多展开 4 项。套餐、单项金额、日期、来源人和备注不会加入海报。").font(.caption).foregroundStyle(Theme.secondary)
                    if options.showsServices { Text("服务名称会公开，请确认名称中没有个人信息。").font(.caption).foregroundStyle(Theme.warning) }
                    if let imageData, let image = UIImage(data: imageData) {
                        Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("分享海报预览：当前持有 \(snapshot.held) 项；" + (options.showsAmounts ? "显示金额；" : "金额已隐藏；") + (options.showsCategories ? "显示分类；" : "分类已隐藏；") + (options.showsServices ? "显示服务名称" : "服务名称已隐藏")).accessibilityIdentifier("sharePosterPreview")
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)).shadow(color: .black.opacity(0.08), radius: 14, y: 6)
                        ShareLink(item: SharePNG(data: imageData), preview: SharePreview("订阅猫", image: Image(uiImage: image))) {
                            Label("分享图片", systemImage: "square.and.arrow.up").font(.headline).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 54).background(Theme.action, in: Capsule())
                        }.buttonStyle(PressScale()).accessibilityIdentifier("shareImage")
                    }
                    if let error { Text(error).foregroundStyle(Theme.destructive) }
                    Text("1080 × 1440 PNG · 仅分享图片，取消不改动钱包。").font(.caption).foregroundStyle(Theme.secondary)
                } else {
                    ContentUnavailableView("还没有当前持有的会员", systemImage: "wallet.pass", description: Text("添加会员后再来生成分享图。"))
                }
            }.padding(20)
        }.background(Theme.background).toolbar(.visible, for: .navigationBar).navigationTitle("分享预览").navigationBarTitleDisplayMode(.inline)
        .onChange(of: snapshot, initial: true) { _, value in
            // Invalidate the previous image synchronously when privacy changes.
            imageData = nil; error = nil
            guard let value else { return }
            do { imageData = try ShareImageRenderer.png(value) } catch { self.error = error.localizedDescription }
        }
    }
}
