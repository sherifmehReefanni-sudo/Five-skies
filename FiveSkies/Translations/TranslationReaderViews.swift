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

/// The "Translation" row of the reader's "Aa" sheet.
struct TranslationSettingsRow: View {
    @EnvironmentObject private var translations: TranslationStore
    @State private var showsPicker = false

    init() {}

    var body: some View {
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
