import SwiftUI

/// First-launch introduction. Shown once; skipped for UI tests.
struct WelcomeView: View {
    let done: () -> Void
    @State private var page = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    private let pages: [(String, String)] = [
        ("你好，\n我是订阅猫", "帮你看清每一份付费\n过更轻松的数字生活"),
        ("续费之前\n先提醒你", "按北京时间提前提醒\n不再为忘记取消的会员买单"),
        ("只存在\n这台手机里", "无需登录，不连网也能用\n可随时导出备份")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                if page < pages.count - 1 { Button("跳过", action: done).font(.subheadline).foregroundStyle(Theme.secondary).frame(minHeight: 44) }
            }.frame(height: 44)
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 0) {
                        Group {
                            switch i {
                            case 0: CatLayeredArt()
                            case 1: ReminderArt()
                            default: AppLogo(size: 150).shadow(color: Theme.action.opacity(0.2), radius: 24, y: 10)
                            }
                        }.frame(maxWidth: .infinity).frame(height: typeSize.isAccessibilitySize ? 220 : 330)
                            .scaleEffect(typeSize.isAccessibilitySize ? 0.7 : 1)
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 20) }
                        Text(pages[i].0).font(.largeTitle.bold()).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        Text(pages[i].1).font(.body).foregroundStyle(Theme.secondary).lineSpacing(4).padding(.top, 14).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 20)
                    }.scrollableWhen(typeSize.isAccessibilitySize).tag(i)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            HStack {
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule().fill(i == page ? Theme.action : Theme.border).frame(width: i == page ? 18 : 6, height: 6)
                    }
                }.animation(.snappy, value: page).accessibilityHidden(true)
                Spacer()
                Button {
                    if page < pages.count - 1 { withAnimation { page += 1 } } else { done() }
                } label: {
                    Image(systemName: page < pages.count - 1 ? "arrow.right" : "checkmark").font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(page < pages.count - 1 ? Theme.text : .white)
                        .frame(width: 56, height: 56)
                        .background(page < pages.count - 1 ? AnyShapeStyle(Theme.fill) : AnyShapeStyle(Theme.actionGradient), in: Circle())
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                }.buttonStyle(PressScale()).accessibilityLabel(page < pages.count - 1 ? "下一页" : "开始使用").accessibilityIdentifier("welcomeNext")
            }.padding(.bottom, 12)
        }.padding(.horizontal, 28).background(Theme.surface.ignoresSafeArea())
    }
}

private struct ReminderArt: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach([("qq_music", "QQ音乐", "3天后"), ("apple_icloud", "iCloud+", "7天后"), ("chatgpt", "ChatGPT", "12天后")], id: \.0) { id, name, when in
                HStack(spacing: 12) {
                    BrandMark(style: BrandStyle.of(id, name: name, category: nil), assetID: id, size: 40)
                    Text(name).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(when).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent).padding(.horizontal, 10).padding(.vertical, 5).background(Theme.soft, in: Capsule())
                }.padding(14).background(Theme.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }.padding(.horizontal, 12).accessibilityHidden(true)
    }
}
