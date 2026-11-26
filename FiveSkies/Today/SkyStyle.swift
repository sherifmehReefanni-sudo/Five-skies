import SwiftUI

/// Colors and placements for one of the five skies, taken from the Skies mockup.
/// Positions are fractions of the screen (x of width, y of height); sizes are fractions of width.
/// The sun and moon sit in the band between the countdown pill and the skyline (about 0.50 to 0.56
/// of the height) so they never sit behind the headline, the time or the pill. Maghrib's sun is lower,
/// half behind the central dome.
struct SkyStyle {
    struct Glow {
        let center: UnitPoint
        let widthFraction: CGFloat
        let heightFraction: CGFloat
        let color: Color
    }

    enum Body {
        case sun(stops: [Gradient.Stop], glow: Color, glowRadius: CGFloat)
        case crescent(color: Color)
        case fullMoon(stops: [Gradient.Stop], glow: Color, glowRadius: CGFloat)
    }

    struct Celestial {
        let center: UnitPoint
        let haloSize: CGFloat
        let haloStops: [Gradient.Stop]
        let bodySize: CGFloat
        let body: Body
    }

    let skyStops: [Gradient.Stop]
    /// Opacity of the three star layers.
    let starOpacities: [Double]
    let glow: Glow?
    let celestial: Celestial
    let hill: Color
    let hillOpacity: Double
    let land: Color
    let ground: Color
    let lightsOpacity: Double

    static func style(for phase: Prayer) -> SkyStyle {
        switch phase {
        case .fajr: return fajr
        case .dhuhr: return dhuhr
        case .asr: return asr
        case .maghrib: return maghrib
        case .isha: return isha
        }
    }

    private static func stop(_ hex: UInt32, _ location: CGFloat, opacity: Double = 1) -> Gradient.Stop {
        Gradient.Stop(color: Color(hex: hex, opacity: opacity), location: location)
    }

    private static let fajr = SkyStyle(
        skyStops: [
            stop(0x050B24, 0), stop(0x0E1846, 0.30), stop(0x1B2A6B, 0.55),
            stop(0xC97A7A, 0.76), stop(0xF2B880, 0.86), stop(0xF2B880, 1)
        ],
        starOpacities: [1, 0.8, 0],
        glow: Glow(
            center: UnitPoint(x: 0.5, y: 0.6),
            widthFraction: 1.65,
            heightFraction: 0.28,
            color: Color(hex: 0xF2B880, opacity: 0.55)
        ),
        celestial: Celestial(
            center: UnitPoint(x: 0.8, y: 0.52),
            haloSize: 0.19,
            haloStops: [stop(0xF6EFD8, 0, opacity: 0.35), stop(0xF6EFD8, 0.7, opacity: 0)],
            bodySize: 0.09,
            body: .crescent(color: Color(hex: 0xF6EFD8))
        ),
        hill: Color(hex: 0x4A3A6E),
        hillOpacity: 0.7,
        land: Color(hex: 0x120E2C),
        ground: Color(hex: 0x07061A),
        lightsOpacity: 1
    )

    private static let dhuhr = SkyStyle(
        skyStops: [
            stop(0x1E6FD0, 0), stop(0x3D8FE0, 0.35), stop(0x7EC3F5, 0.65),
            stop(0xD8F0FF, 0.88), stop(0xD8F0FF, 1)
        ],
        starOpacities: [0, 0, 0],
        glow: nil,
        celestial: Celestial(
            center: UnitPoint(x: 0.5, y: 0.53),
            haloSize: 0.82,
            haloStops: [
                stop(0xFFFFF0, 0, opacity: 0.6), stop(0xFFFFF0, 0.35, opacity: 0.18),
                stop(0xFFFFF0, 0.7, opacity: 0)
            ],
            bodySize: 0.16,
            body: .sun(
                stops: [stop(0xFFFFFF, 0), stop(0xFFF8D6, 0.6), stop(0xFFF1B0, 1)],
                glow: Color(hex: 0xFFFADC, opacity: 0.8),
                glowRadius: 30
            )
        ),
        hill: Color(hex: 0x4F7FB0),
        hillOpacity: 0.6,
        land: Color(hex: 0x23466E),
        ground: Color(hex: 0x1A3556),
        lightsOpacity: 0
    )

    private static let asr = SkyStyle(
        skyStops: [
            stop(0x1B4F9E, 0), stop(0x3F6FB0, 0.30), stop(0x9AA6B8, 0.55),
            stop(0xF4C987, 0.82), stop(0xF4C987, 1)
        ],
        starOpacities: [0, 0, 0],
        glow: Glow(
            center: UnitPoint(x: 0.5, y: 0.58),
            widthFraction: 1.5,
            heightFraction: 0.3,
            color: Color(hex: 0xFFD696, opacity: 0.45)
        ),
        celestial: Celestial(
            center: UnitPoint(x: 0.72, y: 0.53),
            haloSize: 0.98,
            haloStops: [
                stop(0xFFE2A0, 0, opacity: 0.6), stop(0xFFE2A0, 0.35, opacity: 0.2),
                stop(0xFFE2A0, 0.7, opacity: 0)
            ],
            bodySize: 0.23,
            body: .sun(
                stops: [stop(0xFFFBEA, 0), stop(0xFFE9B5, 0.6), stop(0xFFE2A0, 1)],
                glow: Color(hex: 0xFFD68C, opacity: 0.7),
                glowRadius: 36
            )
        ),
        hill: Color(hex: 0x9A6E6A),
        hillOpacity: 0.6,
        land: Color(hex: 0x3A2A44),
        ground: Color(hex: 0x24182F),
        lightsOpacity: 0
    )

    private static let maghrib = SkyStyle(
        skyStops: [
            stop(0x071433, 0), stop(0x1B3F7E, 0.22), stop(0x5B5AA6, 0.40),
            stop(0xC66B7A, 0.54), stop(0xF39A5B, 0.64), stop(0xFBD08A, 0.74), stop(0xFBD08A, 1)
        ],
        starOpacities: [0.8, 0, 0],
        glow: nil,
        celestial: Celestial(
            center: UnitPoint(x: 0.5, y: 0.6),
            haloSize: 0.92,
            haloStops: [
                stop(0xFFF4D6, 0, opacity: 0.95), stop(0xFFDE96, 0.14, opacity: 0.6),
                stop(0xFFBE78, 0.38, opacity: 0.25), stop(0xFFBE78, 0.68, opacity: 0)
            ],
            bodySize: 0.26,
            body: .sun(
                stops: [stop(0xFFF6DC, 0), stop(0xFFE3A0, 0.7), stop(0xFFD08A, 1)],
                glow: Color(hex: 0xFFD68C, opacity: 0.6),
                glowRadius: 40
            )
        ),
        hill: Color(hex: 0x7B4A78),
        hillOpacity: 0.75,
        land: Color(hex: 0x2A1638),
        ground: Color(hex: 0x120B1F),
        lightsOpacity: 1
    )

    private static let isha = SkyStyle(
        skyStops: [
            stop(0x03061A, 0), stop(0x0A1036, 0.35), stop(0x141E55, 0.65),
            stop(0x2E2560, 0.88), stop(0x2E2560, 1)
        ],
        starOpacities: [1, 1, 1],
        glow: nil,
        celestial: Celestial(
            center: UnitPoint(x: 0.78, y: 0.53),
            haloSize: 0.82,
            haloStops: [
                stop(0xDCE1FF, 0, opacity: 0.3), stop(0xDCE1FF, 0.35, opacity: 0.1),
                stop(0xDCE1FF, 0.7, opacity: 0)
            ],
            bodySize: 0.2,
            body: .fullMoon(
                stops: [stop(0xFFFDF2, 0), stop(0xF1ECD6, 0.7), stop(0xDCD5BC, 1)],
                glow: Color(hex: 0xF0ECD6, opacity: 0.35),
                glowRadius: 28
            )
        ),
        hill: Color(hex: 0x2B2A5E),
        hillOpacity: 0.8,
        land: Color(hex: 0x0B0A22),
        ground: Color(hex: 0x05040F),
        lightsOpacity: 1
    )
}
