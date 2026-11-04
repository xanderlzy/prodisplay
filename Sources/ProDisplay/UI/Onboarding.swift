import AppKit
import SwiftUI

/// First-launch welcome window.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onFinish: (() -> Void)?

    func show(model: AppModel, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingView { [weak self] in self?.window?.close() }
            .environment(model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closing the window by any means counts as finishing, so it never nags.
    func windowWillClose(_ notification: Notification) {
        window = nil
        onFinish?()
        onFinish = nil
    }
}

private struct OnboardingView: View {
    let onDone: () -> Void

    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var forward = true

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case 0: WelcomeStep().transition(slide)
                case 1: KeysStep().transition(slide)
                default: DoneStep().transition(slide)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            footer
        }
        .padding(.horizontal, 36)
        .padding(.top, 44)
        .padding(.bottom, 28)
        .frame(width: 440, height: 520)
        .background(.background)
        .tint(Color.ink)
    }

    private var slide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Capsule()
                        .fill(i == step ? Color.ink : Color.hairline)
                        .frame(width: i == step ? 18 : 6, height: 6)
                }
            }
            .animation(Theme.spring, value: step)

            HStack(spacing: 8) {
                if step > 0 {
                    Button("Back") { go(to: step - 1) }
                        .buttonStyle(MonoButtonStyle())
                        .transition(.opacity)
                }
                Button(primaryTitle) { step == 2 ? onDone() : go(to: step + 1) }
                    .buttonStyle(MonoButtonStyle(filled: true))
                    .keyboardShortcut(.defaultAction)
            }
            .animation(Theme.spring, value: step)
        }
    }

    private var primaryTitle: String {
        switch step {
        case 1: model.keyAccessGranted ? "Continue" : "Skip for Now"
        case 2: "Get Started"
        default: "Continue"
        }
    }

    private func go(to newStep: Int) {
        forward = newStep > step
        withAnimation(Theme.spring) { step = newStep }
    }
}

// MARK: - Steps

private struct StepHeader: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WelcomeStep: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)

            StepHeader(title: "ProDisplay", message: "More from your MacBook Pro display.")

            VStack(alignment: .leading, spacing: 14) {
                Feature(symbol: "sun.max", title: "Brighter than 100%", detail: "Use the XDR panel's extra headroom every day.")
                Feature(symbol: "rectangle.expand.diagonal", title: "Every resolution", detail: "Pick from all the sizes macOS keeps hidden.")
                Feature(symbol: "keyboard", title: "Brightness and volume keys", detail: "F1, F2 and F10–F12, with ProDisplay's indicator.")
            }
            .padding(.top, 4)
        }
        .onAppear { withAnimation(Theme.spring.delay(0.1)) { appeared = true } }
    }
}

private struct Feature: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 34)
                .background(Color.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Color.muted)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct KeysStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 28) {
            HStack(spacing: 12) {
                Keycap(label: "F1", symbol: "sun.min")
                Keycap(label: "F2", symbol: "sun.max", lit: model.keyAccessGranted)
            }
            .padding(.top, 12)

            StepHeader(
                title: "Let the keys go further",
                message: "ProDisplay needs Accessibility access to read the brightness and volume keys. It only reacts to those keys."
            )

            ZStack {
                if model.keyAccessGranted {
                    Label("Access granted", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else {
                    Button("Open Accessibility Settings", action: model.openAccessibilitySettings)
                        .buttonStyle(MonoButtonStyle())
                        .frame(width: 240)
                        .transition(.opacity)
                }
            }
            .animation(Theme.spring, value: model.keyAccessGranted)
        }
    }
}

private struct Keycap: View {
    let label: String
    let symbol: String
    var lit = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 20, weight: .medium))
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.muted)
        }
        .frame(width: 72, height: 72)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.wash)
                .shadow(color: Color.ink.opacity(lit ? 0.35 : 0), radius: 14)
        )
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.hairline))
        .animation(Theme.spring, value: lit)
    }
}

private struct DoneStep: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = false
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 28) {
            // A sketch of the menu bar with ProDisplay's icon.
            HStack(spacing: 14) {
                Spacer()
                Image(systemName: "wifi").foregroundStyle(Color.muted)
                Image(systemName: "sun.max.fill")
                    .padding(6)
                    .background(Circle().fill(Color.wash).scaleEffect(pulse ? 1.25 : 1))
                Image(systemName: "battery.75percent").foregroundStyle(Color.muted)
                Text(verbatim: "9:41").foregroundStyle(Color.muted)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Color.wash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.top, 12)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
            }

            StepHeader(
                title: "You're all set",
                message: "ProDisplay lives in the menu bar. Click the sun for brightness, resolution and refresh rate."
            )

            Toggle("Open ProDisplay at login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 13))
                .onAppear { launchAtLogin = model.launchAtLogin }
                .onChange(of: launchAtLogin) { _, on in model.launchAtLogin = on }
        }
    }
}
