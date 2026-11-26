import SwiftUI

/// Full-bleed living sky for a prayer period. Phase changes crossfade slowly.
/// With `showsCelestial` false the sun and moon are left out; stars, gradient, glow and skyline stay.
struct SkyView: View {
    let phase: Prayer
    var showsCelestial = true

    var body: some View {
        ZStack {
            SkyScene(style: SkyStyle.style(for: phase), showsCelestial: showsCelestial)
                .id(phase)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 2.5), value: phase)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Where the top of the skyline sits, as a fraction of the screen height.
private let skylineTopFraction: CGFloat = 0.52

private struct SkyScene: View {
    let style: SkyStyle
    let showsCelestial: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let skylineTop = size.height * skylineTopFraction
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    gradient: Gradient(stops: style.skyStops),
                    startPoint: .top,
                    endPoint: .bottom
                )
                StarField(opacities: style.starOpacities, skylineTop: skylineTop)
                if let glow = style.glow {
                    GlowView(glow: glow, size: size)
                }
                if showsCelestial {
                    CelestialView(celestial: style.celestial, size: size)
                }
                SkylineView(style: style, width: size.width, top: skylineTop)
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

/// Three layers of stars from the mockup, laid out in a 245 x 340 design space.
private struct StarField: View {
    let opacities: [Double]
    let skylineTop: CGFloat

    private static let layers: [[Star]] = [
        [
            Star(24, 22, 1.2), Star(70, 40, 0.9), Star(118, 14, 1),
            Star(160, 34, 0.8), Star(214, 20, 1.3), Star(40, 62, 0.7),
            Star(150, 62, 0.8)
        ],
        [
            Star(18, 120, 0.9), Star(226, 140, 1), Star(60, 210, 0.8),
            Star(210, 262, 0.8), Star(30, 300, 0.7), Star(150, 190, 0.6),
            Star(110, 280, 0.7), Star(232, 320, 0.6)
        ],
        [
            Star(90, 70, 0.8), Star(140, 96, 0.6), Star(12, 170, 0.7),
            Star(236, 200, 0.9), Star(84, 240, 0.6), Star(176, 300, 0.8),
            Star(48, 330, 0.7), Star(128, 150, 0.5), Star(208, 96, 0.7),
            Star(62, 140, 0.6)
        ]
    ]

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / 245
            let scaleY = skylineTop / 340
            for (index, layer) in Self.layers.enumerated() where index < opacities.count {
                let opacity = opacities[index]
                guard opacity > 0 else { continue }
                for star in layer {
                    let radius = star.r * scaleX
                    let rect = CGRect(
                        x: star.x * scaleX - radius,
                        y: star.y * scaleY - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
                }
            }
        }
    }
}

/// A star position and radius in design units.
private struct Star {
    let x: CGFloat
    let y: CGFloat
    let r: CGFloat

    init(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        self.x = x
        self.y = y
        self.r = r
    }
}

/// A soft horizontal glow near the horizon.
private struct GlowView: View {
    let glow: SkyStyle.Glow
    let size: CGSize

    var body: some View {
        Rectangle()
            .fill(
                EllipticalGradient(
                    gradient: Gradient(stops: [
                        Gradient.Stop(color: glow.color, location: 0),
                        Gradient.Stop(color: glow.color.opacity(0), location: 0.65)
                    ]),
                    center: .center,
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.71
                )
            )
            .frame(width: size.width * glow.widthFraction, height: size.height * glow.heightFraction)
            .position(x: size.width * glow.center.x, y: size.height * glow.center.y)
    }
}

/// The sun or moon with its halo.
private struct CelestialView: View {
    let celestial: SkyStyle.Celestial
    let size: CGSize

    var body: some View {
        let haloDiameter = size.width * celestial.haloSize
        let bodyDiameter = size.width * celestial.bodySize
        let position = CGPoint(x: size.width * celestial.center.x, y: size.height * celestial.center.y)
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: celestial.haloStops),
                        center: .center,
                        startRadius: 0,
                        endRadius: haloDiameter * 0.71
                    )
                )
                .frame(width: haloDiameter, height: haloDiameter)
            bodyShape(diameter: bodyDiameter)
        }
        .position(position)
    }

    @ViewBuilder
    private func bodyShape(diameter: CGFloat) -> some View {
        switch celestial.body {
        case let .sun(stops, glow, glowRadius):
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: stops),
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 0.71
                    )
                )
                .frame(width: diameter, height: diameter)
                .shadow(color: glow, radius: glowRadius)
        case let .crescent(color):
            Circle()
                .fill(color)
                .overlay(
                    Circle()
                        .fill(Color.black)
                        .offset(x: -diameter * 0.27, y: diameter * 0.14)
                        .blendMode(.destinationOut)
                )
                .compositingGroup()
                .frame(width: diameter, height: diameter)
                .shadow(color: color.opacity(0.5), radius: 8)
        case let .fullMoon(stops, glow, glowRadius):
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: stops),
                        center: UnitPoint(x: 0.4, y: 0.4),
                        startRadius: 0,
                        endRadius: diameter * 0.85
                    )
                )
                .frame(width: diameter, height: diameter)
                .shadow(color: glow, radius: glowRadius)
        }
    }
}

/// Hills, mosque, window lights and ground, with the ground color filling to the bottom edge.
private struct SkylineView: View {
    let style: SkyStyle
    let width: CGFloat
    let top: CGFloat

    var body: some View {
        let height = width * 250 / 390
        VStack(spacing: 0) {
            Color.clear
                .frame(height: top)
            ZStack {
                HillShape()
                    .fill(style.hill)
                    .opacity(style.hillOpacity)
                MosqueSkylineShape()
                    .fill(style.land)
                SkylineLightsShape()
                    .fill(Color(hex: 0xFFD27A))
                    .opacity(style.lightsOpacity)
                GroundShape()
                    .fill(style.ground)
            }
            .frame(width: width, height: height)
            style.ground
        }
        .frame(width: width)
    }
}
