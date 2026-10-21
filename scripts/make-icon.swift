// Renders the Clipster app icon (a glass card with a paperclip) to a 1024px PNG.
// Usage: swift scripts/make-icon.swift <out.png>   (see scripts/make-icon.sh)
import AppKit
import SwiftUI

/// A spiral-style paperclip in a 2×5 unit box, y pointing down.
struct Paperclip: Shape {
    func path(in rect: CGRect) -> Path {
        let u = min(rect.width / 2, rect.height / 5)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * u, y: rect.minY + y * u) }
        var path = Path()
        path.move(to: p(2, 1.25))
        path.addLine(to: p(2, 4))
        path.addArc(tangent1End: p(2, 5), tangent2End: p(1, 5), radius: u)        // outer bottom bend
        path.addArc(tangent1End: p(0, 5), tangent2End: p(0, 4), radius: u)
        path.addLine(to: p(0, 0.7))
        path.addArc(tangent1End: p(0, 0), tangent2End: p(0.7, 0), radius: 0.7 * u) // top bend
        path.addArc(tangent1End: p(1.4, 0), tangent2End: p(1.4, 0.7), radius: 0.7 * u)
        path.addLine(to: p(1.4, 3.3))
        path.addArc(tangent1End: p(1.4, 3.7), tangent2End: p(1.0, 3.7), radius: 0.4 * u) // inner bend
        path.addArc(tangent1End: p(0.6, 3.7), tangent2End: p(0.6, 3.3), radius: 0.4 * u)
        path.addLine(to: p(0.6, 1.55))
        return path
    }
}

/// Background palettes. Pick one with ICON_PALETTE=<name>.
struct Palette {
    let top: Color, bottom: Color, glow: Color, shadow: Color
    /// Tint of the glass paperclip: its lower edge and inner core.
    var clipTint: Color = .rgb(0xBCCBFF)

    static let all: [String: Palette] = [
        "midnight": Palette(top: .rgb(0x27315A), bottom: .rgb(0x0B0F24), glow: .rgb(0x6F8DFF), shadow: .rgb(0x02040F)),
        "ocean": Palette(top: .rgb(0x4DA2FF), bottom: .rgb(0x1149E0), glow: .rgb(0xBFE0FF), shadow: .rgb(0x0A2A8A)),
        "indigo": Palette(top: .rgb(0x6A5CFF), bottom: .rgb(0x2A1B9E), glow: .rgb(0xC9C2FF), shadow: .rgb(0x140A5C)),
        "graphite": Palette(top: .rgb(0x4A4D55), bottom: .rgb(0x15161A), glow: .rgb(0xFFFFFF), shadow: .rgb(0x000000),
                            clipTint: .rgb(0xA9AEB8)),
    ]
}

extension Color {
    static func rgb(_ hex: Int) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct Icon: View {
    let palette: Palette
    // Apple's macOS icon grid: 824pt squircle centered on a 1024pt canvas.
    let squircle = RoundedRectangle(cornerRadius: 185, style: .continuous)

    var body: some View {
        ZStack {
            background
            // The clip is drawn twice: once behind the card (frosted by the
            // glass) and once in front, masked to outside the card, so it
            // reads as clipped over the card's top edge.
            placedClip
                .blur(radius: 4)
                .opacity(0.9)
            placedCard(card)
            placedClip
                .frame(width: 824, height: 824)   // mask in canvas coordinates
                .mask {
                    ZStack {
                        Rectangle()
                        placedCard(RoundedRectangle(cornerRadius: 72, style: .continuous)
                            .frame(width: 440, height: 540))
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
        }
        .frame(width: 824, height: 824)
        .clipShape(squircle)
        .overlay(squircle.strokeBorder(
            LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05), .white.opacity(0.2)],
                           startPoint: .top, endPoint: .bottom),
            lineWidth: 3))
        .shadow(color: .black.opacity(0.28), radius: 22, y: 14)
        .frame(width: 1024, height: 1024)
    }

    private func placedCard(_ view: some View) -> some View {
        view.rotationEffect(.degrees(-7)).offset(x: -30, y: 72)
    }

    private var placedClip: some View {
        clip.rotationEffect(.degrees(18)).offset(x: 110, y: -150)
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [palette.top, palette.bottom], startPoint: .top, endPoint: .bottom)
            // A single soft light from above, like a studio key light.
            RadialGradient(colors: [palette.glow.opacity(0.55), .clear],
                           center: UnitPoint(x: 0.5, y: -0.05), startRadius: 0, endRadius: 620)
        }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 72, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.12)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.15), .white.opacity(0.4)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 4))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 34) {
                    line(240); line(300); line(190)
                }
                .padding(.top, 190)
                .padding(.leading, 64)
            }
            .frame(width: 440, height: 540)
            .shadow(color: palette.shadow.opacity(0.45), radius: 40, y: 26)
    }

    private func line(_ width: CGFloat) -> some View {
        Capsule().fill(.white.opacity(0.55)).frame(width: width, height: 26)
    }

    private var clip: some View {
        let shape = Paperclip()
        let style = StrokeStyle(lineWidth: 40, lineCap: .round, lineJoin: .round)
        return ZStack {
            // Body of the glass wire.
            shape.stroke(LinearGradient(colors: [.white, palette.clipTint.mix(with: .white, by: 0.4)],
                                        startPoint: .top, endPoint: .bottom), style: style)
            // Tinted core reads as depth through the glass.
            shape.stroke(palette.clipTint.opacity(0.45),
                         style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
            // Specular highlight along one side.
            shape.stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                .offset(x: -8, y: -6)
                .blur(radius: 1.5)
                .mask(shape.stroke(style: style))
        }
        .frame(width: 164, height: 410)
        .shadow(color: palette.shadow.opacity(0.55), radius: 18, x: 6, y: 16)
    }
}

MainActor.assumeIsolated {
    let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
    let renderer = ImageRenderer(content: Icon(palette: Palette.all[ProcessInfo.processInfo.environment["ICON_PALETTE"] ?? "graphite"]!))
    renderer.scale = 1
    guard let tiff = renderer.nsImage?.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        fatalError("render failed")
    }
    try! png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}
