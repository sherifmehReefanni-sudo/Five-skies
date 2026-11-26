import SwiftUI

/// A 300 point compass: a dial that turns with the device, a frosted disc, and a needle toward the Kaaba.
struct QiblaCompass: View {
    /// Degrees from true north, or nil when the location is unknown.
    let bearing: Double?
    /// Device heading in degrees from north, or nil without a compass.
    let heading: Double?
    let guidance: QiblaGuidance.State

    /// Diameter in points. Static so the memberwise init stays internal.
    private static let size: CGFloat = 300

    private var isAligned: Bool {
        guidance == .aligned
    }

    private var dialRotation: Double {
        QiblaGuidance.dialRotation(heading: heading)
    }

    private var needleRotation: Double {
        guard let bearing = bearing else { return 0 }
        return QiblaGuidance.needleRotation(bearing: bearing, heading: heading)
    }

    var body: some View {
        ZStack {
            glow
            dial
                .rotationEffect(.degrees(dialRotation))
            disc
            needle
                .rotationEffect(.degrees(needleRotation))
                .opacity(bearing == nil ? 0.4 : 1)
        }
        .frame(width: Self.size, height: Self.size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityValue(Text(guidance.text))
        .accessibilityIdentifier("qiblaCompass")
    }

    private var accessibilityText: String {
        guard let bearing = bearing else {
            return "Qibla compass. Qibla direction needs your location"
        }
        let degrees = QiblaGuidance.wholeDegrees(bearing)
        let unit = degrees == 1 ? "degree" : "degrees"
        return "Qibla is \(degrees) \(unit) from north, \(QiblaGuidance.compassName(bearing))"
    }

    private var glow: some View {
        let inner = isAligned ? QiblaPalette.mint.opacity(0.4) : Color(hex: 0xFFDE96, opacity: 0.32)
        let middle = isAligned ? QiblaPalette.mint.opacity(0.18) : Color(hex: 0x968CE6, opacity: 0.18)
        return Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        Gradient.Stop(color: inner, location: 0),
                        Gradient.Stop(color: middle, location: 0.42),
                        Gradient.Stop(color: middle.opacity(0), location: 0.7)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: 180
                )
            )
            .frame(width: 360, height: 360)
            .allowsHitTesting(false)
    }

    private var dial: some View {
        let ringColor = isAligned ? QiblaPalette.mint : Color.white.opacity(0.55)
        return ZStack {
            Circle()
                .inset(by: 10)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 1.5, dash: [3, 6]))
                .shadow(color: isAligned ? QiblaPalette.mint.opacity(0.8) : .clear, radius: 8)
            CompassTicks(every: 90, outerInset: 22, length: 12)
                .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            CompassTicks(every: 30, outerInset: 22, length: 6, skippingMultiplesOf: 90)
                .stroke(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            cardinal("N", at: 0, color: QiblaPalette.gold)
            cardinal("E", at: 90, color: .white)
            cardinal("S", at: 180, color: .white)
            cardinal("W", at: 270, color: .white)
        }
        .frame(width: Self.size, height: Self.size)
    }

    /// A letter on the dial that stays upright as the dial turns.
    private func cardinal(_ letter: String, at degrees: Double, color: Color) -> some View {
        let radius: CGFloat = 102
        let radians = degrees * Double.pi / 180
        return Text(letter)
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(color)
            .rotationEffect(.degrees(-dialRotation))
            .offset(x: radius * CGFloat(sin(radians)), y: -radius * CGFloat(cos(radians)))
    }

    private var disc: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().fill(Color.white.opacity(0.1)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            .frame(width: 212, height: 212)
            .shadow(color: Color(hex: 0x071433, opacity: 0.45), radius: 22, y: 18)
    }

    private var needle: some View {
        let main = isAligned ? QiblaPalette.mint : QiblaPalette.gold
        let highlight = isAligned ? Color(hex: 0xD6FFEE) : QiblaPalette.goldLight
        return ZStack {
            NeedleHead()
                .fill(main)
            NeedleHeadHighlight()
                .fill(highlight)
            NeedleTail()
                .fill(Color.white.opacity(0.35))
            Circle()
                .fill(QiblaPalette.ink)
                .overlay(Circle().strokeBorder(main, lineWidth: 3))
                .frame(width: 21, height: 21)
            KaabaGlyph(band: main)
                .rotationEffect(.degrees(-needleRotation))
                .offset(y: -134)
        }
        .frame(width: Self.size, height: Self.size)
    }
}

/// A dark rounded square with a thin gold band, drawn upright at the needle tip.
private struct KaabaGlyph: View {
    let band: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(QiblaPalette.ink)
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(band)
                    .frame(height: 3)
                    .padding(.top, 5)
            }
            .frame(width: 22, height: 22)
    }
}

/// Radial tick marks every `every` degrees, drawn inward from `outerInset` points inside the edge.
private struct CompassTicks: Shape {
    let every: Double
    let outerInset: CGFloat
    let length: CGFloat
    var skippingMultiplesOf: Double? = nil

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2 - outerInset
        let inner = outer - length
        var degrees: Double = 0
        while degrees < 360 {
            let skip: Bool
            if let multiple = skippingMultiplesOf {
                skip = degrees.truncatingRemainder(dividingBy: multiple) == 0
            } else {
                skip = false
            }
            if !skip {
                let radians = degrees * Double.pi / 180
                let dx = CGFloat(sin(radians))
                let dy = -CGFloat(cos(radians))
                path.move(to: CGPoint(x: center.x + dx * outer, y: center.y + dy * outer))
                path.addLine(to: CGPoint(x: center.x + dx * inner, y: center.y + dy * inner))
            }
            degrees += every
        }
        return path
    }
}

/// Needle shapes in a 300 by 300 design space, scaled to the rect.
private func designPoint(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + x * rect.width / 300, y: rect.minY + y * rect.height / 300)
}

private struct NeedleHead: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: designPoint(150, 66, in: rect))
        path.addLine(to: designPoint(162, 150, in: rect))
        path.addLine(to: designPoint(138, 150, in: rect))
        path.closeSubpath()
        return path
    }
}

private struct NeedleHeadHighlight: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: designPoint(150, 66, in: rect))
        path.addLine(to: designPoint(150, 150, in: rect))
        path.addLine(to: designPoint(138, 150, in: rect))
        path.closeSubpath()
        return path
    }
}

private struct NeedleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: designPoint(138, 150, in: rect))
        path.addLine(to: designPoint(150, 222, in: rect))
        path.addLine(to: designPoint(162, 150, in: rect))
        path.closeSubpath()
        return path
    }
}
