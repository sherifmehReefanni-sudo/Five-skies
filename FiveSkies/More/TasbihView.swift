import SwiftUI
import UIKit

/// Tasbih counter: pick a phrase and a target, tap the circle to count.
struct TasbihView: View {
    @AppStorage("tasbih.count") private var storedCount = 0
    @AppStorage("tasbih.target") private var storedTarget = TasbihCounter.defaultTarget
    @AppStorage("tasbih.rounds") private var storedRounds = 0
    @AppStorage("tasbih.phrase") private var phrase: TasbihPhrase = .subhanAllah
    @AppStorage("tasbih.haptics") private var hapticsOn = true

    @ScaledMetric(relativeTo: .largeTitle) private var countSize: CGFloat = 88

    private let circleSize: CGFloat = 250

    private var counter: TasbihCounter {
        TasbihCounter(count: storedCount, target: storedTarget, rounds: storedRounds)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                MoreScreenTitle(text: "Tasbih", identifier: "tasbihTitle")
                phrasePicker
                counterButton
                    .padding(.vertical, 8)
                controls
                roundsRow
                Text("Tap the circle to count. It starts over after the target.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MorePalette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .moreSkyBackground(.tasbih)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var phrasePicker: some View {
        HStack(spacing: 8) {
            ForEach(TasbihPhrase.allCases) { item in
                let selected = item == phrase
                Button {
                    if !selected {
                        phrase = item
                        storedCount = 0
                    }
                } label: {
                    Text(item.title)
                        .font(.footnote.weight(.heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(selected ? MorePalette.ink : Color.white)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(pill(selected: selected))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
                .accessibilityIdentifier("tasbihPhrase-\(item.rawValue)")
            }
        }
    }

    private var counterButton: some View {
        let current = counter
        return Button(action: tap) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                Circle()
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 10)
                    .padding(12)
                Circle()
                    .trim(from: 0, to: CGFloat(current.progress))
                    .stroke(MorePalette.gold, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(12)
                    .animation(.easeOut(duration: 0.2), value: current.count)
                VStack(spacing: 2) {
                    Text("\(current.count)")
                        .font(.system(size: countSize, weight: .black))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    Text("of \(current.target)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MorePalette.secondaryText)
                }
                .padding(36)
            }
            .frame(width: circleSize, height: circleSize)
            .contentShape(Circle())
            .shadow(color: MorePalette.gold.opacity(0.18), radius: 30, y: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Count \(phrase.title), target \(current.target)"))
        .accessibilityValue(Text("\(current.count)"))
        .accessibilityHint(Text("Tap to count"))
        .accessibilityIdentifier("tasbihCounter")
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button(action: reset) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.heavy))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .moreGlass(.light, cornerRadius: 22)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tasbihReset")

                ForEach(TasbihCounter.targets, id: \.self) { value in
                    let selected = value == counter.target
                    Button {
                        var next = counter
                        next.setTarget(value)
                        save(next)
                    } label: {
                        Text("\(value)")
                            .font(.headline.weight(.black))
                            .foregroundStyle(selected ? MorePalette.ink : MorePalette.gold)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(pill(selected: selected))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Target \(value)"))
                    .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
                    .accessibilityIdentifier("tasbihTarget-\(value)")
                }
            }

            Toggle(isOn: $hapticsOn) {
                Text("Vibration")
                    .font(.subheadline.weight(.heavy))
            }
            .tint(MorePalette.mint)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .moreGlass(.light, cornerRadius: 22)
            .accessibilityIdentifier("tasbihHaptics")
        }
    }

    private var roundsRow: some View {
        HStack {
            Text("Rounds completed")
                .font(.subheadline.weight(.bold))
            Spacer(minLength: 8)
            Text("\(counter.rounds)")
                .font(.headline.weight(.black))
                .foregroundStyle(MorePalette.mint)
                .accessibilityIdentifier("tasbihRounds")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .moreGlass(.light, cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func pill(selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if selected {
            shape.fill(MorePalette.goldGradient)
                .overlay(shape.strokeBorder(Color.white, lineWidth: 1))
        } else {
            shape.fill(Color.white.opacity(0.1))
                .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        }
    }

    private func tap() {
        var next = counter
        next.increment()
        save(next)
        if hapticsOn {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func reset() {
        var next = counter
        next.reset()
        save(next)
    }

    private func save(_ value: TasbihCounter) {
        storedCount = value.count
        storedTarget = value.target
        storedRounds = value.rounds
    }
}
