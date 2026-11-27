import SwiftUI

/// Full-bleed living sky for a prayer period. Phase changes crossfade slowly.
/// With `showsCelestial` false the sun and moon are left out; stars, gradient, glow and skyline stay.
/// Stars twinkle, the sun and moon breathe, haze drifts by day, and an occasional shooting star
/// crosses the night, all only while ambient motion is on. With it off every element rests still.
/// When the user picked a fixed theme (see SkyTheme), that theme's sky is drawn instead, with the
/// stars and skyline but no sun or moon, whatever the prayer phase. Living sky is unchanged.
struct SkyView: View {
    let phase: Prayer
    var showsCelestial = true
    /// Draws this theme instead of the stored one, for previews and rendered images.
    var themeOverride: SkyTheme?
    /// False for previews inside a card, so the sky keeps to its own frame.
    var fillsScreen = true

    @AppStorage(SkyTheme.storageKey) private var storedTheme: SkyTheme = SkyTheme.defaultTheme

    init(phase: Prayer, showsCelestial: Bool = true, themeOverride: SkyTheme? = nil, fillsScreen: Bool = true) {
        self.phase = phase
        self.showsCelestial = showsCelestial
        self.themeOverride = themeOverride
        self.fillsScreen = fillsScreen
    }

    var body: some View {
        let theme = themeOverride ?? SkyTheme.effective(stored: storedTheme, arguments: SkyTheme.processArguments)
        return ZStack {
            if let fixedStyle = SkyStyle.style(forTheme: theme) {
                SkyScene(phase: .isha, style: fixedStyle, showsCelestial: false)
                    .id("theme-\(theme.rawValue)")
                    .transition(.opacity)
            } else {
                SkyScene(phase: phase, style: SkyStyle.style(for: phase), showsCelestial: showsCelestial)
                    .id("phase-\(phase.rawValue)")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 2.5), value: phase)
        .animation(.easeInOut(duration: 0.8), value: theme)
        .ignoresSafeArea(edges: fillsScreen ? Edge.Set.all : Edge.Set())
        .accessibilityHidden(true)
    }
}

/// A soft darkening at the top of the bright day skies so white text keeps its contrast
/// (at least 4.5 to 1 for small text where Today and Qibla place it). Night skies need none.
/// It is kept out of SkyView itself so wallpapers and share images keep their full colour.
struct SkyLegibilityScrim: View {
    let phase: Prayer

    @AppStorage(SkyTheme.storageKey) private var storedTheme: SkyTheme = SkyTheme.defaultTheme

    /// Strength at the very top; it fades to nothing at half the screen height.
    static func strength(for phase: Prayer) -> Double {
        switch phase {
        case .dhuhr: return 0.34
        case .asr: return 0.22
        case .fajr, .maghrib, .isha: return 0
        }
    }

    var body: some View {
        let theme = SkyTheme.effective(stored: storedTheme, arguments: SkyTheme.processArguments)
        let strength = SkyStyle.style(forTheme: theme) == nil ? Self.strength(for: phase) : 0
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(hex: 0x061230, opacity: strength), location: 0),
                Gradient.Stop(color: Color(hex: 0x061230, opacity: 0), location: 0.5)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 2.5), value: strength)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Where the top of the skyline sits, as a fraction of the screen height.
private let skylineTopFraction: CGFloat = 0.52

private extension Prayer {
    /// Daytime and sunset skies carry faint drifting haze.
    var hasHaze: Bool {
        switch self {
        case .dhuhr, .asr, .maghrib: return true
        case .fajr, .isha: return false
        }
    }

    /// Night skies can show a shooting star.
    var hasShootingStars: Bool {
        switch self {
        case .fajr, .isha: return true
        case .dhuhr, .asr, .maghrib: return false
        }
    }
}

private struct SkyScene: View {
    let phase: Prayer
    let style: SkyStyle
    let showsCelestial: Bool

    @Environment(\.ambientMotionEnabled) private var animates

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
                if GalaxyBand.isShown(for: style.starOpacities) {
                    GalaxyBand(skylineTop: skylineTop)
                }
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animates)) { context in
                    // nil means rest: every element is drawn in its still state.
                    let time: Double? = animates ? context.date.timeIntervalSinceReferenceDate : nil
                    ZStack(alignment: .topLeading) {
                        StarField(opacities: style.starOpacities, skylineTop: skylineTop, time: time)
                        if phase.hasShootingStars, let time = time {
                            ShootingStar(time: time, skylineTop: skylineTop)
                        }
                        if let glow = style.glow {
                            GlowView(glow: glow, size: size)
                        }
                        if showsCelestial {
                            CelestialView(celestial: style.celestial, size: size, time: time)
                        }
                        if phase.hasHaze {
                            HazeBands(phase: phase, size: size, time: time)
                        }
                        SkylineView(style: style, width: size.width, top: skylineTop, time: time)
                    }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

/// Three layers of stars from the mockup, laid out in a 245 x 340 design space.
private struct StarField: View {
    let opacities: [Double]
    let skylineTop: CGFloat
    /// Seconds for the twinkle, or nil to draw every star at full strength.
    let time: Double?

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

    /// Faint dust between the main stars, placed from a stable hash so it never moves.
    private static let dustCount = 90

    /// How far down the sky the dust reaches, as a share of the skyline top: all the way on
    /// the darkest night, less as the horizon brightens.
    private var dustReach: Double {
        Double(opacities.filter { $0 > 0 }.count) / 3
    }

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / 245
            let scaleY = skylineTop / 340
            drawDust(in: &context, size: size)
            var starIndex = 0
            for (index, layer) in Self.layers.enumerated() where index < opacities.count {
                let layerOpacity = opacities[index]
                for star in layer {
                    starIndex += 1
                    guard layerOpacity > 0 else { continue }
                    let opacity = layerOpacity * Self.twinkle(star: starIndex, time: time)
                    let radius = star.r * scaleX
                    let center = CGPoint(x: star.x * scaleX, y: star.y * scaleY)
                    let tint = Self.tint(for: starIndex)
                    if star.r >= 1 {
                        // A soft bloom around the brighter stars.
                        let bloom = radius * 4
                        context.fill(
                            Path(ellipseIn: CGRect(x: center.x - bloom, y: center.y - bloom, width: bloom * 2, height: bloom * 2)),
                            with: .radialGradient(
                                Gradient(colors: [tint.opacity(0.28 * opacity), tint.opacity(0)]),
                                center: center,
                                startRadius: 0,
                                endRadius: bloom
                            )
                        )
                    }
                    if star.r >= 1.2 && layerOpacity >= 0.9 {
                        // A fine four point glint on the brightest stars of a dark sky.
                        let reach = radius * 4.5
                        var glint = Path()
                        glint.move(to: CGPoint(x: center.x - reach, y: center.y))
                        glint.addLine(to: CGPoint(x: center.x + reach, y: center.y))
                        glint.move(to: CGPoint(x: center.x, y: center.y - reach))
                        glint.addLine(to: CGPoint(x: center.x, y: center.y + reach))
                        context.stroke(glint, with: .color(tint.opacity(0.35 * opacity)), lineWidth: 0.6)
                    }
                    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(tint.opacity(opacity)))
                }
            }
        }
    }

    /// Most stars are white; a few lean warm and a few lean blue, as real stars do.
    static func tint(for index: Int) -> Color {
        let pick = MotionWave.hash(index, salt: 7)
        if pick < 0.18 { return Color(hex: 0xFFE9C4) }
        if pick > 0.84 { return Color(hex: 0xD3E2FF) }
        return .white
    }

    private func drawDust(in context: inout GraphicsContext, size: CGSize) {
        let reach = dustReach
        guard reach > 0 else { return }
        let strength = opacities.max() ?? 0
        for index in 0..<Self.dustCount {
            let x = MotionWave.hash(index, salt: 21)
            let y = MotionWave.hash(index, salt: 22)
            guard y < reach else { continue }
            // Thins out toward the bottom of its reach.
            let fade = 1 - y / reach
            let flicker = time == nil ? 1 : (0.6 + 0.4 * Self.twinkle(star: 100 + index, time: time))
            let radius = CGFloat(0.35 + 0.45 * MotionWave.hash(index, salt: 23)) * size.width / 245
            let center = CGPoint(x: CGFloat(x) * size.width, y: CGFloat(y) * skylineTop)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(.white.opacity(0.5 * strength * fade * flicker))
            )
        }
    }


    /// A star's brightness factor, easing between 0.35 and 1. Each star has its own stable
    /// phase and a period of 2.5 to 6 seconds, both derived from its index.
    static func twinkle(star index: Int, time: Double?) -> Double {
        guard let time = time else { return 1 }
        let period = 2.5 + 3.5 * MotionWave.hash(index, salt: 1)
        let wave = MotionWave.breath(time, period: period, offset: MotionWave.hash(index, salt: 2))
        return 1 - 0.65 * wave
    }
}

/// A faint band of the galaxy across a deep night sky, drawn once and never animated.
private struct GalaxyBand: View {
    let skylineTop: CGFloat

    /// A deep night with every star layer lit shows the band.
    static func isShown(for opacities: [Double]) -> Bool {
        opacities.count >= 3 && opacities.allSatisfy { $0 >= 0.9 }
    }

    var body: some View {
        Canvas { context, size in
            Self.draw(in: &context, size: size, skylineTop: skylineTop)
        }
        .allowsHitTesting(false)
    }

    /// A very faint diagonal wash, brightest along its middle.
    private static func draw(in context: inout GraphicsContext, size: CGSize, skylineTop: CGFloat) {
        var band = context
        band.translateBy(x: size.width * 0.5, y: skylineTop * 0.42)
        band.rotate(by: .degrees(-28))
        let width = size.width * 1.9
        let height = skylineTop * 0.34
        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        band.addFilter(.blur(radius: 18))
        band.fill(
            Path(ellipseIn: rect),
            with: .linearGradient(
                Gradient(stops: [
                    Gradient.Stop(color: Color(hex: 0xB9C4FF, opacity: 0), location: 0),
                    Gradient.Stop(color: Color(hex: 0xB9C4FF, opacity: 0.09), location: 0.5),
                    Gradient.Stop(color: Color(hex: 0xB9C4FF, opacity: 0), location: 1)
                ]),
                startPoint: CGPoint(x: 0, y: -height / 2),
                endPoint: CGPoint(x: 0, y: height / 2)
            )
        )
    }
}

/// Now and then a short thin streak crosses the upper night sky and fades within 0.8 seconds.
/// Timing is worked out from the time alone: one chance in every 25 second window, starting at
/// a stable offset of 0 to 5 seconds, so streaks are always 20 to 30 seconds apart.
private struct ShootingStar: View {
    let time: Double
    let skylineTop: CGFloat

    private static let window: Double = 25
    private static let duration: Double = 0.8

    var body: some View {
        Canvas { context, size in
            let windowIndex = Int(floor(time / Self.window))
            let start = Double(windowIndex) * Self.window + 5 * MotionWave.hash(windowIndex, salt: 3)
            let elapsed = time - start
            guard elapsed >= 0, elapsed < Self.duration else { return }
            let progress = elapsed / Self.duration
            let opacity = sin(Double.pi * progress)

            let goesRight = MotionWave.hash(windowIndex, salt: 4) < 0.5
            let origin = CGPoint(
                x: size.width * CGFloat(0.2 + 0.6 * MotionWave.hash(windowIndex, salt: 5)),
                y: skylineTop * CGFloat(0.08 + 0.3 * MotionWave.hash(windowIndex, salt: 6))
            )
            let direction = CGVector(dx: goesRight ? 0.88 : -0.88, dy: 0.47)
            let travel: CGFloat = 90
            let length: CGFloat = 46
            let head = CGPoint(
                x: origin.x + direction.dx * travel * CGFloat(progress),
                y: origin.y + direction.dy * travel * CGFloat(progress)
            )
            let tail = CGPoint(x: head.x - direction.dx * length, y: head.y - direction.dy * length)

            var path = Path()
            path.move(to: tail)
            path.addLine(to: head)
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [Color.white.opacity(0), Color.white.opacity(0.9 * opacity)]),
                    startPoint: tail,
                    endPoint: head
                ),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )
        }
        .allowsHitTesting(false)
    }
}

/// Two or three very faint, wide, blurred bands that drift sideways and wrap around.
/// Each makes one full pass in 60 to 90 seconds. At rest they sit at their starting places.
private struct HazeBands: View {
    let phase: Prayer
    let size: CGSize
    let time: Double?

    private struct Band {
        let y: CGFloat
        let height: CGFloat
        let opacity: Double
        let period: Double
        let start: Double
    }

    private static let bands: [Band] = [
        Band(y: 0.16, height: 0.05, opacity: 0.10, period: 84, start: 0.25),
        Band(y: 0.29, height: 0.04, opacity: 0.07, period: 66, start: 0.7),
        Band(y: 0.40, height: 0.06, opacity: 0.06, period: 76, start: 0.45)
    ]

    private var color: Color {
        phase == .maghrib ? Color(hex: 0xFFD9B8) : Color.white
    }

    var body: some View {
        let bandWidth = size.width * 1.3
        let blur: CGFloat = 22
        let span = size.width + bandWidth + blur * 4
        ZStack(alignment: .topLeading) {
            ForEach(Self.bands.indices, id: \.self) { index in
                let band = Self.bands[index]
                let progress = MotionWave.fraction(band.start + (time ?? 0) / band.period)
                Capsule()
                    .fill(color.opacity(band.opacity))
                    .frame(width: bandWidth, height: size.height * band.height)
                    .blur(radius: blur)
                    .position(
                        x: -bandWidth / 2 - blur * 2 + span * CGFloat(progress),
                        y: size.height * band.y
                    )
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
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
    /// Seconds for the breathing glow, or nil to rest.
    let time: Double?

    private var isSun: Bool {
        if case .sun = celestial.body { return true }
        return false
    }

    /// 0 at rest, easing up to 1 and back: the sun over 6 seconds, the moon over 8.
    private var breath: Double {
        guard let time = time else { return 0 }
        return MotionWave.breath(time, period: isSun ? 6 : 8)
    }

    var body: some View {
        let haloDiameter = size.width * celestial.haloSize
        let bodyDiameter = size.width * celestial.bodySize
        let position = CGPoint(x: size.width * celestial.center.x, y: size.height * celestial.center.y)
        ZStack {
            // A wide soft bloom behind the halo, so the light seems to spill into the sky.
            Circle()
                .fill(bloomColor)
                .frame(width: bodyDiameter * 2.4, height: bodyDiameter * 2.4)
                .blur(radius: bodyDiameter * 0.5)
                .opacity((isSun ? 0.55 : 0.4) * (1 - 0.25 * breath))
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
                .scaleEffect(isSun ? 1 + 0.06 * CGFloat(breath) : 1)
                .opacity(isSun ? 1 - 0.18 * breath : 1 - 0.4 * breath)
            bodyShape(diameter: bodyDiameter)
        }
        .position(position)
    }

    private var bloomColor: Color {
        switch celestial.body {
        case let .sun(_, glow, _): return glow
        case let .crescent(color): return color.opacity(0.6)
        case let .fullMoon(_, glow, _): return glow
        }
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
                .overlay(MoonSurface())
                .clipShape(Circle())
                .frame(width: diameter, height: diameter)
                .shadow(color: glow, radius: glowRadius)
        }
    }
}

/// A few faint darker patches on the full moon, laid out as fractions of its width.
private struct MoonSurface: View {
    private static let patches: [(x: CGFloat, y: CGFloat, r: CGFloat, opacity: Double)] = [
        (0.36, 0.34, 0.16, 0.10), (0.58, 0.30, 0.11, 0.08), (0.62, 0.56, 0.18, 0.09),
        (0.38, 0.64, 0.10, 0.07), (0.50, 0.46, 0.07, 0.06)
    ]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                ForEach(Self.patches.indices, id: \.self) { index in
                    let patch = Self.patches[index]
                    Circle()
                        .fill(Color(hex: 0x8C8670, opacity: patch.opacity))
                        .frame(width: width * patch.r * 2, height: width * patch.r * 2)
                        .blur(radius: width * 0.02)
                        .position(x: width * patch.x, y: width * patch.y)
                }
            }
        }
    }
}

/// Hills, mosque, window lights and ground, with the ground color filling to the bottom edge.
private struct SkylineView: View {
    let style: SkyStyle
    let width: CGFloat
    let top: CGFloat
    /// Seconds for the window flicker, or nil to rest at full strength.
    let time: Double?

    /// A very slow warm flicker between 0.8 and 1.
    private var flicker: Double {
        guard let time = time else { return 1 }
        let slow = MotionWave.breath(time, period: 7.3)
        let slower = MotionWave.breath(time, period: 11.9, offset: 0.3)
        return 1 - 0.12 * slow - 0.08 * slower
    }

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
                    .opacity(style.lightsOpacity * flicker)
                GroundShape()
                    .fill(style.ground)
            }
            .frame(width: width, height: height)
            style.ground
        }
        .frame(width: width)
    }
}
