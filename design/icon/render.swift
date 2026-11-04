// Renders the ProDisplay app icon ("Radiance") as a 1024 px PNG.
import AppKit
import SwiftUI

// macOS icon grid: 1024 canvas, 824 body, continuous corners.
let canvas: CGFloat = 1024, body: CGFloat = 824, radius: CGFloat = 185

struct Squircle<Content: View>: View {
    let background: AnyShapeStyle
    @ViewBuilder let content: Content
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(background)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            content
                .frame(width: canvas == 0 ? 0 : 824, height: 824)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 2)
        }
        .frame(width: 824, height: 824)
        .frame(width: canvas, height: canvas)
    }
}

let dark = AnyShapeStyle(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.02)], startPoint: .top, endPoint: .bottom))

// A — Radiance: a sun whose glow spills past its rays.
struct Radiance: View {
    var body: some View {
        Squircle(background: dark) {
            ZStack {
                Circle().fill(.white).frame(width: 520).blur(radius: 110).opacity(0.28)
                ForEach(0..<12) { i in
                    Capsule()
                        .fill(.white)
                        .frame(width: 34, height: i % 2 == 0 ? 120 : 84)
                        .offset(y: -(190 + (i % 2 == 0 ? 60 : 42)))
                        .rotationEffect(.degrees(Double(i) * 30))
                }
                Circle()
                    .fill(RadialGradient(colors: [.white, Color(white: 0.9)], center: .center, startRadius: 0, endRadius: 150))
                    .frame(width: 290)
                    .shadow(color: .white.opacity(0.6), radius: 40)
            }
        }
    }
}

@MainActor func save<V: View>(_ view: V, _ name: String) {
    let r = ImageRenderer(content: view.frame(width: canvas, height: canvas))
    r.scale = 1
    guard let cg = r.cgImage else { print("render failed", name); return }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "/" + name + ".png"))
}

// Usage: swiftc -O render.swift -o render && ./render <output-dir>
MainActor.assumeIsolated {
    save(Radiance(), "AppIcon-1024")
}
print("ok")
