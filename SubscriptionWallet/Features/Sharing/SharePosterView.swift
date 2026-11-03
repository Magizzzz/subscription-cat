import SwiftUI
import UIKit

struct SharePosterView: View {
    let snapshot: ShareSnapshot
    private let green = Color(red: 0.42, green: 0.27, blue: 0.90)
    private let ink = Color(red: 0.10, green: 0.09, blue: 0.15)
    private var month: String { let d = LocalDate(date: Date()); return String(format: "%04d.%02d", d.year, d.month) }
    private func trim(_ s: String) -> String { s.hasSuffix(".00") ? String(s.dropLast(3)) : s }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("我的\n数字生活账单").font(.system(size: 21, weight: .bold)).lineSpacing(2)
                Spacer()
                Text(month).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).padding(.top, 4)
            }
            if let monthly = snapshot.monthly {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(trim(monthly)).font(.system(size: 34, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                    Text("/ 月").font(.system(size: 14, weight: .medium))
                }
                if let annual = snapshot.annual {
                    Text("\(trim(annual)) / 年").font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                Text("按当前记录折算，非实际扣款账单").font(.system(size: 8)).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(snapshot.held)").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(green)
                    Text("个当前持有的订阅").font(.system(size: 13, weight: .medium))
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "wallet.pass").font(.system(size: 10, weight: .semibold)).foregroundStyle(green)
                    Text("共 \(snapshot.held) 个订阅 · 自费 \(snapshot.paid) · 联名/赠送 \(snapshot.gifted)" + (snapshot.unknown > 0 ? " · 待确认 \(snapshot.unknown)" : "")).font(.system(size: 9.5, weight: .medium))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: snapshot.categories.count > 4 ? 2 : 1), alignment: .leading, spacing: 6) {
                    ForEach(snapshot.categories) { c in
                        HStack(spacing: 6) {
                            Text(c.label).font(.system(size: 9.5)).lineLimit(1).frame(width: 56, alignment: .leading)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(green.opacity(0.10))
                                    Capsule().fill(green).frame(width: max(4, g.size.width * Double(c.value) / Double(max(snapshot.held, 1))))
                                }
                            }.frame(height: 5)
                            Text("\(c.value) 个").font(.system(size: 9)).foregroundStyle(.secondary).fixedSize()
                        }
                    }
                }
                if !snapshot.services.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(Array(snapshot.services.enumerated()), id: \.offset) { index, name in
                            VStack(spacing: 3) {
                                let id = snapshot.serviceIDs.indices.contains(index) ? snapshot.serviceIDs[index] : nil
                                BrandMark(style: BrandStyle.of(id, name: name, category: nil), assetID: id, size: 26)
                                Text(name).font(.system(size: 8)).lineLimit(1)
                            }.frame(maxWidth: .infinity)
                        }
                    }.padding(.top, 2)
                    if snapshot.omittedServices > 0 { Text("另有 \(snapshot.omittedServices) 项未展开").font(.system(size: 8)).foregroundStyle(.secondary) }
                }
                if !snapshot.notices.isEmpty {
                    Text(snapshot.notices.joined(separator: "；")).font(.system(size: 8)).fixedSize(horizontal: false, vertical: true).foregroundStyle(Color(red: 0.43, green: 0.34, blue: 0.15))
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .topTrailing) { CatEars().fill(.white.opacity(0.92)).frame(width: 52, height: 18).offset(x: -18, y: -15) }
                .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                Text("好的工具，\n让生活更自由。").font(.system(size: 15, weight: .medium, design: .serif)).italic().lineSpacing(3)
                Spacer()
                HStack(spacing: 6) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("订阅猫").font(.system(size: 9.5, weight: .semibold))
                        Text("看清每一份付费").font(.system(size: 7.5)).foregroundStyle(.secondary)
                    }
                    AppLogo(size: 24)
                }
            }
        }
        .padding(18).frame(width: 360, height: 480, alignment: .topLeading)
        .foregroundStyle(ink)
        .background {
            ZStack {
                Color(red: 0.965, green: 0.96, blue: 0.985)
                Circle().fill(Color(red: 0.68, green: 0.58, blue: 1.0).opacity(0.45)).frame(width: 260).blur(radius: 50).offset(x: 120, y: -190)
                Circle().fill(Color(red: 0.86, green: 0.80, blue: 1.0).opacity(0.55)).frame(width: 200).blur(radius: 40).offset(x: -140, y: -120)
                CatTail().stroke(Color(red: 0.86, green: 0.82, blue: 1.0), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 80, height: 90).offset(x: 150, y: 150)
            }
        }
        .environment(\.colorScheme, .light).environment(\.dynamicTypeSize, .medium).environment(\.locale, Locale(identifier: "zh_CN"))
    }
}

@MainActor enum ShareImageRenderer {
    static func png(_ snapshot: ShareSnapshot) throws -> Data {
        let renderer = ImageRenderer(content: SharePosterView(snapshot: snapshot))
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.uiImage, let cg = image.cgImage, cg.width == 1080, cg.height == 1440,
              let data = image.pngData() else { throw WalletError.invalid("分享图生成失败，请重试。") }
        return data
    }
}
