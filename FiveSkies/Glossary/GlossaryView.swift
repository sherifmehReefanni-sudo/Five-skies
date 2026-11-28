import SwiftUI

/// "Words used in the app": every glossary term A to Z with its plain meaning, searchable.
/// Has no NavigationStack of its own; push it, or wrap it in one for a sheet.
struct GlossaryView: View {
    @State private var query = ""

    init() {}

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    MoreScreenTitle(text: "Words used in the app", identifier: "glossary")
                    Text("Plain meanings of the words you will see in Five Skies. Where a word has a dotted line under it, tap it to see its meaning.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 4)

                let sections = GlossaryTerm.sections(matching: query)
                if sections.isEmpty {
                    Text("No words match your search.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                        .padding(.top, 8)
                        .accessibilityIdentifier("glossaryEmpty")
                } else {
                    ForEach(sections) { section in
                        MoreCaption(text: section.letter)
                            .padding(.top, 6)
                            .padding(.leading, 4)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.terms) { term in
                            GlossaryRow(term: term)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .moreSkyBackground(.more)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search words"
        )
    }
}

/// One word and its meaning on a glass card, read by VoiceOver as one element.
private struct GlossaryRow: View {
    let term: GlossaryTerm

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: term.title)
                .font(.headline.weight(.heavy))
            Text(verbatim: term.meaning)
                .font(.subheadline)
                .foregroundStyle(MorePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.leading)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.light, cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("glossary-\(term.rawValue)")
    }
}
