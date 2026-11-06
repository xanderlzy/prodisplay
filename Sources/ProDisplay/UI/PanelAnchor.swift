import AppKit
import SwiftUI

/// Keeps the menu bar panel's window the same height as its content, top edge fixed.
///
/// The MenuBarExtra window grows with its content but doesn't shrink back. After a section
/// collapses, the shorter content sits centred in the old, taller (and invisible) window, so the
/// panel looks like it has slid down the screen. This resizes the window to the content's height
/// and keeps the top edge where macOS placed it under the menu bar.
struct PanelAnchor: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> AnchorView { AnchorView() }

    func updateNSView(_ view: AnchorView, context: Context) {
        view.fit(height: height)
    }

    final class AnchorView: NSView {
        private var height: CGFloat = 0
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observer.map(NotificationCenter.default.removeObserver)
            observer = nil
            guard let window else { return }
            // macOS may restore the old, taller size when it reopens the panel.
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            }
            apply()
        }

        func fit(height: CGFloat) {
            self.height = height
            // After SwiftUI finishes this layout pass.
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        private func apply() {
            guard let window, height > 1 else { return }
            let frame = window.frame
            let target = height.rounded(.up)
            guard abs(frame.height - target) > 0.5 else { return }
            window.setFrame(
                NSRect(x: frame.minX, y: frame.maxY - target, width: frame.width, height: target),
                display: true
            )
        }
    }
}
