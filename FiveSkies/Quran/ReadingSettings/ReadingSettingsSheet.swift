import SwiftUI

/// The one Reading sheet behind the reader's "Aa" button (E1.3): Arabic size, the meaning
/// (on or off, and which translation), transliteration, and the background.
/// Needs the `TranslationStore` environment object. Suggested detents: `[.medium, .large]`.
struct ReadingSettingsSheet: View {
    @EnvironmentObject private var translations: TranslationStore

    @AppStorage(ReadingPreferences.textSizeKey) private var textSize: Double = ReadingPreferences.defaultTextSize
    @AppStorage(ReadingPreferences.showsTranslationKey) private var showsTranslation: Bool = ReadingPreferences.defaultShowsTranslation
    @AppStorage(ReadingPreferences.backgroundKey) private var background: QuranBackground = ReadingPreferences.defaultBackground

    @State private var showsPicker = false

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Reading")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("readingSheetTitle")

                section("Arabic") {
                    sizeCard
                }

                section("Meaning") {
                    meaningCard
                    translationButton
                }

                section("Transliteration") {
                    TransliterationToggleRow()
                }

                section("Background") {
                    backgroundCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .foregroundStyle(.white)
        .background(MorePalette.ink.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: background)
        .sensoryFeedback(.selection, trigger: showsTranslation)
        .onChange(of: translations.selectedID) { _, newID in
            // Picking a translation means wanting to see it.
            if newID != nil {
                showsTranslation = true
            }
        }
        .sheet(isPresented: $showsPicker) {
            TranslationPickerView()
                .environmentObject(translations)
                .presentationDetents([.large])
        }
    }

    // MARK: - Sections

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MoreCaption(text: title)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    // MARK: - Arabic size

    private var clampedSize: Double {
        ReadingPreferences.clamped(textSize)
    }

    private var sizeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                // A neutral sample that grows with the slider. Not Quran text.
                Text("Text size")
                    .font(.system(size: CGFloat(clampedSize), weight: .semibold))
                    .foregroundStyle(QuranPalette.arabicText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("readingSizeSample")
                Spacer(minLength: 8)
                Text(verbatim: "\(Int(clampedSize.rounded())) pt")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: CGFloat(ReadingPreferences.textSizeRange.upperBound) * 1.25, alignment: .bottomLeading)

            Slider(
                value: Binding(
                    get: { clampedSize },
                    set: { textSize = ReadingPreferences.clamped($0) }
                ),
                in: ReadingPreferences.textSizeRange,
                step: 1
            ) {
                Text("Arabic text size")
            } minimumValueLabel: {
                Text("A")
                    .font(.footnote.weight(.bold))
                    .accessibilityHidden(true)
            } maximumValueLabel: {
                Text("A")
                    .font(.title2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .tint(MorePalette.gold)
            .accessibilityValue(Text(verbatim: "\(Int(clampedSize.rounded())) points"))
            .accessibilityIdentifier("textSizeSlider")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .moreGlass(.light, cornerRadius: 18)
    }

    // MARK: - Meaning

    private var meaningCard: some View {
        Toggle(isOn: $showsTranslation) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Show meaning")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("The translation under each ayah")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .lineLimit(2)
            }
        }
        .tint(MorePalette.gold)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .moreGlass(.light, cornerRadius: 18)
        .accessibilityIdentifier("readingShowMeaningToggle")
    }

    private var translationButton: some View {
        Button {
            showsPicker = true
        } label: {
            HStack(spacing: 8) {
                Text("Translation")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(verbatim: currentTranslationName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .moreGlass(.light, cornerRadius: 18)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle(pressedScale: 0.98))
        .accessibilityLabel(Text("Translation"))
        .accessibilityValue(Text(verbatim: currentTranslationName))
        .accessibilityHint(Text("Choose which translation shows under each ayah"))
        .accessibilityIdentifier("readingTranslationRow")
    }

    private var currentTranslationName: String {
        if let loaded = translations.loaded, loaded.summary.id == translations.selectedID {
            return loaded.summary.name
        }
        if let id = translations.selectedID, let summary = translations.summary(for: id) {
            return summary.name
        }
        return translations.isConnected ? "None" : "Coming soon"
    }

    // MARK: - Background

    private var backgroundCard: some View {
        HStack(spacing: 12) {
            ForEach(QuranBackground.allCases) { option in
                backgroundSwatch(option)
            }
        }
        .padding(12)
        .moreGlass(.light, cornerRadius: 18)
    }

    private func backgroundSwatch(_ option: QuranBackground) -> some View {
        let isSelected = background == option
        return Button {
            background = option
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    QuranBackgroundFill(background: option)
                        .frame(height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    isSelected ? MorePalette.gold : Color.white.opacity(0.25),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(MorePalette.gold)
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
                Text(verbatim: option.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : MorePalette.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(pressedScale: 0.97))
        .accessibilityLabel(Text(verbatim: "\(option.title) background"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("readingBackground-\(option.rawValue)")
    }
}
