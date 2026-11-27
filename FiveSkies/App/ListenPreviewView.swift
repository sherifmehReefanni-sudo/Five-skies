import SwiftUI

/// The Listen tab until recitation audio is licensed and built (Phase B).
/// It says plainly what is coming instead of a bare placeholder, on the same night sky as the
/// rest of the app. It shows no recitation, reciter names or scripture.
struct ListenPreviewView: View {
    @State private var revealed = false

    private struct Feature: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
    }

    private static let features: [Feature] = [
        Feature(id: "reciters", symbol: "person.wave.2.fill", title: "Reciters you choose",
                detail: "A curated set of well known reciters."),
        Feature(id: "follow", symbol: "text.word.spacing", title: "Follow each word",
                detail: "The word being recited is highlighted as you listen."),
        Feature(id: "loop", symbol: "repeat", title: "Loop a surah or an ayah",
                detail: "Repeat as many times as you need to memorize."),
        Feature(id: "sleep", symbol: "moon.zzz.fill", title: "Sleep timer",
                detail: "Listen at night and let it fade out on its own.")
    ]

    var body: some View {
        ZStack {
            Color.clear.moreSkyBackground(.tasbih)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Listen")
                        .font(.largeTitle.weight(.heavy))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("listenTitle")
                        .riseIn(revealed: revealed, delay: 0)

                    hero
                        .riseIn(revealed: revealed, delay: 0.08)

                    VStack(spacing: 0) {
                        ForEach(Array(Self.features.enumerated()), id: \.element.id) { index, feature in
                            row(feature)
                            if index < Self.features.count - 1 {
                                Divider().overlay(Color.white.opacity(0.12)).padding(.leading, 56)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .moreGlass(.dark, cornerRadius: 24)
                    .riseIn(revealed: revealed, delay: 0.16)

                    Text("Free, like everything in Five Skies. Every recitation will name its source.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                        .padding(.horizontal, 4)
                        .riseIn(revealed: revealed, delay: 0.24)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(.white)
        .onAppear { revealed = true }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            ListenRings()
                .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 6) {
                Text("Recitation is on its way")
                    .font(.title3.weight(.heavy))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Coming in a free update.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .moreGlass(.light, cornerRadius: 28)
        .accessibilityElement(children: .combine)
    }

    private func row(_ feature: Feature) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: feature.symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(MorePalette.gold)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.headline.weight(.bold))
                Text(feature.detail)
                    .font(.subheadline)
                    .foregroundStyle(MorePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// A headphones glyph inside soft rings that ripple outward while ambient motion is on.
private struct ListenRings: View {
    @Environment(\.ambientMotionEnabled) private var animates

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animates)) { context in
            let time = animates ? context.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let wave = animates ? MotionWave.fraction(time / 2.4 + Double(index) / 3) : 0.25 + 0.25 * Double(index)
                    Circle()
                        .strokeBorder(MorePalette.gold.opacity(0.55 * (1 - wave)), lineWidth: 1.5)
                        .scaleEffect(0.55 + 0.45 * CGFloat(wave))
                }
                Circle()
                    .fill(MorePalette.goldGradient)
                    .frame(width: 44, height: 44)
                    .shadow(color: MorePalette.gold.opacity(0.5), radius: 12)
                Image(systemName: "headphones")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(MorePalette.ink)
            }
        }
        .accessibilityHidden(true)
    }
}
