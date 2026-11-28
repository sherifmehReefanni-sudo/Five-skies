import SwiftUI

/// One field that takes "2:255", a surah number or name, "page 50" or "juz 30",
/// with live suggestions under it. Go, the return key or a suggestion opens the reader there.
struct QuranGoToSheet: View {
    let data: QuranData
    let onGo: (QuranReaderTarget) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool
    @State private var text = ""
    @State private var goCount = 0

    init(data: QuranData, onGo: @escaping (QuranReaderTarget) -> Void) {
        self.data = data
        self.onGo = onGo
    }

    var body: some View {
        let parsed = QuranGoTo.parse(text, data: data)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(MorePalette.gold)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("goToCancel")
                }
                MoreScreenTitle(text: "Go to", identifier: "goToTitle")
                field
                results(parsed)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.never)
        .safeAreaInset(edge: .bottom) {
            goButton(parsed)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(MorePalette.ink.opacity(0.7).ignoresSafeArea())
        }
        .quranSkyBackground()
        .sensoryFeedback(.selection, trigger: goCount)
        .onAppear {
            fieldFocused = true
        }
    }

    // MARK: - Field

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.turn.down.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(QuranPalette.gold)
                .accessibilityHidden(true)
            TextField(
                "Go to",
                text: $text,
                prompt: Text(QuranGoTo.hint).foregroundStyle(Color.white.opacity(0.6))
            )
            .font(.body.weight(.semibold))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($fieldFocused)
            .onSubmit {
                go(QuranGoTo.parse(text, data: data))
            }
            .accessibilityIdentifier("goToField")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(MorePalette.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
                .accessibilityIdentifier("goToClear")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, text.isEmpty ? 16 : 4)
        .frame(minHeight: 52)
        .moreGlass(.dark, cornerRadius: 22)
    }

    // MARK: - Results

    @ViewBuilder
    private func results(_ parsed: QuranGoToResult) -> some View {
        switch parsed {
        case .target(let target, let label):
            row(title: label, detail: detail(for: target), index: 0) {
                go(parsed)
            }
        case .suggestions(let suggestions):
            MoreCaption(text: "Did you mean")
                .padding(.top, 4)
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                row(title: suggestion.title, detail: suggestion.detail, index: index) {
                    finish(suggestion.target)
                }
            }
        case .nothing:
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? "Type a surah and ayah, a surah name, a page or a juz."
                 : "Nothing found yet. Try 2:255, Yasin, page 50 or juz 30.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
                .padding(.horizontal, 4)
                .accessibilityIdentifier("goToHelp")
        }
    }

    private func detail(for target: QuranReaderTarget) -> String {
        guard let sura = data.sura(target.sura) else { return "" }
        return "Surah \(sura.number) · \(sura.englishName) · \(sura.ayahCount) ayahs"
    }

    private func row(title: String, detail: String, index: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    if !detail.isEmpty {
                        Text(verbatim: detail)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MorePalette.secondaryText)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .moreGlass(.light, cornerRadius: 22)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityIdentifier("goToSuggestion-\(index)")
    }

    // MARK: - Go

    private func goButton(_ parsed: QuranGoToResult) -> some View {
        let enabled = parsed.destination != nil
        return Button {
            go(parsed)
        } label: {
            Text("Go")
                .font(.headline.weight(.heavy))
                .foregroundStyle(MorePalette.ink)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(MorePalette.goldGradient)
                )
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityIdentifier("goToGo")
    }

    private func go(_ parsed: QuranGoToResult) {
        guard let target = parsed.destination else { return }
        finish(target)
    }

    private func finish(_ target: QuranReaderTarget) {
        goCount += 1
        fieldFocused = false
        onGo(target)
        dismiss()
    }
}
