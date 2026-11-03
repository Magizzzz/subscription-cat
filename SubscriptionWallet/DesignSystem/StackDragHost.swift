import SwiftUI
import UIKit

/// 让“长按后上下拖”和页面滚动共存：在最近的 UIScrollView 上挂一个系统长按识别器。
/// 手指一动就是滚动（长按识别失败）；按住不动约 0.35 秒才进入拖动，此时暂停滚动。
/// 放在叠卡的 `.background` 里，用它自己的窗口坐标算出按在第几张。
struct StackDragHost: UIViewRepresentable {
    var isEnabled: Bool
    var count: Int
    /// 每张卡露出的高度；按在最后一张及其下面都算最后一张。
    var peek: CGFloat
    var onBegan: (Int) -> Void
    var onMoved: (CGFloat) -> Void
    var onEnded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> HostView {
        let view = HostView(); view.isUserInteractionEnabled = false; view.coordinator = context.coordinator; return view
    }
    func updateUIView(_ view: HostView, context: Context) { context.coordinator.parent = self; view.coordinator = context.coordinator; view.attachIfNeeded() }

    final class HostView: UIView {
        weak var coordinator: Coordinator?
        fileprivate weak var scroll: UIScrollView?
        private var recognizer: UILongPressGestureRecognizer?
        var windowFrame: CGRect? { window == nil ? nil : convert(bounds, to: nil) }
        override func didMoveToWindow() { super.didMoveToWindow(); window == nil ? detach() : attachIfNeeded() }
        func attachIfNeeded() {
            guard recognizer == nil, window != nil, let coordinator else { return }
            var view = superview
            while let current = view, !(current is UIScrollView) { view = current.superview }
            guard let scrollView = view as? UIScrollView else { return }
            let press = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.handle(_:)))
            press.minimumPressDuration = 0.35; press.cancelsTouchesInView = false; press.delegate = coordinator
            scrollView.addGestureRecognizer(press); scroll = scrollView; recognizer = press; coordinator.host = self
        }
        func detach() { if let recognizer { scroll?.removeGestureRecognizer(recognizer) }; recognizer = nil; scroll?.isScrollEnabled = true }
        deinit { detach() }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: StackDragHost
        weak var host: HostView?
        private var active = false
        private var startY: CGFloat = 0
        init(_ parent: StackDragHost) { self.parent = parent }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard parent.isEnabled, parent.count > 1, let frame = host?.windowFrame else { return false }
            return frame.contains(gesture.location(in: nil))
        }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc func handle(_ gesture: UILongPressGestureRecognizer) {
            let point = gesture.location(in: nil)
            switch gesture.state {
            case .began:
                guard let host, let frame = host.windowFrame else { return }
                active = true; startY = point.y; host.scroll?.isScrollEnabled = false
                parent.onBegan(min(max(Int((point.y - frame.minY) / parent.peek), 0), parent.count - 1))
            case .changed:
                if active { parent.onMoved(point.y - startY) }
            case .ended, .cancelled, .failed:
                guard active else { return }
                active = false; host?.scroll?.isScrollEnabled = true; parent.onEnded()
            default: break
            }
        }
    }
}
