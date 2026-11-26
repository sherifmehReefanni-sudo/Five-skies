import SwiftUI

/// Colors and fonts for the Quran tab, taken from the reader mockup.
enum QuranPalette {
    static let cream = Color(hex: 0xFFE9B8)
    static let gold = Color(hex: 0xF3C97A)
    static let arabicText = Color(hex: 0xE9EDF2)

    /// The PostScript name of the bundled Amiri Quran typeface.
    static let arabicFontName = "AmiriQuran-Regular"

    static func arabicFont(size: CGFloat) -> Font {
        Font.custom(arabicFontName, size: size)
    }

    /// Night sky behind the Quran screens. Ends dark so the tab bar stays legible.
    static let sky = LinearGradient(
        colors: [
            Color(hex: 0x071433),
            Color(hex: 0x16306B),
            Color(hex: 0x3A3F8F),
            Color(hex: 0x5B4A8F),
            Color(hex: 0x2A1638)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension View {
    /// Paints the Quran night sky behind the view, edge to edge.
    func quranSkyBackground() -> some View {
        background(QuranPalette.sky.ignoresSafeArea())
    }

    /// Tells VoiceOver which language the text below is in.
    /// SwiftUI has no direct speech language modifier, so this sets the locale, which VoiceOver follows.
    func quranSpeechLanguage(_ identifier: String) -> some View {
        environment(\.locale, Locale(identifier: identifier))
    }

    /// A row in the Quran lists: clear background, no separator, card spacing.
    func quranListRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }

    /// A gentle fade in the first time the view appears. Off when motion is off.
    func quranFadeIn() -> some View {
        modifier(QuranFadeInModifier())
    }
}

private struct QuranFadeInModifier: ViewModifier {
    @Environment(\.motionEnabled) private var motionEnabled
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || !motionEnabled ? 1 : 0)
            .onAppear {
                guard !shown else { return }
                if motionEnabled {
                    withAnimation(.easeOut(duration: 0.35)) {
                        shown = true
                    }
                } else {
                    shown = true
                }
            }
    }
}

/// A sura number inside a small gold eight-point star, drawn with two rounded squares.
struct SuraNumberBadge: View {
    let number: Int
    var size: CGFloat = 36

    var body: some View {
        let side = size * 0.72
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
                .fill(MorePalette.goldGradient)
                .frame(width: side, height: side)
            RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
                .fill(MorePalette.goldGradient)
                .frame(width: side, height: side)
                .rotationEffect(.degrees(45))
            Text(verbatim: String(number))
                .font(.system(size: size * 0.33, weight: .heavy))
                .foregroundStyle(MorePalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 3)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The small round ayah number marker shown after each ayah, in Latin digits.
struct AyahNumberMarker: View {
    let number: Int

    var body: some View {
        Text(verbatim: String(number))
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(QuranPalette.gold)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: 30, height: 30)
            .background(Circle().fill(MorePalette.ink.opacity(0.45)))
            .overlay(Circle().strokeBorder(QuranPalette.gold.opacity(0.8), lineWidth: 1.2))
            .accessibilityHidden(true)
    }
}
