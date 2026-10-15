import CoreGraphics
import SwiftUI

/// The Geomap mark: a planet circling a center on tilted orbits. Drawn in
/// code so the in-app logo and the generated app icon
/// (scripts/generate-app-icon.swift) share one definition.
enum OrbitLogoDrawing {
    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// Draws into a context whose origin is the top-left (y down), `size` square.
    static func draw(in ctx: CGContext, size: CGFloat, includeBackground: Bool) {
        let u = size / 1024
        let center = CGPoint(x: size / 2, y: size / 2)

        if includeBackground {
            let space = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(
                colorsSpace: space,
                colors: [rgb(0x6B8264), rgb(0x3C4D3D)] as CFArray,
                locations: [0, 1]
            )!
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size, y: size),
                options: []
            )
        }

        // Point on an ellipse (rx, ry) rotated by `tilt`, parameter t.
        func point(rx: CGFloat, ry: CGFloat, tilt: CGFloat, t: CGFloat) -> CGPoint {
            let x = rx * cos(t)
            let y = ry * sin(t)
            return CGPoint(
                x: center.x + x * cos(tilt) - y * sin(tilt),
                y: center.y + x * sin(tilt) + y * cos(tilt)
            )
        }

        func arc(rx: CGFloat, ry: CGFloat, tilt: CGFloat, from t0: CGFloat, to t1: CGFloat, width: CGFloat, color: CGColor) {
            let steps = 120
            ctx.beginPath()
            for i in 0...steps {
                let t = t0 + (t1 - t0) * CGFloat(i) / CGFloat(steps)
                let p = point(rx: rx, ry: ry, tilt: tilt, t: t)
                if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
            }
            ctx.setStrokeColor(color)
            ctx.setLineWidth(width)
            ctx.setLineCap(.round)
            ctx.strokePath()
        }

        let deg = CGFloat.pi / 180
        let ring1 = (rx: 350 * u, ry: 150 * u, tilt: -28 * deg)
        let ring2 = (rx: 310 * u, ry: 115 * u, tilt: 42 * deg)
        let cream = rgb(0xF3EFE2)
        let sage = rgb(0x9DB39C)

        // Back halves (behind the center).
        arc(rx: ring2.rx, ry: ring2.ry, tilt: ring2.tilt, from: .pi, to: 2 * .pi, width: 16 * u, color: sage)
        arc(rx: ring1.rx, ry: ring1.ry, tilt: ring1.tilt, from: .pi, to: 2 * .pi, width: 30 * u, color: cream)

        // Center body.
        let r = 120 * u
        ctx.setFillColor(rgb(0xC47B56))
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        ctx.setFillColor(rgb(0xE0A07C, 0.7))
        let h = 46 * u
        ctx.fillEllipse(in: CGRect(x: center.x - r * 0.55, y: center.y - r * 0.6, width: h, height: h * 0.8))

        // Front halves (in front of the center).
        arc(rx: ring2.rx, ry: ring2.ry, tilt: ring2.tilt, from: 0, to: .pi, width: 16 * u, color: sage)
        arc(rx: ring1.rx, ry: ring1.ry, tilt: ring1.tilt, from: 0, to: .pi, width: 30 * u, color: cream)

        // The orbiting planet, on the front of the main ring.
        let p = point(rx: ring1.rx, ry: ring1.ry, tilt: ring1.tilt, t: 0.62 * .pi)
        let pr = 58 * u
        ctx.setFillColor(cream)
        ctx.fillEllipse(in: CGRect(x: p.x - pr - 10 * u, y: p.y - pr - 10 * u, width: 2 * (pr + 10 * u), height: 2 * (pr + 10 * u)))
        ctx.setFillColor(rgb(0xF08A2E))
        ctx.fillEllipse(in: CGRect(x: p.x - pr, y: p.y - pr, width: 2 * pr, height: 2 * pr))
    }
}

struct OrbitLogo: View {
    var size: CGFloat = 96

    var body: some View {
        Canvas { context, canvasSize in
            context.withCGContext { cg in
                OrbitLogoDrawing.draw(in: cg, size: min(canvasSize.width, canvasSize.height), includeBackground: true)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
        .accessibilityLabel("Geomap")
    }
}
