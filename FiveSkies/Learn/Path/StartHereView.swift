import SwiftUI

/// The Start here path: one card per surah, with how much of it is known.
/// "Learn" hands the surah to the lead, who opens the reader in the Memorize preset.
/// "Read" opens the reader at ayah 1. Pushed inside the Learn tab's NavigationStack.
@MainActor
struct StartHereView: View {
    let data: QuranData
    let onLearn: (Int) -> Void
    let onOpen: (QuranReaderTarget) -> Void

    @ObservedObject private var progress: MemorizeProgressStore

    init(data: QuranData, onLearn: @escaping (Int) -> Void, onOpen: @escaping (QuranReaderTarget) -> Void) {
        self.data = data
        self.onLearn = onLearn
        self.onOpen = onOpen
        _progress = ObservedObject(wrappedValue: MemorizeProgressStore.shared)
    }

    var body: some View {
        let steps = makeSteps()
        let nextSura = StartHerePath.nextStep(known: Set(steps.filter(\.isComplete).map(\.sura.number)))
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MoreScreenTitle(text: "Start here", identifier: "startHereTitle")
                Text("Short surahs in a gentle order, starting with Al-Faatiha.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)

                if nextSura == nil, !steps.isEmpty {
                    Label("You know every surah on this path. Well done.", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(MorePalette.mint)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("pathAllKnown")
                }

                ForEach(steps) { step in
                    StartHereStepCard(
                        step: step,
                        isNext: step.sura.number == nextSura,
                        onLearn: { onLearn(step.sura.number) },
                        onRead: { onOpen(QuranReaderTarget(sura: step.sura.number, aya: 1)) }
                    )
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .quranSkyBackground()
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("startHere")
    }

    private func makeSteps() -> [StartHereStep] {
        var steps: [StartHereStep] = []
        for (offset, number) in StartHerePath.surahs.enumerated() {
            guard let sura = data.sura(number) else { continue }
            let known = progress.knownCount(in: StartHerePath.refs(sura: number, ayahCount: sura.ayahCount))
            steps.append(StartHereStep(position: offset + 1, sura: sura, known: known))
        }
        return steps
    }
}

/// One step on the path, worked out from the store and the Quran data.
private struct StartHereStep: Identifiable {
    let position: Int
    let sura: Sura
    let known: Int

    var id: Int { sura.number }

    var isComplete: Bool {
        StartHerePath.isComplete(known: known, ayahCount: sura.ayahCount)
    }
}

private struct StartHereStepCard: View {
    let step: StartHereStep
    let isNext: Bool
    let onLearn: () -> Void
    let onRead: () -> Void

    var body: some View {
        let name = step.sura.transliteratedName
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(verbatim: String(step.position))
                    .font(.headline.weight(.black))
                    .monospacedDigit()
                    .foregroundStyle(isNext ? MorePalette.ink : Color.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(isNext ? AnyShapeStyle(MorePalette.goldGradient) : AnyShapeStyle(Color.white.opacity(0.14)))
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(verbatim: name)
                            .font(.headline.weight(.heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if isNext {
                            Text("Next")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(MorePalette.ink)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(MorePalette.goldGradient))
                                .accessibilityIdentifier("pathNext-\(step.sura.number)")
                        }
                        Spacer(minLength: 4)
                        if step.isComplete {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title3)
                                .foregroundStyle(QuranPalette.gold)
                                .accessibilityLabel("All known")
                                .accessibilityIdentifier("pathSeal-\(step.sura.number)")
                        }
                    }
                    Text(verbatim: "\(step.sura.englishName) · \(step.sura.ayahCount) ayahs")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                    Text(verbatim: StartHerePath.progressText(known: step.known, ayahCount: step.sura.ayahCount))
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(step.known > 0 ? MorePalette.mint : MorePalette.secondaryText)
                        .accessibilityIdentifier("pathProgress-\(step.sura.number)")
                }
            }

            HStack(spacing: 8) {
                Button(action: onLearn) {
                    Label("Learn", systemImage: "graduationcap")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(MorePalette.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(StartHereButtonFill(filled: true))
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel(Text(verbatim: "Learn \(name)"))
                .accessibilityIdentifier("pathLearn-\(step.sura.number)")

                Button(action: onRead) {
                    Label("Read", systemImage: "book")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(StartHereButtonFill(filled: false))
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel(Text(verbatim: "Read \(name)"))
                .accessibilityIdentifier("pathRead-\(step.sura.number)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(isNext ? .dark : .light, cornerRadius: 24)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isNext ? MorePalette.gold.opacity(0.8) : Color.clear, lineWidth: 1.5)
                .allowsHitTesting(false)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pathStep-\(step.sura.number)")
    }
}

private struct StartHereButtonFill: View {
    let filled: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if filled {
            shape.fill(MorePalette.goldGradient)
        } else {
            shape.fill(Color.white.opacity(0.1))
                .overlay(shape.strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        }
    }
}
