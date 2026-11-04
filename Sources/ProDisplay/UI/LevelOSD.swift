import AppKit
import Observation
import SwiftUI

/// Minimal on-screen indicator for brightness and volume key presses; replaces the macOS one.
@MainActor
final class LevelOSD {
    @Observable
    final class State {
        var symbol = "sun.max"
        /// 0...1, or up to 2 for brightness in the XDR range.
        var value = 1.0
        var percent = 100
        /// Shows the 100% tick and reserves the XDR part of the bar.
        var showsXDRRange = true
        var visible = false
    }

    private let state = State()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func showBrightness(value: Double, xdrAvailable: Bool, percent: Int, on screen: NSScreen?) {
        show(symbol: value > 1 ? "sun.max.fill" : "sun.max", value: value, percent: percent,
             showsXDRRange: xdrAvailable, on: screen)
    }

    func showVolume(level: Double, muted: Bool, on screen: NSScreen?) {
        let symbol = switch muted ? 0 : level {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
        show(symbol: symbol, value: muted ? 0 : level, percent: muted ? 0 : Int((level * 100).rounded()),
             showsXDRRange: false, on: screen)
    }

    private func show(symbol: String, value: Double, percent: Int, showsXDRRange: Bool, on screen: NSScreen?) {
        let panel = panel ?? makePanel()
        if let screen = screen ?? NSScreen.main {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: screen.frame.maxX - size.width - 4,
                y: screen.visibleFrame.maxY - size.height + 18
            ))
        }
        panel.orderFrontRegardless()

        withAnimation(Theme.spring) {
            state.symbol = symbol
            state.value = value
            state.percent = percent
            state.showsXDRRange = showsXDRRange
            state.visible = true
        }

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.state.visible = false }
            try? await Task.sleep(for: .seconds(0.35))
            guard !Task.isCancelled else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let hosting = NSHostingView(rootView: OSDView(state: state))
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
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel
        return panel
    }
}

private struct OSDView: View {
    let state: LevelOSD.State

    private let barWidth: CGFloat = 150
    private var sdrShare: CGFloat { state.showsXDRRange ? 0.72 : 1 }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.symbol)
                .font(.system(size: 14, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22) // speaker symbols vary in width

            ZStack(alignment: .leading) {
                Capsule().fill(Color.wash)
                Capsule()
                    .fill(Color.ink)
                    .frame(width: max(6, position * barWidth))
                    .shadow(color: Color.ink.opacity(0.5 * glow), radius: 6 * glow)
                if state.showsXDRRange {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 1, height: 4)
                        .offset(x: barWidth * sdrShare - 0.5)
                        .blendMode(.difference)
                }
            }
            .frame(width: barWidth, height: 6)

            Text("\(state.percent)%")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(state.percent)))
                .frame(width: 40, alignment: .trailing)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.hairline))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
        .padding(24) // room for the shadow
        .scaleEffect(state.visible ? 1 : 0.92)
        .opacity(state.visible ? 1 : 0)
    }

    private var position: CGFloat {
        state.value <= 1 ? state.value * sdrShare : sdrShare + (state.value - 1) * (1 - sdrShare)
    }

    private var glow: Double { max(0, min(state.value - 1, 1)) }
}
