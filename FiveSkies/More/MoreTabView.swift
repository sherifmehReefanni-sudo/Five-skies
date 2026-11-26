import SwiftUI

/// The More tab: a grid of every tool in the app, plus the tip row.
struct MoreTabView: View {
    @State private var showsTipsAlert = false

    init() {}

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    MoreScreenTitle(text: "Everything", identifier: "moreTitle")
                        .padding(.horizontal, 4)

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(MoreTool.allCases) { tool in
                            tile(for: tool)
                        }
                    }

                    supportRow
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .moreSkyBackground(.more)
            .navigationTitle("Everything")
            .toolbar(.hidden, for: .navigationBar)
            .alert("Tips are coming soon.", isPresented: $showsTipsAlert) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func tile(for tool: MoreTool) -> some View {
        if tool.isAvailable {
            NavigationLink {
                tool.destination
            } label: {
                MoreTile(tool: tool)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(tool.title))
            .accessibilityIdentifier("moreTile-\(tool.rawValue)")
        } else {
            Button {} label: {
                MoreTile(tool: tool)
            }
            .buttonStyle(.plain)
            .disabled(true)
            .accessibilityLabel(Text("\(tool.title), coming soon"))
            .accessibilityIdentifier("moreTile-\(tool.rawValue)")
        }
    }

    private var supportRow: some View {
        Button {
            showsTipsAlert = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Support this app")
                        .font(.headline.weight(.heavy))
                    Text("Free forever. No ads. Tips keep it running.")
                        .font(.caption.weight(.semibold))
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.body.weight(.bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(MorePalette.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(MorePalette.goldGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 1)
            )
            .shadow(color: MorePalette.gold.opacity(0.35), radius: 18, y: 14)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("moreSupport")
    }
}

/// Every tile on the More screen, in display order.
enum MoreTool: String, CaseIterable, Identifiable {
    case tracker
    case tasbih
    case zakat
    case hijriCalendar
    case hadith
    case duas
    case ramadan
    case names
    case mosques
    case halal
    case memorize
    case stories
    case themes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tracker: return "Prayer tracker"
        case .tasbih: return "Tasbih"
        case .zakat: return "Zakat"
        case .hijriCalendar: return "Hijri calendar"
        case .hadith: return "Hadith"
        case .duas: return "Duas and adhkar"
        case .ramadan: return "Ramadan"
        case .names: return "99 Names"
        case .mosques: return "Mosques nearby"
        case .halal: return "Halal food"
        case .memorize: return "Memorize"
        case .stories: return "Stories"
        case .themes: return "Themes"
        }
    }

    var symbol: String {
        switch self {
        case .tracker: return "checkmark.circle"
        case .tasbih: return "hand.tap"
        case .zakat: return "banknote"
        case .hijriCalendar: return "calendar"
        case .hadith: return "book.closed"
        case .duas: return "hands.sparkles"
        case .ramadan: return "moon.stars"
        case .names: return "sparkles"
        case .mosques: return "mappin.and.ellipse"
        case .halal: return "fork.knife"
        case .memorize: return "bookmark"
        case .stories: return "book"
        case .themes: return "paintpalette"
        }
    }

    var tint: Color {
        switch self {
        case .tracker, .zakat: return Color(red: 90 / 255, green: 200 / 255, blue: 120 / 255).opacity(0.45)
        case .tasbih, .stories: return Color(red: 90 / 255, green: 150 / 255, blue: 240 / 255).opacity(0.45)
        case .hijriCalendar, .halal: return Color(red: 240 / 255, green: 150 / 255, blue: 80 / 255).opacity(0.45)
        case .hadith, .mosques: return Color(red: 64 / 255, green: 200 / 255, blue: 180 / 255).opacity(0.4)
        case .duas, .memorize: return Color(red: 160 / 255, green: 120 / 255, blue: 240 / 255).opacity(0.45)
        case .ramadan: return Color(red: 240 / 255, green: 110 / 255, blue: 150 / 255).opacity(0.45)
        case .names, .themes: return Color(red: 240 / 255, green: 200 / 255, blue: 90 / 255).opacity(0.45)
        }
    }

    var isAvailable: Bool {
        switch self {
        case .tracker, .tasbih, .zakat, .hijriCalendar: return true
        default: return false
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .tracker: TrackerView()
        case .tasbih: TasbihView()
        case .zakat: ZakatView()
        case .hijriCalendar: HijriCalendarView()
        default: EmptyView()
        }
    }
}

private struct MoreTile: View {
    let tool: MoreTool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: tool.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tool.tint))
                .accessibilityHidden(true)
            Text(tool.title)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 84)
        .moreGlass(.light, cornerRadius: 22)
        .overlay(alignment: .topTrailing) {
            if !tool.isAvailable {
                Text("Soon")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(MorePalette.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(MorePalette.goldLight))
                    .padding(6)
                    .accessibilityHidden(true)
            }
        }
        .opacity(tool.isAvailable ? 1 : 0.5)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
