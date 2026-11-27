import SwiftUI

/// A small tip jar. Tips are optional, unlock nothing, and go through the App Store only.
struct TipJarView: View {
    @StateObject private var store: TipStore
    @State private var revealed = false

    init() {
        // The fixed screenshot mode never contacts the App Store.
        let isFixedPhase = LaunchOptions().fixedPhase != nil
        let loader: TipProductLoading = isFixedPhase ? UnavailableTipLoader() : StoreKitTipLoader()
        _store = StateObject(wrappedValue: TipStore(loader: loader))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MoreScreenTitle(text: "Support Five Skies", identifier: "tipJarTitle")
                content
                    .riseIn(revealed: revealed, delay: 0.05)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .moreSkyBackground(.more)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadProducts()
        }
        .onAppear {
            revealed = true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.loadState {
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Loading")
                    .font(.headline)
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .moreGlass(.dark, cornerRadius: 24)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tipLoading")
        case .unavailable:
            VStack(alignment: .leading, spacing: 10) {
                Text("Five Skies is free and has no ads. If it helps you, a tip helps keep it running.")
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Tips are not available yet.")
                    .font(.subheadline)
                    .foregroundStyle(MorePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .moreGlass(.dark, cornerRadius: 24)
                .accessibilityIdentifier("tipUnavailable")
        case .loaded:
            loaded
        }
    }

    private var loaded: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Five Skies is free and has no ads. If it helps you, a tip helps keep it running.")
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .moreGlass(.dark, cornerRadius: 24)
                .accessibilityIdentifier("tipMessage")

            switch store.purchaseState {
            case .thankYou:
                statusCard(
                    title: "Thank you",
                    detail: "Your tip arrived. It means a lot.",
                    symbol: "heart.fill",
                    identifier: "tipThanks"
                )
                againButton(title: "Done")
            case .pending:
                statusCard(
                    title: "Waiting for approval",
                    detail: "Your tip will go through once it is approved.",
                    symbol: "clock",
                    identifier: "tipPending"
                )
                againButton(title: "OK")
            case .failed:
                statusCard(
                    title: "The tip did not go through",
                    detail: "Nothing was added. You can try again.",
                    symbol: "exclamationmark.circle",
                    identifier: "tipFailed"
                )
                buttons
            case .idle, .purchasing:
                buttons
            }

            Text("Tips are optional and unlock nothing.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
                .padding(.horizontal, 4)
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            ForEach(store.options) { option in
                tipButton(option)
            }
        }
    }

    private func tipButton(_ option: TipStore.Option) -> some View {
        let isBuying = store.purchaseState == .purchasing(option.id)
        let isBusy: Bool = {
            if case .purchasing = store.purchaseState { return true }
            return false
        }()
        return Button {
            Task {
                await store.purchase(option.id)
            }
        } label: {
            HStack(spacing: 12) {
                Text(verbatim: option.displayName)
                    .font(.headline.weight(.heavy))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if isBuying {
                    ProgressView()
                        .tint(MorePalette.ink)
                } else {
                    Text(verbatim: option.displayPrice)
                        .font(.headline.weight(.heavy))
                }
            }
            .foregroundStyle(MorePalette.ink)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(MorePalette.goldGradient)
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(isBusy)
        .accessibilityLabel(Text(verbatim: "\(option.displayName), \(option.displayPrice)"))
        .accessibilityIdentifier("tipButton-\(option.id)")
    }

    private func statusCard(title: String, detail: String, symbol: String, identifier: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(MorePalette.gold)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.heavy))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(MorePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func againButton(title: String) -> some View {
        Button {
            store.reset()
        } label: {
            Text(title)
                .font(.headline.weight(.heavy))
                .frame(maxWidth: .infinity, minHeight: 48)
                .moreGlass(.light, cornerRadius: 22)
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityIdentifier("tipDone")
    }
}
