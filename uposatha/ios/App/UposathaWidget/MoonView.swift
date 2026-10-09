import SwiftUI

// The shadow of the moon: the same geometry as DgMoon.shadePath(f) of the designer's dg-moon.js (a 100 x 100 box,
// centre 50, R 48): the terminator, a half ellipse of semi-axis R |cos 2 pi f|, then a big half circle round the dark
// side that reaches beyond the disk. Drawn as short lines (48 steps a half) instead of SVG arcs.
struct MoonShade: Shape {
    var phase: Double

    func path(in rect: CGRect) -> Path {
        var f = phase.truncatingRemainder(dividingBy: 1)
        if f < 0 { f += 1 }
        let c = 50.0, r = 48.0, big = 62.0
        let k = cos(2 * Double.pi * f)
        let rx = abs(k) * r
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

// The moon: the NASA photo (the disk fills the square), the double shadow (sharp + wide penumbra), edge darkening, a thin rim.
// `south` turns it by 180 degrees; `mono` is for the lock screen; `glow` is a faint halo for dark backgrounds.
struct MoonView: View {
    let phase: Double
    let size: CGFloat
    var south: Bool = false
    var mono: Bool = false
    var glow: Bool = false
    @Environment(\.colorScheme) private var scheme

    private var illumination: Double {
        var f = phase.truncatingRemainder(dividingBy: 1)
        if f < 0 { f += 1 }
        return (1 - cos(2 * Double.pi * f)) / 2
    }

    var body: some View {
        let u = size / 100
        let shade: Color = mono ? Color.black : Color.dgMoonShade
        let rim: Color = mono ? Color.white.opacity(0.4) : Color.dgNavyInk.opacity(0.22)
        let edge = RadialGradient(
            gradient: Gradient(stops: [
                Gradient.Stop(color: Color.black.opacity(0), location: 0.5),
                Gradient.Stop(color: Color.black.opacity(0.14), location: 0.86),
                Gradient.Stop(color: Color.black.opacity(0.42), location: 1.0)
            ]),
            center: .center, startRadius: 0, endRadius: 48 * u)
        let halo = glow && scheme == .dark
        ZStack {
            Image("moon")
                .resizable()
                .interpolation(.high)
                .saturation(mono ? 0 : 1)
                .frame(width: 97.2 * u, height: 97.2 * u)
            Circle().fill(edge).frame(width: 96 * u, height: 96 * u)
            MoonShade(phase: phase).fill(shade).opacity(0.5).blur(radius: 4.5 * u)
            MoonShade(phase: phase).fill(shade).opacity(0.8).blur(radius: 1.3 * u)
        }
        .frame(width: size, height: size)
        .clipShape(Circle().inset(by: 2 * u))
        .overlay(Circle().inset(by: 2.4 * u).stroke(rim, lineWidth: 0.8 * u))
        .shadow(color: halo ? Color.white.opacity(0.4 * illumination) : Color.clear,
                radius: halo ? size * CGFloat(0.02 + 0.05 * illumination) : 0)
        .rotationEffect(.degrees(south ? 180 : 0))
    }
}
