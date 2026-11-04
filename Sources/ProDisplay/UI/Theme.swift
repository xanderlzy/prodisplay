import AppKit
import SwiftUI

enum Theme {
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let quick = Animation.spring(response: 0.22, dampingFraction: 0.9)

    static let panelWidth: CGFloat = 300
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 12
    static let rowRadius: CGFloat = 8
}

extension Color {
    // Plain black/white rather than system label colours: the menu bar panel applies
    // vibrancy to label colours, which turns white fills grey.
    /// Primary text and fills: black in light mode, white in dark mode.
    static let ink = Color(nsColor: .monochrome(dark: .white, light: .black))
    /// The opposite of `ink`, for text on filled (selected) rows.
    static let inkInverse = Color(nsColor: .monochrome(dark: .black, light: .white))
    static let muted = ink.opacity(0.5)
    static let hairline = ink.opacity(0.1)
    static let wash = ink.opacity(0.08)
}

private extension NSColor {
    static func monochrome(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
                .map { [.darkAqua, .vibrantDark].contains($0) } == true ? dark : light
        }
    }
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Color.muted)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color.hairline).frame(height: 1)
    }
}

/// Monochrome button: filled (ink) or quiet (outlined).
struct MonoButtonStyle: ButtonStyle {
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .foregroundStyle(filled ? Color.inkInverse : Color.ink)
            .background {
                RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                    .fill(filled ? Color.ink : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                            .strokeBorder(filled ? Color.clear : Color.hairline)
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Small text button that brightens on hover.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietLabel(configuration: configuration)
    }

    private struct QuietLabel: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12))
                .foregroundStyle(hovering ? Color.ink : Color.muted)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .onHover { h in withAnimation(Theme.quick) { hovering = h } }
                .contentShape(Rectangle())
        }
    }
}
