import SwiftUI

/// The list of reciters, as the Quran Foundation API gives them (D4). Names are shown verbatim.
struct ListenReciterPicker: View {
    @ObservedObject var model: ListenTabModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.reciters) { reciter in
                    let isSelected = reciter.id == model.selectedReciter?.id
                    Button {
                        model.select(reciter)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: reciter.name)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                                if let style = reciter.style, !style.isEmpty {
                                    Text(verbatim: style)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(MorePalette.secondaryText)
                                }
                            }
                            Spacer(minLength: 8)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(MorePalette.gold)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: Self.accessibilityName(reciter)))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("listenReciter-\(reciter.id)")
                    .listRowBackground(Color.white.opacity(isSelected ? 0.12 : 0.05))
                    .listRowSeparatorTint(Color.white.opacity(0.12))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .moreSkyBackground(.tasbih)
            .navigationTitle("Reciters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("listenRecitersDone")
                }
            }
        }
        .foregroundStyle(.white)
        .sensoryFeedback(.selection, trigger: model.selectedReciter?.id)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    static func accessibilityName(_ reciter: Reciter) -> String {
        if let style = reciter.style, !style.isEmpty {
            return "\(reciter.name), \(style)"
        }
        return reciter.name
    }
}
