import AppKit
import SwiftUI

/// Thick pill slider. 0...1 is normal brightness; 1...2 (when XDR is available)
/// is the extended range, drawn past a thin tick with a soft glow.
struct BrightnessSlider: View {
    let value: Double
    let xdrAvailable: Bool
    let boostFactor: (Double) -> Double
    let onChange: (Double) -> Void
    let onEditingChanged: (Bool) -> Void

    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let height: CGFloat = 24
    private var sdrShare: CGFloat { xdrAvailable ? 0.72 : 1 }
    private var glow: Double { max(0, min(value - 1, 1)) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: value > 1 ? "sun.max.fill" : "sun.max")
                    .font(.system(size: 12, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                if value > 1 {
                    Text("XDR")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.6)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(Color.ink.opacity(0.6)))
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
                Spacer()
                Text(readout)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: value))
            }
            .foregroundStyle(Color.ink)
            .animation(Theme.quick, value: value > 1)

            GeometryReader { geo in
                let width = geo.size.width
                let fill = max(height, position(for: value) * width)

                ZStack(alignment: .leading) {
                    // Glow sits behind the track so clipping doesn't cut it off.
                    Capsule()
                        .fill(Color.ink)
                        .frame(width: fill)
                        .blur(radius: 6 + 10 * glow)
                        .opacity(0.55 * glow)

                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.wash)
                        if xdrAvailable {
                            Rectangle()
                                .fill(Color.wash)
                                .frame(width: width * (1 - sdrShare))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        Capsule().fill(Color.ink).frame(width: fill)
                    }
                    .clipShape(Capsule())

                    if xdrAvailable {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 1, height: height * 0.45)
                            .offset(x: width * sdrShare - 0.5)
                            .blendMode(.difference)
                    }
                }
                .frame(height: height)
                .animation(dragging || reduceMotion ? nil : Theme.spring, value: value)
                .animation(Theme.spring, value: xdrAvailable)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            if !dragging {
                                dragging = true
                                onEditingChanged(true)
                            }
                            update(to: value(for: g.location.x / width))
                        }
                        .onEnded { _ in
                            dragging = false
                            onEditingChanged(false)
                        }
                )
            }
            .frame(height: height)
        }
    }

    private var readout: String {
        value <= 1
            ? "\(Int((value * 100).rounded()))%"
            : "\(Int((boostFactor(value) * 100).rounded()))%"
    }

    private func position(for v: Double) -> CGFloat {
        v <= 1 ? v * sdrShare : sdrShare + (v - 1) * (1 - sdrShare)
    }

    private func value(for x: CGFloat) -> Double {
        let p = min(max(x, 0), 1)
        return p <= sdrShare ? p / sdrShare : 1 + (p - sdrShare) / (1 - sdrShare)
    }

    private func update(to newValue: Double) {
        var v = newValue
        if xdrAvailable, abs(v - 1) < 0.025 { v = 1 } // gentle detent at 100%
        if (value <= 1) != (v <= 1) || (v == 1 && value != 1) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        onChange(v)
    }
}
