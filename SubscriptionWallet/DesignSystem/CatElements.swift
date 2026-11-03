import SwiftUI

/// The 订阅猫 logo artwork (designer bitmap, rounded corners baked in).
struct AppLogo: View {
    var size: CGFloat = 64
    var body: some View {
        Image("AppLogoImage").resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: Theme.action.opacity(0.18), radius: size * 0.12, y: size * 0.06)
            .accessibilityHidden(true)
    }
}

/// Two soft, rounded cat ears sitting on the top edge of a card.
struct CatEars: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        func ear(_ x0: CGFloat, _ tip: CGFloat, _ x1: CGFloat) {
            let w = r.width, h = r.height
            p.move(to: CGPoint(x: r.minX + w * x0, y: r.maxY))
            p.addQuadCurve(to: CGPoint(x: r.minX + w * (tip - 0.035), y: r.minY + h * 0.12), control: CGPoint(x: r.minX + w * (x0 + 0.03), y: r.minY + h * 0.35))
            p.addQuadCurve(to: CGPoint(x: r.minX + w * (tip + 0.05), y: r.minY + h * 0.10), control: CGPoint(x: r.minX + w * (tip + 0.005), y: r.minY - h * 0.08))
            p.addQuadCurve(to: CGPoint(x: r.minX + w * x1, y: r.maxY), control: CGPoint(x: r.minX + w * (x1 - 0.02), y: r.minY + h * 0.45))
            p.closeSubpath()
        }
        ear(0.02, 0.16, 0.40)
        ear(0.60, 0.80, 0.98)
        return p
    }
}

/// Head silhouette (round face + two ears) as ONE path, so translucent fills don't double up.
struct CatHead: Shape {
    func path(in r: CGRect) -> Path {
        let earH = r.height * 0.34
        var p = Path(ellipseIn: CGRect(x: r.minX, y: r.minY + earH * 0.6, width: r.width, height: r.height - earH * 0.6))
        let ear = CGSize(width: r.width * 0.30, height: earH * 1.25)
        for (x, angle) in [(r.minX + r.width * 0.08, -16.0), (r.maxX - r.width * 0.08 - ear.width, 16.0)] {
            let rect = CGRect(x: x, y: r.minY, width: ear.width, height: ear.height)
            let t = CGAffineTransform(translationX: rect.midX, y: rect.maxY).rotated(by: angle * .pi / 180).translatedBy(x: -rect.midX, y: -rect.maxY)
            p.addPath(CatEar().path(in: rect).applying(t))
        }
        return p
    }
}

/// One rounded ear.
struct CatEar: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.midX - r.width * 0.12, y: r.minY + r.height * 0.08), control: CGPoint(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.30))
        p.addQuadCurve(to: CGPoint(x: r.midX + r.width * 0.12, y: r.minY + r.height * 0.08), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.06))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.maxX - r.width * 0.12, y: r.minY + r.height * 0.30))
        p.closeSubpath()
        return p
    }
}

/// A slender curled tail; stroke it.
struct CatTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.maxX * 0.82, y: r.minY + r.height * 0.28),
                   control1: CGPoint(x: r.width * 0.55, y: r.maxY),
                   control2: CGPoint(x: r.maxX * 0.98, y: r.minY + r.height * 0.70))
        p.addQuadCurve(to: CGPoint(x: r.maxX * 0.58, y: r.minY + r.height * 0.10), control: CGPoint(x: r.maxX * 0.72, y: r.minY - r.height * 0.06))
        return p
    }
}

extension View {
    /// Little paw prints pop out from the view whenever `trigger` changes.
    func pawBurst<T: Equatable>(trigger: T, color: Color = Theme.accent, count: Int = 6) -> some View {
        overlay { PawBurst(trigger: trigger, color: color, count: count).allowsHitTesting(false) }
    }
}
private struct PawBurst<T: Equatable>: View {
    let trigger: T
    let color: Color
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if !reduceMotion {
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    let angle = Double(i) / Double(count) * 2 * .pi + 0.4
                    Image(systemName: "pawprint.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
                        .keyframeAnimator(initialValue: PawFrame(), trigger: trigger) { content, f in
                            content.rotationEffect(.radians(angle + .pi / 2)).scaleEffect(f.scale)
                                .offset(x: cos(angle) * f.distance, y: sin(angle) * f.distance).opacity(f.opacity)
                        } keyframes: { _ in
                            KeyframeTrack(\.distance) { LinearKeyframe(0, duration: 0.01); SpringKeyframe(54, duration: 0.55, spring: .snappy) }
                            KeyframeTrack(\.scale) { LinearKeyframe(0.2, duration: 0.01); SpringKeyframe(1.0, duration: 0.3, spring: .bouncy); LinearKeyframe(0.6, duration: 0.3) }
                            KeyframeTrack(\.opacity) { LinearKeyframe(1, duration: 0.01); LinearKeyframe(1, duration: 0.35); LinearKeyframe(0, duration: 0.3) }
                        }
                }
            }
        }
    }
}
private struct PawFrame { var distance: CGFloat = 0; var scale: CGFloat = 0; var opacity: Double = 0 }

/// Frosted layered cards whose top layer has ears and eyes — the welcome illustration.
struct CatLayeredArt: View {
    @State private var float = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private func layer(_ i: Int) -> some View {
        let t = CGFloat(i)
        return RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(LinearGradient(colors: [Color.white.opacity(0.96), Theme.fixed(i == 0 ? 0xB9A6FF : 0xECE6FF).opacity(i == 0 ? 0.95 : 0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(.white, lineWidth: 1))
            .frame(width: 170, height: 170)
            .rotationEffect(.degrees(45)).scaleEffect(x: 1, y: 0.56)
            .offset(y: 70 - t * 36 - (float ? 5 * t : 0))
            .shadow(color: Theme.fixed(0x7150F0).opacity(i == 0 ? 0.28 : 0.08), radius: 18, y: 12)
    }
    var body: some View {
        let lift: CGFloat = float ? 15 : 0
        ZStack {
            ForEach(0..<3) { layer($0) }
            // Ears tuck behind the top layer so they grow out of its upper edges.
            ForEach([-1.0, 1.0], id: \.self) { side in
                CatEar().fill(LinearGradient(colors: [.white, Theme.fixed(0xD9CCFF)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 50, height: 56).rotationEffect(.degrees(side * 24))
                    .offset(x: side * 58, y: -92 - lift)
                    .shadow(color: Theme.fixed(0x7150F0).opacity(0.10), radius: 6, y: 2)
            }
            layer(3)
            HStack(spacing: 22) {
                ForEach(0..<2, id: \.self) { _ in Capsule().fill(Theme.fixed(0x7150F0)).frame(width: 10, height: 20) }
            }.offset(y: -38 - lift)
        }
        .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { float = true } } }
        .accessibilityHidden(true)
    }
}
