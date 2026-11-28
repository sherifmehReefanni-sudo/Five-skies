import SwiftUI

/// The bar that slides up when an ayah is tapped: large icon buttons with short labels,
/// a More menu for the rarer actions and a close button. One tap to each common action.
struct AyahToolbar: View {
    let title: String
    let isBookmarked: Bool
    /// Nil hides Play (no reciter available).
    let playTitle: String?
    let actions: AyahToolbarActions
    /// Runs whenever the bar closes itself: the close button, a one shot action, or VoiceOver escape.
    let onClose: () -> Void

    /// Set by `.ayahToolbar(item:content:)` so the bar also clears the host's item.
    fileprivate var hostDismiss: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var bookmarkTaps = 0
    @AccessibilityFocusState private var titleFocused: Bool

    init(
        title: String,
        isBookmarked: Bool,
        playTitle: String?,
        actions: AyahToolbarActions,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.isBookmarked = isBookmarked
        self.playTitle = playTitle
        self.actions = actions
        self.onClose = onClose
        self.hostDismiss = nil
    }

    var body: some View {
        let buttons = AyahToolbarButton.visible(playTitle: playTitle, hasWords: actions.words != nil)
        let columnCount = AyahToolbarLayout.columns(
            buttonCount: buttons.count,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 4, alignment: .top),
            count: columnCount
        )
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                Text(verbatim: title)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(MorePalette.secondaryText)
                    .lineLimit(2)
                    .padding(.leading, 6)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
                Spacer(minLength: 4)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: AyahToolbarLayout.minimumTarget, height: AyahToolbarLayout.minimumTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel("Close")
                .accessibilityIdentifier("toolbarClose")
            }

            LazyVGrid(columns: columns, alignment: .center, spacing: 4) {
                ForEach(buttons, id: \.self) { button in
                    control(for: button)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThickMaterial)
                .environment(\.colorScheme, .dark)
        )
        .moreGlass(.dark, cornerRadius: 26)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ayahToolbar")
        .accessibilityAction(.escape) {
            close()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: bookmarkTaps)
        .onAppear {
            titleFocused = true
        }
    }

    @ViewBuilder
    private func control(for button: AyahToolbarButton) -> some View {
        switch button {
        case .more:
            moreMenu
        case .play, .bookmark, .words, .share:
            Button {
                perform(button)
            } label: {
                AyahToolbarButtonLabel(
                    title: button.title(isBookmarked: isBookmarked, playTitle: playTitle),
                    systemImage: button.systemImage(isBookmarked: isBookmarked),
                    iconTint: button == .bookmark && isBookmarked ? MorePalette.gold : .white
                )
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityLabel(Text(verbatim: button.accessibilityLabel(isBookmarked: isBookmarked, playTitle: playTitle)))
            .accessibilityInputLabels([
                button.title(isBookmarked: isBookmarked, playTitle: playTitle),
                button.accessibilityLabel(isBookmarked: isBookmarked, playTitle: playTitle)
            ])
            .accessibilityIdentifier(button.identifier)
        }
    }

    private var moreMenu: some View {
        Menu {
            ForEach(AyahToolbarMenuItem.allCases, id: \.self) { item in
                Button {
                    perform(item)
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                }
                .accessibilityIdentifier(item.identifier)
            }
        } label: {
            AyahToolbarButtonLabel(
                title: AyahToolbarButton.more.title(isBookmarked: isBookmarked, playTitle: playTitle),
                systemImage: AyahToolbarButton.more.systemImage(isBookmarked: isBookmarked),
                iconTint: .white
            )
        }
        .menuOrder(.fixed)
        .accessibilityLabel(Text(verbatim: AyahToolbarButton.more.accessibilityLabel(isBookmarked: isBookmarked, playTitle: playTitle)))
        .accessibilityIdentifier(AyahToolbarButton.more.identifier)
    }

    private func perform(_ button: AyahToolbarButton) {
        switch button {
        case .play:
            actions.play()
        case .bookmark:
            bookmarkTaps += 1
            actions.toggleBookmark()
        case .words:
            actions.words?()
        case .share:
            actions.share()
        case .more:
            return
        }
        if button.closesBar {
            close()
        }
    }

    private func perform(_ item: AyahToolbarMenuItem) {
        switch item {
        case .copy:
            actions.copy()
        case .shareAsImage:
            actions.shareAsImage()
        case .markLastRead:
            actions.markLastRead()
        }
        close()
    }

    private func close() {
        onClose()
        hostDismiss?()
    }

    /// A copy that also clears the host's item when it closes. Used by `AyahToolbarHost`.
    fileprivate func dismissingHost(_ dismiss: @escaping () -> Void) -> AyahToolbar {
        var copy = self
        copy.hostDismiss = dismiss
        return copy
    }
}

/// An icon over a short label that may wrap to two lines. At least 44 points tall.
private struct AyahToolbarButtonLabel: View {
    let title: String
    let systemImage: String
    let iconTint: Color

    @ScaledMetric(relativeTo: .title3) private var iconHeight: CGFloat = 26

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(iconTint)
                .frame(height: iconHeight)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: AyahToolbarLayout.minimumTarget)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Host

/// Pins the toolbar to the bottom of the view it modifies, through `safeAreaInset(edge: .bottom)`.
/// An inset (not an overlay) so the reader's last ayah can still scroll clear of the bar, and so the
/// bar stacks above the play bar the Quran tab adds with its own, outer, bottom inset.
private struct AyahToolbarHost: ViewModifier {
    @Binding var item: AyahToolbarItem?
    let dismissesOnOutsideTap: Bool
    let makeToolbar: (AyahToolbarItem) -> AyahToolbar

    @Environment(\.motionEnabled) private var motionEnabled
    @State private var lastChangeAt: Double?

    func body(content: Content) -> some View {
        let watchesTaps = dismissesOnOutsideTap && item != nil
        return content
            // A tap, never a drag, so scrolling is untouched. Off while the bar is hidden.
            .simultaneousGesture(
                TapGesture().onEnded { outsideTapped() },
                including: watchesTaps ? .all : .subviews
            )
            .onChange(of: item) {
                lastChangeAt = ProcessInfo.processInfo.systemUptime
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if let item {
                        makeToolbar(item)
                            .dismissingHost { self.item = nil }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                            .transition(
                                motionEnabled
                                    ? AnyTransition.move(edge: .bottom).combined(with: .opacity)
                                    : AnyTransition.identity
                            )
                    }
                }
                .animation(motionEnabled ? .spring(response: 0.35, dampingFraction: 0.86) : nil, value: item != nil)
            }
    }

    private func outsideTapped() {
        guard item != nil else { return }
        let tapAt = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.asyncAfter(deadline: .now() + AyahToolbarDismissal.settleDelay) {
            if AyahToolbarDismissal.shouldDismiss(tapAt: tapAt, lastChangeAt: lastChangeAt, isShowing: item != nil) {
                item = nil
            }
        }
    }
}

extension View {
    /// Shows `content(item)` pinned at the bottom while `item` is set. Close and the bar's one shot
    /// actions set `item` to nil. With `dismissesOnOutsideTap`, a tap anywhere else in this view
    /// also closes it, except a tap that moved the bar to another ayah.
    func ayahToolbar(
        item: Binding<AyahToolbarItem?>,
        dismissesOnOutsideTap: Bool = true,
        content: @escaping (AyahToolbarItem) -> AyahToolbar
    ) -> some View {
        modifier(AyahToolbarHost(item: item, dismissesOnOutsideTap: dismissesOnOutsideTap, makeToolbar: content))
    }
}
