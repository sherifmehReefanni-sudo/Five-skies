import SwiftUI

/// A short page on what Five Skies promises, in plain words.
struct MissionView: View {
    struct Promise: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
    }

    static let promises: [Promise] = [
        Promise(
            id: "free",
            symbol: "gift",
            title: "Free",
            detail: "Everything in Five Skies is free. What is free today stays free."
        ),
        Promise(
            id: "noAds",
            symbol: "eye.slash",
            title: "No ads",
            detail: "No ads and no promotions for other apps. Ever."
        ),
        Promise(
            id: "noAccount",
            symbol: "person.crop.circle.badge.xmark",
            title: "No account",
            detail: "Nothing to sign up for. Your prayers, progress and settings stay on your phone, and in your own iCloud only if you back up."
        ),
        Promise(
            id: "sources",
            symbol: "text.book.closed",
            title: "Every text has a source",
            detail: "Every religious text is shown exactly as published, with its source named."
        ),
        Promise(
            id: "tips",
            symbol: "heart",
            title: "Tips only",
            detail: "The app runs on tips from people who want to help. A tip unlocks nothing. It keeps the app going for everyone."
        )
    ]

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MoreScreenTitle(text: "Our promise", identifier: "missionTitle")

                ForEach(Self.promises) { promise in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: promise.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(MorePalette.gold)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(promise.title)
                                .font(.headline.weight(.heavy))
                                .foregroundStyle(.white)
                            Text(promise.detail)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MorePalette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .moreGlass(.dark, cornerRadius: 24)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .moreSkyBackground(.more)
        .navigationBarTitleDisplayMode(.inline)
    }
}
