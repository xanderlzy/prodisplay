import AppKit
import Observation
import SwiftUI

/// "Keep this resolution?" prompt shown on an external display after its mode changes.
/// If nobody answers (for example because the monitor can't show the new mode and went
/// black), the change is reverted when the countdown ends.
@MainActor
final class ResolutionConfirmPanel {
    @Observable
    final class State {
        var secondsLeft = 15
        var visible = false
    }

    static let timeout = 15

    private let state = State()
    private var panel: NSPanel?
    private var countdown: Task<Void, Never>?
    private var onKeep: (() -> Void)?
    private var onRevert: (() -> Void)?

    var isShowing: Bool { countdown != nil }

    func show(on display: CGDirectDisplayID, keep: @escaping () -> Void, revert: @escaping () -> Void) {
        onKeep = keep
        onRevert = revert
        state.secondsLeft = Self.timeout

        countdown?.cancel()
        countdown = Task { [weak self] in
            // Screen frames update a moment after the mode change; place the panel after that.
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, !Task.isCancelled else { return }
            self.present(on: display)
            while self.state.secondsLeft > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                withAnimation(Theme.quick) { self.state.secondsLeft -= 1 }
            }
            self.finish(keep: false)
        }
    }

    /// Hides the prompt without running either action (e.g. the display was unplugged).
    func cancel() {
        countdown?.cancel()
        countdown = nil
        onKeep = nil
        onRevert = nil
        hide()
    }

    private func finish(keep: Bool) {
        let action = keep ? onKeep : onRevert
        cancel()
        action?()
    }

    private func present(on display: CGDirectDisplayID) {
        let panel = panel ?? makePanel()
        if let screen = DisplayManager.screen(for: display) ?? NSScreen.main {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2,
                                         y: screen.frame.midY - size.height / 2))
        }
        panel.orderFrontRegardless()
        withAnimation(Theme.spring) { state.visible = true }
    }

    private func hide() {
        guard let panel else { return }
        withAnimation(.easeOut(duration: 0.2)) { state.visible = false }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            if !self.isShowing { panel.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let view = ConfirmView(
            state: state,
            keep: { [weak self] in self?.finish(keep: true) },
            revert: { [weak self] in self?.finish(keep: false) }
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
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel
        return panel
    }
}

private struct ConfirmView: View {
    let state: ResolutionConfirmPanel.State
    let keep: () -> Void
    let revert: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("Keep this resolution?")
                    .font(.system(size: 13, weight: .semibold))
                Text("Reverting in \(state.secondsLeft) s")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Color.muted)
                    .contentTransition(.numericText(countsDown: true))
            }
            HStack(spacing: 8) {
                Button("Revert", action: revert)
                    .buttonStyle(MonoButtonStyle())
                Button("Keep", action: keep)
                    .buttonStyle(MonoButtonStyle(filled: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .foregroundStyle(Color.ink)
        .tint(Color.ink)
        .frame(width: 220)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .padding(30) // room for the shadow
        .scaleEffect(state.visible ? 1 : 0.94)
        .opacity(state.visible ? 1 : 0)
    }
}
