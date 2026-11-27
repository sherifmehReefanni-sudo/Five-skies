import SwiftUI

/// Themes: choose the app's sky, and save sky wallpapers for the phone.
struct ThemesView: View {
    @AppStorage(SkyTheme.storageKey) private var storedTheme: SkyTheme = SkyTheme.defaultTheme
    @State private var shareImage: SkySharedImage?
    @State private var renderingWallpaper: ThemeWallpaper?

    init() {}

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    /// The card shown as chosen: the `-FSTheme` screenshot choice when present, else the stored one.
    private var selectedTheme: SkyTheme {
        SkyTheme.launchTheme(in: SkyTheme.processArguments) ?? storedTheme
    }

    var body: some View {
        ZStack {
            SkyView(phase: .isha, showsCelestial: false)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    MoreScreenTitle(text: "Themes", identifier: "themesTitle")
                    MoreCaption(text: "App theme")
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(SkyTheme.allCases) { theme in
                            themeCard(theme)
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        MoreCaption(text: "Wallpapers for your phone")
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(ThemeWallpaper.allCases) { wallpaper in
                                wallpaperCard(wallpaper)
                            }
                        }
                        Text("Save opens the share sheet. Choose Save Image to keep it in Photos.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(MorePalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .moreGlass(.dark, cornerRadius: 24)
                    .padding(.top, 8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareImage) { item in
            QuranActivityView(items: [item.image])
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Theme cards

    private func themeCard(_ theme: SkyTheme) -> some View {
        let selected = theme == selectedTheme
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return Button {
            storedTheme = theme
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                SkyView(phase: .maghrib, showsCelestial: true, themeOverride: theme, fillsScreen: false)
                    .environment(\.ambientMotionEnabled, false)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(MorePalette.ink)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(MorePalette.gold))
                                .padding(8)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.title)
                        .font(.subheadline.weight(.heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(theme.caption)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(MorePalette.ink.opacity(0.55)))
            .overlay(
                shape.strokeBorder(selected ? MorePalette.gold : Color.white.opacity(0.22), lineWidth: selected ? 2 : 1)
            )
            .shadow(color: selected ? MorePalette.gold.opacity(0.3) : .clear, radius: 14, y: 10)
            .contentShape(shape)
        }
        .buttonStyle(PressScaleButtonStyle())
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(Text("\(theme.title) theme"))
        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
        .accessibilityIdentifier("themeCard-\(theme.rawValue)")
    }

    // MARK: - Wallpapers

    private func wallpaperCard(_ wallpaper: ThemeWallpaper) -> some View {
        VStack(spacing: 8) {
            wallpaper.sky
                .environment(\.ambientMotionEnabled, false)
                .aspectRatio(ThemeWallpaper.pixelSize.width / ThemeWallpaper.pixelSize.height, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                )
                .accessibilityHidden(true)
            Text(wallpaper.title)
                .font(.footnote.weight(.heavy))
            Button {
                save(wallpaper)
            } label: {
                Group {
                    if renderingWallpaper == wallpaper {
                        ProgressView()
                            .tint(MorePalette.ink)
                    } else {
                        Text("Save")
                            .font(.footnote.weight(.heavy))
                    }
                }
                .foregroundStyle(MorePalette.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(MorePalette.goldGradient))
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(renderingWallpaper != nil)
            .accessibilityLabel(Text("Save \(wallpaper.title) wallpaper"))
            .accessibilityIdentifier("wallpaperSave-\(wallpaper.rawValue)")
        }
        .frame(maxWidth: .infinity)
    }

    private func save(_ wallpaper: ThemeWallpaper) {
        renderingWallpaper = wallpaper
        Task { @MainActor in
            // Lets the button show its progress before the render runs.
            await Task.yield()
            let image = SkyImageRenderer.render(wallpaper.sky, pixels: ThemeWallpaper.pixelSize)
            renderingWallpaper = nil
            if let image {
                shareImage = SkySharedImage(image: image)
            }
        }
    }
}

/// The three wallpaper skies, always drawn as living skies whatever the app theme.
enum ThemeWallpaper: String, CaseIterable, Identifiable {
    case night
    case sunset
    case dawn

    /// iPhone Pro Max screen size in pixels.
    static let pixelSize = CGSize(width: 1290, height: 2796)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .night: return "Night"
        case .sunset: return "Sunset"
        case .dawn: return "Dawn"
        }
    }

    var phase: Prayer {
        switch self {
        case .night: return .isha
        case .sunset: return .maghrib
        case .dawn: return .fajr
        }
    }

    var sky: SkyView {
        SkyView(phase: phase, showsCelestial: true, themeOverride: .living, fillsScreen: false)
    }
}
