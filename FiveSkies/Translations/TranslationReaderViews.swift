import SwiftUI

/// A translation line under an ayah: left to right, body font, secondary colour, Dynamic Type.
struct AyahTranslationText: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.body)
            .foregroundStyle(MorePalette.secondaryText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// The attribution under the reader: translation name, translator, Quran Foundation, last updated.
struct TranslationAttributionFooter: View {
    let summary: TranslationSummary
    let needsRefresh: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(verbatim: TranslationText.attribution(name: summary.name, authorName: summary.authorName))
                .accessibilityIdentifier("translationAttribution")
            Text(verbatim: lastUpdated)
                .font(.caption)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(MorePalette.secondaryText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var lastUpdated: String {
        let date = summary.lastSyncedAt.formatted(date: .abbreviated, time: .omitted)
        return needsRefresh ? "Last updated \(date). Will refresh when online." : "Last updated \(date)"
    }
}

/// The "Translation" row of the reader's "Aa" sheet, with the "Transliteration" switch under it.
struct TranslationSettingsRow: View {
    @EnvironmentObject private var translations: TranslationStore
    @State private var showsPicker = false

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            translationButton
            TransliterationToggleRow()
        }
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
                Text(verbatim: currentName)
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
        .accessibilityValue(Text(verbatim: currentName))
        .accessibilityHint(Text("Choose a translation to show under each ayah"))
        .accessibilityIdentifier("translationSettingsRow")
        .sheet(isPresented: $showsPicker) {
            TranslationPickerView()
                .environmentObject(translations)
                .presentationDetents([.large])
        }
    }

    private var currentName: String {
        if let loaded = translations.loaded, loaded.summary.id == translations.selectedID {
            return loaded.summary.name
        }
        if let id = translations.selectedID, let summary = translations.summary(for: id) {
            return summary.name
        }
        return translations.isConnected ? "None" : "Coming soon"
    }
}

// MARK: - Transliteration (W6, D6)

/// A transliteration line under an ayah, placed above the translation (W6 order).
/// Like `AyahTranslationText`, but italic and a little smaller.
struct AyahTransliterationText: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.callout)
            .italic()
            .foregroundStyle(MorePalette.secondaryText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityLabel(Text(verbatim: "Transliteration: \(text)"))
    }
}

/// The transliteration's credit line under the reader, for example
/// "Transliteration provided by Quran Foundation." Shows nothing when it is off.
struct TransliterationAttributionFooter: View {
    @EnvironmentObject private var translations: TranslationStore

    init() {}

    var body: some View {
        if let line = translations.transliterationAttribution, let summary = translations.transliterationLoaded?.summary {
            VStack(spacing: 4) {
                Text(verbatim: line)
                    .accessibilityIdentifier("transliterationAttribution")
                Text(verbatim: lastUpdated(summary))
                    .font(.caption)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(MorePalette.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    private func lastUpdated(_ summary: TranslationSummary) -> String {
        let date = summary.lastSyncedAt.formatted(date: .abbreviated, time: .omitted)
        return translations.needsRefresh(summary) ? "Last updated \(date). Will refresh when online." : "Last updated \(date)"
    }
}

/// The "Transliteration" switch of the reader's "Aa" sheet, with its source.
/// Already shown inside `TranslationSettingsRow()`, so the Aa sheet gets it with no change.
struct TransliterationToggleRow: View {
    @EnvironmentObject private var translations: TranslationStore

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $translations.showsTransliteration) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Transliteration")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(verbatim: sourceLine)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                        .lineLimit(2)
                }
            }
            .tint(MorePalette.gold)
            .disabled(!isAvailable)
            .accessibilityHint(Text("Shows how each ayah sounds, in Latin letters, above the translation"))
            .accessibilityIdentifier("transliterationToggle")

            status
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .moreGlass(.light, cornerRadius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transliterationRow")
        .task {
            // The catalog names the source; with a copy on the device it is not needed.
            if translations.transliterationSummary == nil {
                await translations.loadCatalog()
            }
        }
    }

    /// The switch can always be turned off; it can be turned on when a copy exists or the relay is set up.
    private var isAvailable: Bool {
        translations.showsTransliteration || translations.transliterationSummary != nil || translations.isConnected
    }

    private var sourceLine: String {
        if let source = translations.transliterationSource {
            return source
        }
        if !translations.isConnected {
            return "Coming soon"
        }
        return "Quran Foundation"
    }

    @ViewBuilder
    private var status: some View {
        switch translations.transliterationActivity {
        case .some(.downloading(let value)):
            HStack(spacing: 8) {
                ProgressView(value: value)
                    .tint(MorePalette.gold)
                Text("Downloading")
                    .font(.caption)
                    .foregroundStyle(MorePalette.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(Text(verbatim: "\(Int((value * 100).rounded())) percent"))
            .accessibilityIdentifier("transliterationDownloading")
        case .some(.refreshing):
            HStack(spacing: 8) {
                ProgressView()
                Text("Updating")
                    .font(.caption)
                    .foregroundStyle(MorePalette.secondaryText)
            }
            .accessibilityElement(children: .combine)
        case .some(.failed(let text)):
            HStack(spacing: 8) {
                Text(verbatim: text)
                    .font(.caption)
                    .foregroundStyle(Color(hex: 0xFFB4A8))
                Button("Retry") {
                    retry()
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.heavy))
                .foregroundStyle(MorePalette.gold)
                .accessibilityIdentifier("transliterationRetry")
            }
        case .none:
            if let summary = translations.transliterationSummary {
                HStack(spacing: 8) {
                    Text(lastUpdatedText(summary))
                        .font(.caption)
                        .foregroundStyle(MorePalette.secondaryText)
                    Spacer(minLength: 8)
                    Button(role: .destructive) {
                        Task { await translations.removeTransliteration() }
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color(hex: 0xFFB4A8))
                    .accessibilityLabel(Text("Remove transliteration from this iPhone"))
                    .accessibilityIdentifier("transliterationRemove")
                }
            }
        }
    }

    private func retry() {
        Task {
            if translations.transliterationSummary != nil {
                await translations.refreshTransliteration()
            } else {
                await translations.ensureTransliteration()
            }
        }
    }

    private func lastUpdatedText(_ summary: TranslationSummary) -> String {
        let date = summary.lastSyncedAt.formatted(date: .abbreviated, time: .omitted)
        if translations.needsRefresh(summary) {
            return "Last updated \(date). Needs refresh."
        }
        return "Last updated \(date)"
    }
}
