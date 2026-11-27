import SwiftUI

/// Choose, download and remove translations. Opened from the reader's "Aa" sheet.
struct TranslationPickerView: View {
    @EnvironmentObject private var translations: TranslationStore
    @Environment(\.dismiss) private var dismiss

    init() {}

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Translation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("translationPickerDone")
                    }
                }
                .background(MorePalette.ink.ignoresSafeArea())
        }
        .task {
            await translations.loadCatalog()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !translations.isConnected && translations.downloaded.isEmpty {
            message("Translations will be available soon.", identifier: "translationsNotConnected")
        } else {
            List {
                Section {
                    noneRow
                }
                .listRowBackground(Color.white.opacity(0.08))

                catalogSections
            }
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("translationList")
        }
    }

    @ViewBuilder
    private var catalogSections: some View {
        if !translations.isConnected {
            downloadedSection(note: "Translations will be available soon.")
        } else {
            switch translations.catalogState {
            case .idle, .loading:
                if translations.catalog.isEmpty {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading translations")
                                .foregroundStyle(MorePalette.secondaryText)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("translationsLoading")
                    }
                    .listRowBackground(Color.white.opacity(0.08))
                } else {
                    languageSections
                }
            case .failed(let text):
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(verbatim: text)
                            .foregroundStyle(MorePalette.secondaryText)
                        Button("Retry") {
                            Task { await translations.loadCatalog(force: true) }
                        }
                        .buttonStyle(.borderless)
                        .font(.headline)
                        .foregroundStyle(MorePalette.gold)
                        .accessibilityIdentifier("translationsRetry")
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.white.opacity(0.08))
                downloadedSection(note: nil)
            case .loaded:
                languageSections
            }
        }
    }

    @ViewBuilder
    private var languageSections: some View {
        ForEach(TranslationText.groupedByLanguage(translations.catalog)) { group in
            Section {
                ForEach(group.translations) { info in
                    TranslationRow(
                        id: info.id,
                        name: info.name,
                        authorName: info.authorName,
                        info: info,
                        isSuggested: translations.suggestion?.id == info.id
                    )
                }
            } header: {
                Text(verbatim: group.language)
                    .foregroundStyle(MorePalette.secondaryText)
            }
            .listRowBackground(Color.white.opacity(0.08))
        }
    }

    /// Copies on the device, for when the catalog cannot be shown.
    @ViewBuilder
    private func downloadedSection(note: String?) -> some View {
        if !translations.downloaded.isEmpty {
            Section {
                ForEach(translations.downloaded) { summary in
                    TranslationRow(id: summary.id, name: summary.name, authorName: summary.authorName, info: nil, isSuggested: false)
                }
            } header: {
                Text("On this iPhone")
                    .foregroundStyle(MorePalette.secondaryText)
            } footer: {
                if let note {
                    Text(verbatim: note)
                }
            }
            .listRowBackground(Color.white.opacity(0.08))
        }
    }

    private var noneRow: some View {
        Button {
            translations.select(nil)
        } label: {
            HStack {
                Text("No translation")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if translations.selectedID == nil {
                    Image(systemName: "checkmark")
                        .foregroundStyle(MorePalette.gold)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(translations.selectedID == nil ? .isSelected : [])
        .accessibilityIdentifier("translationNone")
    }

    private func message(_ text: String, identifier: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "text.book.closed")
                .font(.largeTitle)
                .foregroundStyle(MorePalette.gold)
                .accessibilityHidden(true)
            Text(text)
                .font(.headline)
                .foregroundStyle(MorePalette.secondaryText)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier(identifier)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One translation: name, author, last updated, and its Download / Selected / Remove control.
private struct TranslationRow: View {
    let id: Int
    let name: String
    let authorName: String?
    /// Needed to download; nil for rows built from the copy on the device.
    let info: TranslationInfo?
    let isSuggested: Bool

    @EnvironmentObject private var translations: TranslationStore

    init(id: Int, name: String, authorName: String?, info: TranslationInfo?, isSuggested: Bool) {
        self.id = id
        self.name = name
        self.authorName = authorName
        self.info = info
        self.isSuggested = isSuggested
    }

    var body: some View {
        let summary = translations.summary(for: id)
        let isSelected = translations.selectedID == id
        let activity = translations.activity[id]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if let authorName, !authorName.isEmpty {
                        Text(verbatim: authorName)
                            .font(.subheadline)
                            .foregroundStyle(MorePalette.secondaryText)
                    }
                    if isSuggested && summary == nil {
                        Text("Suggested")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(MorePalette.gold)
                    }
                }
                Spacer(minLength: 8)
                control(summary: summary, isSelected: isSelected, activity: activity)
            }

            if let summary {
                Text(lastUpdatedText(summary))
                    .font(.caption)
                    .foregroundStyle(MorePalette.secondaryText)
            }

            if case .some(.failed(let text)) = activity {
                HStack(spacing: 8) {
                    Text(verbatim: text)
                        .font(.caption)
                        .foregroundStyle(Color(hex: 0xFFB4A8))
                    Button("Retry") {
                        retry(summary: summary)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(MorePalette.gold)
                    .disabled(summary == nil && info == nil)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("translationRow-\(id)")
    }

    @ViewBuilder
    private func control(summary: TranslationSummary?, isSelected: Bool, activity: TranslationStore.Activity?) -> some View {
        switch activity {
        case .some(.downloading(let value)):
            ProgressView(value: value)
                .frame(width: 70)
                .tint(MorePalette.gold)
                .accessibilityLabel(Text("Downloading"))
                .accessibilityValue(Text(verbatim: "\(Int((value * 100).rounded())) percent"))
        case .some(.refreshing):
            ProgressView()
                .accessibilityLabel(Text("Updating"))
        case .some(.failed), .none:
            if summary != nil {
                HStack(spacing: 8) {
                    if isSelected {
                        Label("Selected", systemImage: "checkmark")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(MorePalette.gold)
                            .accessibilityIdentifier("translationSelected-\(id)")
                    } else {
                        pill("Use", identifier: "translationUse-\(id)") {
                            translations.select(id)
                        }
                        .accessibilityLabel(Text(verbatim: "Use \(name)"))
                    }
                    Button(role: .destructive) {
                        translations.remove(id: id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color(hex: 0xFFB4A8))
                    .accessibilityLabel(Text(verbatim: "Remove \(name)"))
                    .accessibilityIdentifier("translationRemove-\(id)")
                }
            } else if let info {
                pill("Download", identifier: "translationDownload-\(id)") {
                    translations.download(info)
                }
                .accessibilityLabel(Text(verbatim: "Download \(name)"))
            }
        }
    }

    private func pill(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(MorePalette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(MorePalette.goldGradient))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityIdentifier(identifier)
    }

    private func retry(summary: TranslationSummary?) {
        if summary != nil {
            Task { await translations.refresh(id: id) }
        } else if let info {
            translations.download(info)
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
