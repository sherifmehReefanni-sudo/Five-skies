import SwiftUI

/// Memorise: pick a sura, pick an ayah range, then practise one ayah at a time.
struct MemorizeView: View {
    @EnvironmentObject private var quran: QuranStore
    @ObservedObject private var progress = MemorizeProgressStore.shared
    @State private var query = ""
    @State private var selected: Sura?

    init() {}

    var body: some View {
        content
            .quranSkyBackground()
            .foregroundStyle(.white)
            .navigationTitle("Memorize")
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch quran.state {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Loading the Quran")
                    .font(.headline)
                    .foregroundStyle(MorePalette.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("memorizeLoading")
        case .failed(let message):
            VStack(spacing: 8) {
                Text("The Quran could not be opened")
                    .font(.headline.weight(.heavy))
                Text(verbatim: message)
                    .font(.subheadline)
                    .foregroundStyle(MorePalette.secondaryText)
            }
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("memorizeFailed")
        case .loaded(let data):
            list(data)
                .searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search surahs"
                )
        }
    }

    private func list(_ data: QuranData) -> some View {
        let suras = QuranSearch.filter(data.suras, query: query)
        return List {
            VStack(alignment: .leading, spacing: 6) {
                MoreScreenTitle(text: "Memorize", identifier: "memorizeTitle")
                Text("Choose a surah, then the ayahs to practise.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .quranListRow()

            if suras.isEmpty {
                Text("No surahs match your search.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .quranListRow()
            }

            ForEach(suras) { sura in
                Button {
                    selected = sura
                } label: {
                    MemorizeSuraRow(
                        sura: sura,
                        known: progress.knownCount(in: MemorizeText.refs(sura: sura.number, range: 1...max(1, sura.ayahCount)))
                    )
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel(Text(verbatim: "\(sura.number), \(sura.transliteratedName), \(sura.englishName), \(sura.ayahCount) ayahs"))
                .accessibilityIdentifier("memorizeSura-\(sura.number)")
                .quranListRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationDestination(item: $selected) { sura in
            MemorizeSetupView(sura: sura, progress: progress)
        }
    }
}

private struct MemorizeSuraRow: View {
    let sura: Sura
    let known: Int

    var body: some View {
        HStack(spacing: 12) {
            SuraNumberBadge(number: sura.number)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: sura.transliteratedName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(verbatim: "\(sura.englishName) · \(sura.ayahCount) ayahs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            if known > 0 {
                Text(verbatim: "\(known) known")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(MorePalette.mint)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(MorePalette.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .moreGlass(.light, cornerRadius: 22)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Picks the ayah range to practise.
struct MemorizeSetupView: View {
    let sura: Sura
    @ObservedObject var progress: MemorizeProgressStore

    @State private var from: Int = 1
    @State private var to: Int = 1
    @State private var didSetDefaults = false

    var body: some View {
        let count = max(1, sura.ayahCount)
        let refs = MemorizeText.refs(sura: sura.number, range: from...max(from, to))
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    MoreCaption(text: "Surah \(sura.number)")
                    Text(verbatim: sura.transliteratedName)
                        .font(.largeTitle.weight(.heavy))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("memorizeSetupTitle")
                    Text(verbatim: "\(sura.englishName) · \(sura.ayahCount) ayahs")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                }

                VStack(alignment: .leading, spacing: 12) {
                    MoreCaption(text: "Ayahs")
                    Stepper(value: $from, in: 1...count) {
                        Text("From ayah \(from)")
                            .font(.headline)
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("memorizeFrom")
                    Stepper(value: $to, in: 1...count) {
                        Text("To ayah \(to)")
                            .font(.headline)
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("memorizeTo")
                    Text(verbatim: "\(progress.knownCount(in: refs)) of \(refs.count) marked known")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                }
                .padding(18)
                .moreGlass(.dark, cornerRadius: 24)

                NavigationLink {
                    MemorizePracticeView(sura: sura, range: from...max(from, to), progress: progress)
                } label: {
                    Text("Start")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(MorePalette.ink)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Capsule().fill(MorePalette.goldGradient))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityIdentifier("memorizeStart")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .quranSkyBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didSetDefaults else { return }
            didSetDefaults = true
            from = 1
            to = min(count, 10)
        }
        .onChange(of: from) { _, value in
            if to < value {
                to = value
            }
        }
        .onChange(of: to) { _, value in
            if from > value {
                from = value
            }
        }
    }
}
