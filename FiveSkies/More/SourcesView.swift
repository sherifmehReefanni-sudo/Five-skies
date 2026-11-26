import SwiftUI

/// Credits and licenses for the content and code the app ships with.
/// The Tanzil and font attributions are license requirements, so this screen must stay reachable.
struct SourcesView: View {
    private let tanzilURL = URL(string: "https://tanzil.net")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MoreScreenTitle(text: "About and sources", identifier: "sourcesTitle")

                card {
                    Text("Quran text: Tanzil Project, Uthmani text, Creative Commons Attribution 3.0. The text is shown exactly as published.")
                    if let tanzilURL {
                        Link(destination: tanzilURL) {
                            HStack(spacing: 6) {
                                Text(verbatim: "tanzil.net")
                                Image(systemName: "arrow.up.right")
                                    .accessibilityHidden(true)
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(MorePalette.gold)
                        }
                        .accessibilityIdentifier("sourcesTanzilLink")
                    }
                }

                card {
                    Text("Quran typeface: Amiri Quran, SIL Open Font License.")
                }

                card {
                    Text("Prayer times and Qibla: Adhan library by Batoul Apps, MIT License.")
                }

                card {
                    Text("Five Skies is free and has no ads.")
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .moreSkyBackground(.more)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .font(.body.weight(.semibold))
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 24)
    }
}
