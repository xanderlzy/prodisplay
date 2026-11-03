import AppKit
import SwiftUI

/// Floating "Keep this scaling?" prompt that reverts automatically after a countdown.
@MainActor
final class ConfirmHUD {
    private var panel: NSPanel?
    private var token = UUID()

    func show(size: CustomSize, seconds: Int = 15, onRevert: @escaping () -> Void) {
        dismiss()
        let token = UUID()
        self.token = token
        // Each callback checks the token so a stale countdown can't act after Keep or a newer prompt.
        let view = ConfirmView(
            size: size,
            seconds: seconds,
            onKeep: { [weak self] in
                guard self?.token == token else { return }
                self?.dismiss()
            },
            onRevert: { [weak self] in
                guard let self, self.token == token else { return }
                self.dismiss()
                onRevert()
            }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: f.midX - hosting.fittingSize.width / 2,
                y: f.midY - hosting.fittingSize.height / 2
            ))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func dismiss() {
        token = UUID()
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct ConfirmView: View {
    let size: CustomSize
    let seconds: Int
    let onKeep: () -> Void
    let onRevert: () -> Void

    @State private var remaining = 0
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("Keep this scaling?")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 0) {
                    Text("\(size.label) · reverting in ")
                    Text("\(remaining)")
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    Text("s")
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.muted)
            }
            HStack(spacing: 8) {
                Button("Revert", action: onRevert).buttonStyle(MonoButtonStyle())
                Button("Keep", action: onKeep).buttonStyle(MonoButtonStyle(filled: true))
            }
        }
        .padding(18)
        .frame(width: 264)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .padding(30) // room for the shadow
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .task {
            remaining = seconds
            withAnimation(Theme.spring) { appeared = true }
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                withAnimation(Theme.quick) { remaining -= 1 }
            }
            onRevert()
        }
    }
}
