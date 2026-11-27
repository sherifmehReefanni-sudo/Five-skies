import SwiftUI

/// The full player: play and pause, 15 second skips, a scrubber, speed, loop surah and the
/// sleep timer. The credit line sits under the title so it is always in view (D9).
struct ListenPlayerSheet: View {
    @EnvironmentObject private var player: ListenPlayer
    @Environment(\.dismiss) private var dismiss

    @Binding var sleepChoice: ListenSleepChoice

    @State private var scrubValue: Double? = nil
    @State private var isScrubbing = false
    @State private var skips = 0
    @State private var picks = 0

    var body: some View {
        ZStack {
            Color.clear.moreSkyBackground(.tasbih)
            if let item = player.item {
                ScrollView {
                    content(item)
                        .padding(.horizontal, 22)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                VStack(spacing: 14) {
                    Text("Nothing is playing")
                        .font(.title3.weight(.heavy))
                    Button("Close") { dismiss() }
                        .font(.headline)
                        .accessibilityIdentifier("playerDone")
                }
            }
        }
        .foregroundStyle(.white)
        .sensoryFeedback(.impact(weight: .light), trigger: skips)
        .sensoryFeedback(.selection, trigger: picks)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func content(_ item: NowPlayingItem) -> some View {
        VStack(spacing: 22) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(MorePalette.gold)
                    .accessibilityHint("Closes the player")
                    .accessibilityIdentifier("playerDone")
            }

            ListenArtwork(isPlaying: player.state == .playing, size: 170)
                .padding(.top, 4)

            VStack(spacing: 6) {
                Text(verbatim: item.chapterName)
                    .font(.title.weight(.heavy))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("playerTitle")
                Text(verbatim: "Surah \(item.chapter)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                Text(verbatim: item.credit)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MorePalette.goldLight)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(verbatim: "Recited by \(item.credit)"))
                    .accessibilityIdentifier("playerCredit")
            }

            scrubber

            transport

            if case .failed = player.state {
                Text("This surah could not play. Check your connection and tap Try again.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("playerFailed")
            }

            options(item)
        }
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        let duration = max(0, player.duration.isFinite ? player.duration : 0)
        let shown = min(max(0, scrubValue ?? player.position), duration)
        return VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { shown },
                    set: { value in
                        if isScrubbing {
                            scrubValue = value
                        } else {
                            // VoiceOver adjusts without a drag, so seek straight away.
                            player.seek(to: value)
                        }
                    }
                ),
                in: 0...max(duration, 1),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing, let value = scrubValue {
                        player.seek(to: value)
                        scrubValue = nil
                    }
                }
            )
            .tint(MorePalette.gold)
            .disabled(duration <= 0)
            .accessibilityLabel("Position in surah")
            .accessibilityValue(Text(verbatim: "\(ListenTimeFormat.spoken(shown)) of \(ListenTimeFormat.spoken(duration))"))
            .accessibilityIdentifier("playerScrubber")

            HStack {
                Text(verbatim: ListenTimeFormat.clock(shown))
                    .accessibilityLabel(Text(verbatim: "Elapsed \(ListenTimeFormat.spoken(shown))"))
                    .accessibilityIdentifier("playerElapsed")
                Spacer()
                Text(verbatim: ListenTimeFormat.remaining(position: shown, duration: duration))
                    .accessibilityLabel(Text(verbatim: "Remaining \(ListenTimeFormat.spoken(max(0, duration - shown)))"))
                    .accessibilityIdentifier("playerRemaining")
            }
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(MorePalette.secondaryText)
        }
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 34) {
            skipButton(seconds: -15, symbol: "gobackward.15", label: "Back 15 seconds", identifier: "playerBack15")
            ListenPlayPauseButton(size: 78, identifier: "playerPlayPause")
            skipButton(seconds: 15, symbol: "goforward.15", label: "Forward 15 seconds", identifier: "playerForward15")
        }
    }

    private func skipButton(seconds: Double, symbol: String, label: String, identifier: String) -> some View {
        Button {
            skips += 1
            player.skip(by: seconds)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle(pressedScale: 0.9))
        .disabled(player.duration <= 0)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Speed, loop, sleep

    private func options(_ item: NowPlayingItem) -> some View {
        VStack(spacing: 0) {
            speedMenu
            divider
            Toggle(isOn: Binding(
                get: { player.loopsSurah },
                set: { player.loopsSurah = $0 }
            )) {
                optionLabel(symbol: "repeat", title: "Loop surah", value: nil)
            }
            .tint(MorePalette.gold)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityIdentifier("playerLoopSurah")
            divider
            sleepMenu(item)
        }
        .moreGlass(.dark, cornerRadius: 22)
    }

    private var divider: some View {
        Divider()
            .overlay(Color.white.opacity(0.12))
            .padding(.leading, 52)
    }

    private var speedMenu: some View {
        Menu {
            ForEach(ListenSpeed.rates, id: \.self) { rate in
                Button {
                    picks += 1
                    player.setRate(rate)
                } label: {
                    if ListenSpeed.matches(rate, player.rate) {
                        Label(ListenSpeed.label(rate), systemImage: "checkmark")
                    } else {
                        Text(verbatim: ListenSpeed.label(rate))
                    }
                }
                .accessibilityLabel(Text(ListenSpeed.spoken(rate)))
            }
        } label: {
            optionLabel(symbol: "speedometer", title: "Speed", value: Text(verbatim: ListenSpeed.label(player.rate)))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Speed")
        .accessibilityValue(Text(ListenSpeed.spoken(player.rate)))
        .accessibilityIdentifier("playerSpeed")
    }

    private func sleepMenu(_ item: NowPlayingItem) -> some View {
        let current = ListenSleepOption.current(
            chosen: sleepChoice.option,
            chosenChapter: sleepChoice.chapter,
            playingChapter: item.chapter,
            timerEnd: player.sleepTimerEnd
        )
        return Menu {
            ForEach(ListenSleepOption.all) { option in
                Button {
                    choose(option, chapter: item.chapter)
                } label: {
                    if option == current {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(verbatim: option.title)
                    }
                }
                .accessibilityIdentifier(option.identifier)
            }
        } label: {
            optionLabel(symbol: "moon.zzz.fill", title: "Sleep timer", value: sleepValue(current))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Sleep timer")
        .accessibilityValue(Text(sleepSpoken(current)))
        .accessibilityIdentifier("playerSleepTimer")
    }

    private func sleepValue(_ current: ListenSleepOption) -> Text {
        switch current {
        case .off:
            return Text("Off")
        case .endOfSurah:
            return Text("End of surah")
        case .minutes:
            if let end = player.sleepTimerEnd {
                return Text(end, style: .timer)
            }
            return Text("Off")
        }
    }

    private func sleepSpoken(_ current: ListenSleepOption) -> String {
        switch current {
        case .off:
            return "Off"
        case .endOfSurah:
            return "Stops at the end of this surah"
        case .minutes(let minutes):
            return "Stops after \(minutes) minutes"
        }
    }

    private func choose(_ option: ListenSleepOption, chapter: Int) {
        picks += 1
        switch option {
        case .off:
            player.setSleepTimer(minutes: nil)
        case .minutes(let minutes):
            player.setSleepTimer(minutes: minutes)
        case .endOfSurah:
            player.setSleepTimer(minutes: nil)
            player.sleepAtEndOfSurah()
        }
        sleepChoice = ListenSleepChoice(option: option, chapter: option == .endOfSurah ? chapter : nil)
    }

    private func optionLabel(symbol: String, title: String, value: Text?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(MorePalette.gold)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            if let value {
                value
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(MorePalette.secondaryText)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .accessibilityHidden(true)
            }
        }
    }
}
