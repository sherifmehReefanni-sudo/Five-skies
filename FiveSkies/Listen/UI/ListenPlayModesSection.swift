import SwiftUI

/// The play modes in the player sheet (docs/LEARN_LISTEN_PLAN.md section 3): when this surah
/// ends, repeat each ayah, recite after me, read the meaning, pause for prayer, and start over.
/// The options that follow single ayahs need timings, so they are greyed with a short note when
/// there are none. Reading the meaning also needs a translation chosen in Aa.
struct ListenPlayModesSection: View {
    static let meaningTitle = "Read the meaning after each ayah"
    static let meaningNote = "English voice reads your chosen translation"
    static let meaningNeedsTranslation = "Choose a translation in Aa first"

    @EnvironmentObject private var player: ListenPlayer
    @EnvironmentObject private var quran: QuranStore

    let item: NowPlayingItem
    /// False when no translation is chosen, so there is no meaning to read. Passed by the lead.
    var hasTranslation = true

    @State private var picks = 0
    @State private var restarts = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MoreCaption(text: "Play modes")
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("playModes")

            VStack(spacing: 0) {
                surahEndMenu
                if case .playSet(let first, let last) = player.modes.surahEnd {
                    divider
                    setPicker(title: "From", symbol: "arrow.right.to.line", selection: first, identifier: "playerSetFirst") { chosen in
                        player.modes.surahEnd = ListenSetRange.changingFirst(chosen, last: last)
                    }
                    divider
                    setPicker(title: "To", symbol: "arrow.left.to.line", selection: last, identifier: "playerSetLast") { chosen in
                        player.modes.surahEnd = ListenSetRange.changingLast(chosen, first: first)
                    }
                }
                divider
                timedOptions
                divider
                toggleRow(
                    symbol: "moon.stars.fill",
                    title: "Pause for prayer",
                    isOn: Binding(
                        get: { player.modes.pausesForPrayer },
                        set: { player.modes.pausesForPrayer = $0 }
                    ),
                    identifier: "playerPauseForPrayer"
                )
                .accessibilityHint("Pauses when a prayer time comes and offers to resume")
                divider
                startOverButton
            }
            .moreGlass(.dark, cornerRadius: 22)
        }
        .sensoryFeedback(.selection, trigger: picks)
        .sensoryFeedback(.impact(weight: .light), trigger: restarts)
    }

    // MARK: - When this surah ends

    private var surahEndMenu: some View {
        let current = player.modes.surahEnd
        return Menu {
            endChoice(.stop, title: ListenPlayModeText.surahEnd(.stop), current: current)
            endChoice(.playNext, title: ListenPlayModeText.surahEnd(.playNext), current: current)
            Menu {
                ForEach(PlayModes.surahRepeatChoices, id: \.self) { times in
                    endChoice(.repeatSurah(times: times), title: ListenPlayModeText.repeatSurah(times), current: current)
                }
            } label: {
                if case .repeatSurah = current {
                    Label("Repeat this surah", systemImage: "checkmark")
                } else {
                    Text("Repeat this surah")
                }
            }
            Button {
                picks += 1
                if case .playSet = current {
                    return
                }
                player.modes.surahEnd = ListenSetRange.starting(at: item.chapter)
            } label: {
                if case .playSet = current {
                    Label("Play surahs from A to B", systemImage: "checkmark")
                } else {
                    Text("Play surahs from A to B")
                }
            }
        } label: {
            HStack(spacing: 14) {
                optionIcon("forward.end.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("When this surah ends")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(verbatim: ListenPlayModeText.surahEnd(current))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MorePalette.goldLight)
                }
                Spacer(minLength: 8)
                chevrons
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("When this surah ends")
        .accessibilityValue(Text(verbatim: ListenPlayModeText.surahEnd(current)))
        .accessibilityIdentifier("playerSurahEnd")
    }

    private func endChoice(_ action: SurahEndAction, title: String, current: SurahEndAction) -> some View {
        Button {
            picks += 1
            player.modes.surahEnd = action
        } label: {
            if action == current {
                Label(title, systemImage: "checkmark")
            } else {
                Text(verbatim: title)
            }
        }
    }

    private func setPicker(
        title: String,
        symbol: String,
        selection: Int,
        identifier: String,
        choose: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 14) {
            optionIcon(symbol)
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Picker(title, selection: Binding(
                get: { selection },
                set: { value in
                    picks += 1
                    choose(value)
                }
            )) {
                ForEach(surahChoices) { choice in
                    Text(verbatim: choice.title).tag(choice.number)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(MorePalette.goldLight)
            .accessibilityLabel(Text(title == "From" ? "First surah" : "Last surah"))
            .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// "1. Al-Fatihah" from the bundled metadata, or "Surah 1" if it has not loaded.
    private var surahChoices: [ListenSurahChoice] {
        let suras = quran.suras
        if suras.isEmpty {
            return ListenSetRange.chapters.map { ListenSurahChoice(number: $0, title: "Surah \($0)") }
        }
        return suras.map { ListenSurahChoice(number: $0.number, title: "\($0.number). \($0.transliteratedName)") }
    }

    // MARK: - Options that need timings

    private var timedOptions: some View {
        let available = player.timingsAvailable
        return VStack(spacing: 0) {
            ayahRepeatMenu
            divider
            toggleRow(
                symbol: "mic.fill",
                title: "Recite after me",
                isOn: Binding(
                    get: { player.modes.reciteAfterMe },
                    set: { player.modes.reciteAfterMe = $0 }
                ),
                needsTimings: true,
                identifier: "playerReciteAfterMe"
            )
            .accessibilityHint("After each ayah, waits as long as the ayah lasted so you can recite it")
            divider
            toggleRow(
                symbol: "text.bubble.fill",
                title: Self.meaningTitle,
                note: hasTranslation ? Self.meaningNote : Self.meaningNeedsTranslation,
                isOn: Binding(
                    get: { player.modes.readsMeaning },
                    set: { player.modes.readsMeaning = $0 }
                ),
                needsTimings: true,
                allowed: hasTranslation,
                identifier: "playerReadMeaning"
            )
            .accessibilityHint(Text(meaningHint(timingsAvailable: available)))
            if !available {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.footnote.weight(.bold))
                        .accessibilityHidden(true)
                    Text(ListenPlayModeText.timingsNote)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(MorePalette.secondaryText)
                .padding(.leading, 52)
                .padding(.trailing, 16)
                .padding(.bottom, 12)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("playerTimingsNote")
            }
        }
    }

    private var ayahRepeatMenu: some View {
        let available = player.timingsAvailable
        let current = player.modes.ayahRepeat
        return Menu {
            ForEach(PlayModes.ayahRepeatChoices, id: \.self) { count in
                Button {
                    picks += 1
                    player.modes.ayahRepeat = count
                } label: {
                    if count == current {
                        Label(ListenPlayModeText.ayahRepeat(count), systemImage: "checkmark")
                    } else {
                        Text(verbatim: ListenPlayModeText.ayahRepeat(count))
                    }
                }
            }
        } label: {
            HStack(spacing: 14) {
                optionIcon("repeat.1")
                Text("Repeat each ayah")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(verbatim: ListenPlayModeText.ayahRepeat(current))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                chevrons
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .disabled(!available)
        .opacity(available ? 1 : 0.45)
        .accessibilityLabel("Repeat each ayah")
        .accessibilityValue(Text(verbatim: ListenPlayModeText.ayahRepeat(current)))
        .accessibilityHint(Text(available ? "" : ListenPlayModeText.timingsNote))
        .accessibilityIdentifier("playerAyahRepeat")
    }

    private func meaningHint(timingsAvailable: Bool) -> String {
        if !hasTranslation { return Self.meaningNeedsTranslation }
        if !timingsAvailable { return ListenPlayModeText.timingsNote }
        return "After each ayah, an English voice reads its meaning, then the recitation goes on"
    }

    // MARK: - Rows

    private func toggleRow(
        symbol: String,
        title: String,
        note: String? = nil,
        isOn: Binding<Bool>,
        needsTimings: Bool = false,
        allowed: Bool = true,
        identifier: String
    ) -> some View {
        let enabled = allowed && (!needsTimings || player.timingsAvailable)
        return Toggle(isOn: Binding(
            get: { isOn.wrappedValue },
            set: { value in
                picks += 1
                isOn.wrappedValue = value
            }
        )) {
            HStack(spacing: 14) {
                optionIcon(symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note {
                        Text(verbatim: note)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(MorePalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .tint(MorePalette.gold)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityIdentifier(identifier)
    }

    private var startOverButton: some View {
        Button {
            restarts += 1
            player.startOver()
        } label: {
            HStack(spacing: 14) {
                optionIcon("backward.end.fill")
                Text("Start over")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                if let resumed = player.resumedFrom {
                    Text(verbatim: "Resumed at \(ListenTimeFormat.clock(resumed))")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(MorePalette.secondaryText)
                        .accessibilityIdentifier("playerResumedFrom")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Plays this surah again from the beginning")
        .accessibilityIdentifier("playerStartOver")
    }

    private func optionIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(MorePalette.gold)
            .frame(width: 22)
            .accessibilityHidden(true)
    }

    private var chevrons: some View {
        Image(systemName: "chevron.up.chevron.down")
            .font(.caption.weight(.bold))
            .foregroundStyle(MorePalette.secondaryText)
            .accessibilityHidden(true)
    }

    private var divider: some View {
        Divider()
            .overlay(Color.white.opacity(0.12))
            .padding(.leading, 52)
    }
}

/// One surah in the "from" and "to" pickers.
struct ListenSurahChoice: Identifiable {
    let number: Int
    let title: String

    var id: Int { number }
}
