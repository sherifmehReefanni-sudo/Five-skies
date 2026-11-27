import SwiftUI

/// Colors shared by the More tab and its tools, taken from the mockups.
enum MorePalette {
    static let ink = Color(hex: 0x120B1F)
    static let gold = Color(hex: 0xFBC56A)
    static let goldLight = Color(hex: 0xFFF1C9)
    static let mint = Color(hex: 0x8FF0C8)
    static let secondaryText = Color.white.opacity(0.84)

    static let goldGradient = LinearGradient(
        colors: [goldLight, gold],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// The night-sky backgrounds behind each More screen.
enum MoreSky {
    case more
    case tracker
    case tasbih
    case zakat
    case calendar

    private var colors: [Color] {
        switch self {
        case .more:
            return [Color(hex: 0x0B1030), Color(hex: 0x2B2A7A), Color(hex: 0x6B3F8F), Color(hex: 0x120B1F)]
        case .tracker:
            // Ends dark so the tab bar icons stay legible.
            return [Color(hex: 0x0A1440), Color(hex: 0x3A3F8F), Color(hex: 0x5B4A8F), Color(hex: 0x2A1638)]
        case .tasbih:
            return [Color(hex: 0x03061A), Color(hex: 0x141E55), Color(hex: 0x2E2560)]
        case .zakat:
            return [Color(hex: 0x0A1440), Color(hex: 0x1F4C7A), Color(hex: 0x3A3F8F), Color(hex: 0x120B1F)]
        case .calendar:
            return [Color(hex: 0x050B24), Color(hex: 0x1B2A6B), Color(hex: 0x5B4A8F), Color(hex: 0x2A1638)]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

/// How strong a glass card is: a dark tinted pane or a lighter frosted one.
enum MoreGlassTone {
    case dark
    case light
}

private struct MoreGlassModifier: ViewModifier {
    let tone: MoreGlassTone
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(
                shape.fill(tone == .dark ? MorePalette.ink.opacity(0.55) : Color.white.opacity(0.1))
                    .shadow(color: Color(hex: 0x05040F, opacity: 0.3), radius: 12, y: 6)
            )
            .overlay(
                // Lit along the top edge and fading down, like light catching a pane of glass.
                shape.strokeBorder(
                    LinearGradient(
                        colors: tone == .dark
                            ? [Color.white.opacity(0.42), Color.white.opacity(0.16)]
                            : [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
    }
}

/// A still scatter of faint stars over the top of a More sky, from a stable hash.
private struct MoreStarDust: View {
    private static let count = 70

    var body: some View {
        Canvas { context, size in
            for index in 0..<Self.count {
                let x = MotionWave.hash(index, salt: 31)
                let y = MotionWave.hash(index, salt: 32) * 0.55
                let fade = 1 - y / 0.55
                let radius = CGFloat(0.5 + 0.9 * MotionWave.hash(index, salt: 33))
                let center = CGPoint(x: CGFloat(x) * size.width, y: CGFloat(y) * size.height)
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(.white.opacity(0.55 * fade))
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// A semi-transparent glass card with a thin light border.
    func moreGlass(_ tone: MoreGlassTone = .light, cornerRadius: CGFloat = 24) -> some View {
        modifier(MoreGlassModifier(tone: tone, cornerRadius: cornerRadius))
    }

    /// Paints a More night sky behind the view, edge to edge.
    func moreSkyBackground(_ sky: MoreSky) -> some View {
        background(
            ZStack {
                sky.gradient
                MoreStarDust()
            }
            .ignoresSafeArea()
        )
    }
}

/// The large heavy screen title used across the More screens.
struct MoreScreenTitle: View {
    let text: String
    let identifier: String

    var body: some View {
        Text(text)
            .font(.largeTitle.weight(.heavy))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }
}

/// A small upper-case caption, as in "CURRENT STREAK".
struct MoreCaption: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.heavy))
            .tracking(2)
            .foregroundStyle(MorePalette.secondaryText)
    }
}
