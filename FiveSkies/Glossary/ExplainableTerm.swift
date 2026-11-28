import SwiftUI

/// A word with a faint dotted underline. Tapping it opens a small popover with its plain meaning
/// and a link to the full glossary (plan N3).
struct ExplainableTerm: View {
    let term: GlossaryTerm
    /// The text shown; the term's title unless the caller passes its own spelling.
    let text: String

    @State private var isShowing = false

    init(_ term: GlossaryTerm) {
        self.term = term
        self.text = term.title
    }

    /// Shows `text` (for example a lower-case form inside a sentence) but explains `term`.
    init(_ term: GlossaryTerm, text: String) {
        self.term = term
        self.text = text
    }

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Text(verbatim: text)
                .underline(true, pattern: .dot)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityHint(Text("Explains this word"))
        .accessibilityIdentifier("explain-\(term.rawValue)")
        .popover(isPresented: $isShowing) {
            GlossaryPopover(term: term)
        }
    }
}

/// Opens the same popover as `ExplainableTerm` when the view is tapped.
private struct ExplainsTermModifier: ViewModifier {
    let term: GlossaryTerm

    @State private var isShowing = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                isShowing = true
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("Explains this word"))
            .accessibilityAction {
                isShowing = true
            }
            .popover(isPresented: $isShowing) {
                GlossaryPopover(term: term)
            }
    }
}

extension View {
    /// Makes the whole view open the plain meaning of `term` on tap.
    func explainsTerm(_ term: GlossaryTerm) -> some View {
        modifier(ExplainsTermModifier(term: term))
    }

    /// As above; leaves the view unchanged when `term` is nil.
    @ViewBuilder
    func explainsTerm(_ term: GlossaryTerm?) -> some View {
        if let term = term {
            modifier(ExplainsTermModifier(term: term))
        } else {
            self
        }
    }
}

/// The compact popover: the word, its meaning, and a link to every word.
private struct GlossaryPopover: View {
    let term: GlossaryTerm

    @State private var showsGlossary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: term.title)
                .font(.headline.weight(.heavy))
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: term.meaning)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showsGlossary = true
            } label: {
                HStack(spacing: 4) {
                    Text("More words")
                    Image(systemName: "chevron.right")
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MorePalette.gold)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityIdentifier("explainMoreWords")
        }
        .multilineTextAlignment(.leading)
        .padding(16)
        .frame(width: 280, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("explainPopover-\(term.rawValue)")
        .presentationCompactAdaptation(.popover)
        .sheet(isPresented: $showsGlossary) {
            GlossarySheet()
        }
    }
}

/// The glossary in its own navigation stack, for opening from a popover.
private struct GlossarySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GlossaryView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                        .accessibilityIdentifier("glossaryDone")
                    }
                }
        }
    }
}
