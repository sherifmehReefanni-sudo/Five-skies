import SwiftUI

/// One compact glass card on Today: "Continue: Al-Baqara, ayah 45", for whichever of
/// reading or listening was last. Tapping opens the reader there. Shows nothing when there is
/// nothing to continue. Carries its own padding like `DayCardsView`, so place it without any.
/// With `-FSFixedPhase` it shows nothing, unless `-FSContinueSample` asks for a sample entry.
/// No timer of its own: it follows `now`, which Today already refreshes.
struct ContinueCard: View {
    let now: Date

    @EnvironmentObject private var quran: QuranStore
    @EnvironmentObject private var navigator: QuranNavigator
    @ObservedObject private var store: ContinueStore
    @State private var tapCount = 0

    private let mode: ContinueCardMode

    init(now: Date, store: ContinueStore = .shared, mode: ContinueCardMode = ContinueCardMode()) {
        self.now = now
        _store = ObservedObject(wrappedValue: store)
        self.mode = mode
    }

    var body: some View {
        let entry = mode.displayedEntry(stored: store.entry(now: now), now: now)
        VStack(spacing: 0) {
            if let entry {
                card(entry)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
        .sensoryFeedback(.selection, trigger: tapCount)
    }

    private func card(_ entry: ContinueEntry) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let suraName = quran.sura(entry.sura)?.transliteratedName
        let title = ContinueCardText.title(for: entry, suraName: suraName)
        let subtitle = ContinueCardText.subtitle(for: entry)
        return Button {
            tapCount += 1
            navigator.open(QuranReaderTarget(sura: entry.sura, aya: entry.ayah))
        } label: {
            HStack(spacing: 9) {
                Image(systemName: ContinueCardText.symbol(for: entry.kind))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(MorePalette.gold)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title)
                        .font(.footnote.weight(.heavy))
                        .foregroundStyle(.white)
                    Text(verbatim: subtitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
            .background(shape.fill(Color(hex: 0x120B1F, opacity: 0.88)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(PressScaleButtonStyle())
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(title). \(subtitle)"))
        .accessibilityHint(Text("Opens the Quran at this place"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("continueCard")
    }
}

/// When the card shows its stored entry, nothing, or the screenshot sample.
struct ContinueCardMode {
    static let sampleArgument = "-FSContinueSample"

    let isFixedPhase: Bool
    let wantsSample: Bool

    init(isFixedPhase: Bool, wantsSample: Bool) {
        self.isFixedPhase = isFixedPhase
        self.wantsSample = wantsSample
    }

    init(processInfo: ProcessInfo = .processInfo) {
        isFixedPhase = LaunchOptions(processInfo: processInfo).fixedPhase != nil
        wantsSample = processInfo.arguments.contains(Self.sampleArgument)
    }

    /// The sample for screenshots: Al-Baqara, ayah 45, reading.
    static func sample(now: Date) -> ContinueEntry {
        ContinueEntry(kind: .reading, sura: 2, ayah: 45, reciterName: nil, date: now)
    }

    func displayedEntry(stored: ContinueEntry?, now: Date) -> ContinueEntry? {
        // Like the other testing hooks, the sample only takes effect together with `-FSFixedPhase`.
        if isFixedPhase {
            return wantsSample ? Self.sample(now: now) : nil
        }
        return ContinueStore.visible(stored, now: now)
    }
}

/// The card's words, kept apart so tests can check them.
enum ContinueCardText {
    /// "Continue: Al-Baqara, ayah 45", or "Continue: Al-Baqara" without an ayah.
    /// Falls back to "Surah 2" while the Quran is still loading.
    static func title(for entry: ContinueEntry, suraName: String?) -> String {
        let name = suraName ?? "Surah \(entry.sura)"
        if let ayah = entry.ayah {
            return "Continue: \(name), ayah \(ayah)"
        }
        return "Continue: \(name)"
    }

    /// "Reading", or "Listening · <reciter>".
    static func subtitle(for entry: ContinueEntry) -> String {
        switch entry.kind {
        case .reading:
            return "Reading"
        case .listening:
            let reciter = entry.reciterName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return reciter.isEmpty ? "Listening" : "Listening \u{00B7} \(reciter)"
        }
    }

    static func symbol(for kind: ContinueKind) -> String {
        switch kind {
        case .reading:
            return "book.fill"
        case .listening:
            return "headphones"
        }
    }
}
