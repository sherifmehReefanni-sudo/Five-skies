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
            )
            .overlay(
                shape.strokeBorder(Color.white.opacity(tone == .dark ? 0.3 : 0.22), lineWidth: 1)
            )
    }
}

extension View {
    /// A semi-transparent glass card with a thin light border.
    func moreGlass(_ tone: MoreGlassTone = .light, cornerRadius: CGFloat = 24) -> some View {
        modifier(MoreGlassModifier(tone: tone, cornerRadius: cornerRadius))
    }

    /// Paints a More night sky behind the view, edge to edge.
    func moreSkyBackground(_ sky: MoreSky) -> some View {
        background(sky.gradient.ignoresSafeArea())
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
