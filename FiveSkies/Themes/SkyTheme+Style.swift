import SwiftUI

extension SkyStyle {
    /// The fixed sky for a theme, or nil for the living sky. Stars and skyline stay; the sun and
    /// moon are hidden by SkyView, so the celestial entry here is never drawn.
    static func style(forTheme theme: SkyTheme) -> SkyStyle? {
        guard let gradient = theme.gradient else { return nil }
        let stops = gradient.map { Gradient.Stop(color: Color(hex: $0.hex), location: CGFloat($0.location)) }
        switch theme {
        case .living:
            return nil
        case .midnight:
            return themed(stops, stars: [1, 1, 1], hill: 0x2B2A5E, land: 0x0B0A22, ground: 0x05040F)
        case .emerald:
            return themed(stops, stars: [1, 0.8, 0.5], hill: 0x0F4A44, land: 0x03201C, ground: 0x021411)
        case .desert:
            return themed(stops, stars: [0.8, 0.4, 0], hill: 0x7B4A78, land: 0x2A1638, ground: 0x120B1F)
        }
    }

    private static func themed(
        _ stops: [Gradient.Stop],
        stars: [Double],
        hill: UInt32,
        land: UInt32,
        ground: UInt32
    ) -> SkyStyle {
        SkyStyle(
            skyStops: stops,
            starOpacities: stars,
            glow: nil,
            celestial: SkyStyle.style(for: .isha).celestial,
            hill: Color(hex: hill),
            hillOpacity: 0.8,
            land: Color(hex: land),
            ground: Color(hex: ground),
            lightsOpacity: 1
        )
    }
}
