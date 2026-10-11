import SwiftUI

// The shadow of the moon: the same geometry as DgMoon.shadePath(f) of the designer's dg-moon.js (a 100 x 100 box,
// centre 50, R 48): the terminator, a half ellipse of semi-axis R |cos 2 pi f|, then a big half circle round the dark
// side that reaches beyond the disk. Drawn as short lines (48 steps a half) instead of SVG arcs.
struct MoonShade: Shape {
    var phase: Double

    func path(in rect: CGRect) -> Path {
        let f = WPlan.norm(phase)
        let c = 50.0, r = 48.0, big = 62.0
        let k = cos(2 * Double.pi * f)
        // drawn, not true: the thin crescents are made thicker so that the day after a new moon (and the 14th day) can be told from the new (full) one; same as WidgetMoon.seen / dg-moon.js
        let u = 1 - min(1, abs(k))
        let thick: Double = pow(u, 0.6)
        let bump: Double = 0.07 * exp(-u / 0.06) * (1 - exp(-u / 0.0015))   // the first 5 % a little more visible
        let rx: Double = (1 - (thick + bump)) * r
        let gibbous = k < 0
        let waxing = f < 0.5
        let terminatorRight = waxing ? !gibbous : gibbous
        let bigOnLeft = waxing
        let s = Double(min(rect.width, rect.height)) / 100
        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: Double(rect.minX) + x * s, y: Double(rect.minY) + y * s)
        }
        let n = 48
        var p = Path()
        p.move(to: pt(c, c - r))
        for i in 1...n {
            let a = Double.pi * Double(i) / Double(n)
            p.addLine(to: pt(c + rx * sin(a) * (terminatorRight ? 1 : -1), c - r * cos(a)))
        }
        p.addLine(to: pt(c, c + big))
        for i in 1...n {
            let a = Double.pi * Double(i) / Double(n)
            p.addLine(to: pt(c + big * sin(a) * (bigOnLeft ? -1 : 1), c + big * cos(a)))
        }
        p.closeSubpath()
        return p
    }
}

// The moon: the NASA photo with the shade of the phase, edge darkening and a thin rim (a port of Android's WidgetMoon.java).
// The shade is EARTHSHINE, not a black hole: the night side is the same moon, dim and blue-grey, its seas still readable
// (a wide penumbra 46 % under a sharp edge 70 %, 60 % when small). On a dark card every moon has a halo that fades to nothing.
// `disc` is the disc's diameter. The big moon's frame is disc / discShare (the halo's room, as on Android: rows under the moon are
// moved in by the margin, so their left edge is the disc's); a `mini` moon (a list row, a calendar cell) fills its frame, has a
// neutral rim for both themes and no halo. `south` turns it by 180 degrees.
struct MoonView: View {
    let phase: Double
    let disc: CGFloat
    var south: Bool = false
    var mini: Bool = false
    @Environment(\.colorScheme) private var scheme

    // The share of the frame's side that the disc takes (the rest is the halo's room)
    static let discShare: CGFloat = 0.88

    var body: some View {
        let u: CGFloat = disc / 96                       // points per unit of the 100 x 100 box the geometry is written in
        let box: CGFloat = mini ? disc : disc / MoonView.discShare
        let dark: Bool = scheme == .dark && !mini
        let small: Bool = mini || disc < 50
        let rimWidth: CGFloat = (small ? 1.6 : 0.9) * u
        ZStack {
            if dark {
                halo(box)
            }
            face(u, dark: dark, small: small)
                .frame(width: 100 * u, height: 100 * u)
                .clipShape(Circle().inset(by: 2 * u))
                .overlay(Circle().inset(by: 2.4 * u).stroke(rimColor(dark: dark, small: small), lineWidth: rimWidth))
        }
        .frame(width: box, height: box)
        .rotationEffect(.degrees(south ? 180 : 0))
    }

    // The halo under every moon on a dark card, a bit stronger as the moon fills; it ends exactly at the frame's edge.
    private func halo(_ box: CGFloat) -> some View {
        let lit: Double = (1 - cos(2 * Double.pi * WPlan.norm(phase))) / 2
        let alpha: Double = 0.20 + 0.22 * lit
        let glow: Color = Color.hex(0xE9E4DC, alpha)
        let inner: CGFloat = 47.0 / 48.0 * MoonView.discShare
        let gradient = RadialGradient(
            gradient: Gradient(stops: [
                Gradient.Stop(color: glow, location: 0),
                Gradient.Stop(color: glow, location: inner),
                Gradient.Stop(color: Color.hex(0xE9E4DC, 0), location: 1)
            ]),
            center: .center, startRadius: 0, endRadius: box / 2)
        return Circle().fill(gradient).frame(width: box, height: box)
    }

    private func rimColor(dark: Bool, small: Bool) -> Color {
        if mini { return Color.hex(0x8A9096, 0.60) }
        if dark { return Color.hex(0xE9E4DC, small ? 0.55 : 0.42) }
        return Color.hex(0x2F4A63, 0.30)
    }

    // The photo, the edge darkening and the shade, in the 100-unit box
    private func face(_ u: CGFloat, dark: Bool, small: Bool) -> some View {
        let shade: Color = dark ? Color.hex(0x1B2535) : Color.hex(0x1F2A3C)
        // transparent to 50 %, then a little, then darker at the rim (a small moon keeps its brightness to the rim)
        let edge = RadialGradient(
            gradient: Gradient(stops: [
                Gradient.Stop(color: Color.black.opacity(0), location: 0.5),
                Gradient.Stop(color: Color.black.opacity(small ? 0.06 : 0.14), location: 0.86),
                Gradient.Stop(color: Color.black.opacity(small ? 0.19 : 0.42), location: 1.0)
            ]),
            center: .center, startRadius: 0, endRadius: 48 * u)
        // a blur is lost on a moon of a dozen points (and a calendar has thirty of them): one flat shade of the same weight there
        let blurred: Bool = disc >= 24
        return ZStack {
            Image("moon")
                .resizable()
                .interpolation(.high)
                .brightness(small ? 0.05 : 0)   // at list sizes a little brighter, so it does not read as one more row of text
                .frame(width: 97.2 * u, height: 97.2 * u)
            Circle().fill(edge).frame(width: 96 * u, height: 96 * u)
            if blurred {
                MoonShade(phase: phase).fill(shade).opacity(0.46).blur(radius: 4.5 * u)
                MoonShade(phase: phase).fill(shade).opacity(small ? 0.60 : 0.70).blur(radius: 1.3 * u)
            } else {
                MoonShade(phase: phase).fill(shade).opacity(0.78)
            }
        }
    }
}

// The lit part of the flat moon sign (the mock-up's glyph(): a 100 x 100 box, R 44): nothing at a new moon, the whole disc at a
// full one, else the limb's half circle closed by the terminator's half ellipse.
struct MoonGlyphLit: Shape {
    var phase: Double

    func path(in rect: CGRect) -> Path {
        let f = WPlan.norm(phase)
        var p = Path()
        if f < 0.02 || f > 0.98 { return p }
        let s = Double(min(rect.width, rect.height)) / 100
        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: Double(rect.minX) + x * s, y: Double(rect.minY) + y * s)
        }
        let r = 44.0
        if abs(f - 0.5) < 0.02 {
            p.addEllipse(in: CGRect(x: Double(rect.minX) + (50 - r) * s, y: Double(rect.minY) + (50 - r) * s, width: 2 * r * s, height: 2 * r * s))
            return p
        }
        let k = cos(2 * Double.pi * f)
        let rx = abs(k) * r
        let limb: Double = f < 0.5 ? 1 : -1           // the lit limb: right when waxing, left when waning
        let term: Double = k < 0 ? -limb : limb       // the terminator bulges away from the limb when gibbous
        let n = 32
        p.move(to: pt(50, 50 - r))
        for i in 1...n {
            let a = Double.pi * Double(i) / Double(n)
            p.addLine(to: pt(50 + r * sin(a) * limb, 50 - r * cos(a)))
        }
        for i in 1...n {
            let a = Double.pi * Double(n - i) / Double(n)
            p.addLine(to: pt(50 + rx * sin(a) * term, 50 - r * cos(a)))
        }
        p.closeSubpath()
        return p
    }
}

// The flat moon sign of the lock screen: the system tints these widgets, and a photo turns into a white blob there.
struct MoonGlyph: View {
    let phase: Double
    let size: CGFloat
    var south: Bool = false

    var body: some View {
        let f = WPlan.norm(phase)
        let dark: Bool = f < 0.02 || f > 0.98      // a new moon: only the ring
        let u: CGFloat = size / 100
        ZStack {
            MoonGlyphLit(phase: phase).fill(Color.primary)
            Circle().inset(by: 6 * u).stroke(Color.primary.opacity(dark ? 0.9 : 0.55), lineWidth: 5 * u)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(south ? 180 : 0))
    }
}
