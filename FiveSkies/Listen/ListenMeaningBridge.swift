import Foundation

/// Gives the player the English meaning of an ayah from the translation the user chose,
/// with the translator's name as its source. Owned by the lead; wired at the app root.
/// Reads the store on the main actor, where the store lives.
final class TranslationMeaningProvider: AyahMeaningProviding, @unchecked Sendable {
    private weak var store: TranslationStore?

    init(store: TranslationStore) {
        self.store = store
    }

    func meaning(chapter: Int, ayah: Int) async -> AyahMeaning? {
        await MainActor.run { [weak self] () -> AyahMeaning? in
            guard let store = self?.store,
                  let text = store.text(for: chapter, aya: ayah),
                  !text.isEmpty
            else { return nil }
            let summary = store.loaded?.summary
            let source = summary?.authorName ?? summary?.name ?? "Translation"
            return AyahMeaning(text: text, source: source)
        }
    }
}
