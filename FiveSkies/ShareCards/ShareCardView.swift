import SwiftUI

/// The image sizes an ayah card can be shared at.
enum ShareCardFormat: String, CaseIterable, Identifiable {
    case story
    case square
    case wallpaper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .story: return "Story"
        case .square: return "Square"
        case .wallpaper: return "Wallpaper"
        }
    }

    var pixelSize: CGSize {
        switch self {
        case .story: return CGSize(width: 1080, height: 1920)
        case .square: return CGSize(width: 1080, height: 1080)
        case .wallpaper: return CGSize(width: 1290, height: 2796)
        }
    }

    /// The layout size in points; the image is rendered at 3x this.
    var pointSize: CGSize {
        SkyImageRenderer.pointSize(forPixels: pixelSize)
    }

    /// Where the text block starts and ends, as fractions of the height.
    /// The wallpaper starts lower to leave room for the lock screen clock.
    var textBand: (top: CGFloat, bottom: CGFloat) {
        switch self {
        case .story: return (0.14, 0.66)
        case .square: return (0.08, 0.68)
        case .wallpaper: return (0.3, 0.7)
        }
    }

    /// The Arabic size before any shrinking to fit.
    var arabicSize: CGFloat {
        switch self {
        case .story: return 34
        case .square: return 28
        case .wallpaper: return 36
        }
    }
}

/// The card itself: sky, skyline, the ayah as stored, its reference and the app mark.
/// Laid out at the format's point size, both for the preview and for the rendered image.
struct ShareCardArt: View {
    let text: String
    let reference: String
    let sky: Prayer
    let format: ShareCardFormat

    var body: some View {
        let size = format.pointSize
        let band = format.textBand
        let fontSize = format.arabicSize
        return ZStack(alignment: .top) {
            SkyView(phase: sky, showsCelestial: false, themeOverride: .living, fillsScreen: false)
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: size.height * band.top)
                VStack(spacing: 14) {
                    Text(verbatim: text)
                        .font(QuranPalette.arabicFont(size: fontSize))
                        .lineSpacing(fontSize * 0.35)
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .environment(\.layoutDirection, .rightToLeft)
                        .quranSpeechLanguage("ar")
                        .shadow(color: Color.black.opacity(0.45), radius: 6, y: 2)
                    Text(verbatim: reference)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(QuranPalette.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(18)
                .frame(height: size.height * (band.bottom - band.top))
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(MorePalette.ink.opacity(0.32))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
                .padding(.horizontal, 22)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("Five Skies")
                        .font(.system(size: 13, weight: .heavy))
                }
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.bottom, size.height * 0.04)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// The "Share as image" sheet: a live preview, a sky, a format and the Share button.
struct ShareCardView: View {
    /// Above this many characters the card gets small text, so sharing as text is suggested.
    static let longAyahLength = 300

    let ayah: Ayah
    let sura: Sura

    @Environment(\.dismiss) private var dismiss
    @State private var sky: Prayer = .isha
    @State private var format: ShareCardFormat = .story
    @State private var shareImage: SkySharedImage?
    @State private var isRendering = false

    init(ayah: Ayah, sura: Sura) {
        self.ayah = ayah
        self.sura = sura
    }

    private var reference: String {
        "\(sura.transliteratedName) \(sura.number):\(ayah.number)"
    }

    private var isLong: Bool {
        ayah.text.count > Self.longAyahLength
    }

    private var art: ShareCardArt {
        ShareCardArt(text: ayah.text, reference: reference, sky: sky, format: format)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    preview
                    if isLong {
                        Text("This ayah is long. Sharing as text works better.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(MorePalette.goldLight)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("shareCardLongNote")
                    }
                    swatches
                    formats
                    shareButton
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(MorePalette.ink.ignoresSafeArea())
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Share")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("shareCardTitle")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("shareCardDone")
                }
            }
            .toolbarBackground(MorePalette.ink, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(item: $shareImage) { item in
            QuranActivityView(items: [item.image])
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Preview

    private var preview: some View {
        let size = format.pointSize
        let height: CGFloat = 400
        let scale = min(height / size.height, 320 / size.width)
        return art
            .environment(\.ambientMotionEnabled, false)
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
            .clipShape(RoundedRectangle(cornerRadius: 22 * scale + 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22 * scale + 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 18, y: 12)
            .frame(maxWidth: .infinity, minHeight: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Card preview, \(reference)"))
            .accessibilityIdentifier("shareCardPreview")
    }

    // MARK: - Choices

    private var swatches: some View {
        VStack(alignment: .leading, spacing: 8) {
            MoreCaption(text: "Sky")
            HStack(spacing: 12) {
                ForEach(Prayer.allCases) { prayer in
                    let selected = prayer == sky
                    Button {
                        sky = prayer
                    } label: {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: SkyStyle.style(for: prayer).skyStops),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 44, height: 44)
                            .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 1 : 0.3), lineWidth: selected ? 3 : 1))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleButtonStyle(pressedScale: 0.92))
                    .accessibilityLabel(Text("\(prayer.displayName) sky"))
                    .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
                    .accessibilityIdentifier("shareSky-\(prayer.rawValue)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formats: some View {
        VStack(alignment: .leading, spacing: 8) {
            MoreCaption(text: "Format")
            HStack(spacing: 8) {
                ForEach(ShareCardFormat.allCases) { item in
                    let selected = item == format
                    Button {
                        format = item
                    } label: {
                        Text(item.title)
                            .font(.footnote.weight(.heavy))
                            .foregroundStyle(selected ? MorePalette.ink : Color.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                Capsule().fill(selected ? Color.white : Color.white.opacity(0.08))
                            )
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
                    .accessibilityIdentifier("shareFormat-\(item.rawValue)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shareButton: some View {
        Button(action: share) {
            Group {
                if isRendering {
                    ProgressView()
                        .tint(MorePalette.ink)
                } else {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.headline.weight(.heavy))
                }
            }
            .foregroundStyle(MorePalette.ink)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Capsule().fill(MorePalette.goldGradient))
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(isRendering)
        .accessibilityIdentifier("shareCardShare")
    }

    private func share() {
        isRendering = true
        let card = art
        let pixels = format.pixelSize
        Task { @MainActor in
            await Task.yield()
            let image = SkyImageRenderer.render(card, pixels: pixels)
            isRendering = false
            if let image {
                shareImage = SkySharedImage(image: image)
            }
        }
    }
}
