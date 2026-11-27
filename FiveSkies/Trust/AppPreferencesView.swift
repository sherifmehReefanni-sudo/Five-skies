import MessageUI
import SwiftUI
import UIKit

/// Settings and backup: the optional first name, iCloud backup and restore, feedback,
/// the mission page and "What's new". Pushed inside the More tab's NavigationStack.
struct AppPreferencesView: View {
    @Environment(\.openURL) private var openURL

    @State private var service: BackupService
    @State private var draftName: String = FirstNameStore.load() ?? ""
    @State private var lastBackup: Date?
    @State private var statusMessage: String?
    @State private var confirmsRestore = false
    @State private var composing: FeedbackKind?
    @State private var showsMailFallback = false
    @State private var showsWhatsNew = false
    /// Counts successful backups and restores, for the success haptic.
    @State private var successCount = 0

    init(service: BackupService = BackupService.live()) {
        _service = State(initialValue: service)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MoreScreenTitle(text: "Settings and backup", identifier: "preferencesTitle")

                MoreCaption(text: "Your name")
                    .padding(.top, 4)
                nameCard

                MoreCaption(text: "Backup")
                    .padding(.top, 8)
                backupCard

                MoreCaption(text: "Talk to us")
                    .padding(.top, 8)
                feedbackCard

                MoreCaption(text: "About")
                    .padding(.top, 8)
                aboutCard
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .moreSkyBackground(.more)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshBackupDate)
        .sensoryFeedback(.success, trigger: successCount)
        .confirmationDialog("Restore from backup?", isPresented: $confirmsRestore, titleVisibility: .visible) {
            Button("Restore", role: .destructive, action: restore)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(restoreMessage)
        }
        .sheet(item: $composing) { kind in
            MailComposeView(kind: kind, messageBody: FeedbackMail.currentBody()) {
                composing = nil
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsWhatsNew) {
            WhatsNewView()
        }
        .alert("No mail app found", isPresented: $showsMailFallback) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: "You can write to \(FeedbackMail.address) from any mail app.")
        }
    }

    // MARK: - Name

    private var nameCard: some View {
        card {
            TextField(
                "First name",
                text: $draftName,
                prompt: Text("First name (optional)").foregroundColor(MorePalette.secondaryText.opacity(0.75))
            )
            .font(.headline.weight(.heavy))
            .textContentType(.givenName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.1))
            )
            .accessibilityLabel(Text("First name"))
            .accessibilityIdentifier("preferencesFirstName")
            .onChange(of: draftName) { _, newValue in
                if newValue.count > FirstNameStore.maxLength {
                    draftName = String(newValue.prefix(FirstNameStore.maxLength))
                    return
                }
                FirstNameStore.save(newValue)
            }

            Text("Used only for a greeting on Today. It stays on this phone and is not backed up.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
        }
    }

    // MARK: - Backup

    private var backupCard: some View {
        card {
            Text("Save your tracker, goals, settings and progress to your own iCloud. No account needed.")

            Text(lastBackupText)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MorePalette.goldLight)
                .accessibilityIdentifier("backupLastDate")

            HStack(spacing: 10) {
                Button(action: backUp) {
                    Label("Back up now", systemImage: "icloud.and.arrow.up")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(MorePalette.ink)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(MorePalette.goldGradient)
                        )
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityIdentifier("backupNow")

                Button {
                    confirmsRestore = true
                } label: {
                    Label("Restore", systemImage: "icloud.and.arrow.down")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(lastBackup == nil)
                .opacity(lastBackup == nil ? 0.5 : 1)
                .accessibilityIdentifier("backupRestore")
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .accessibilityIdentifier("backupStatus")
            }
        }
    }

    private var lastBackupText: String {
        if let lastBackup {
            return "Last backup: \(lastBackup.formatted(date: .abbreviated, time: .shortened))"
        }
        return "No backup yet"
    }

    private var restoreMessage: String {
        if let lastBackup {
            return "This replaces your tracker, goals, settings and progress on this phone with the backup from \(lastBackup.formatted(date: .abbreviated, time: .shortened))."
        }
        return "This replaces your tracker, goals, settings and progress on this phone with your backup."
    }

    private func refreshBackupDate() {
        lastBackup = service.latestSnapshot()?.createdAt
    }

    private func backUp() {
        do {
            lastBackup = try service.backUp()
            statusMessage = "Backed up."
            successCount += 1
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func restore() {
        do {
            try service.restore()
            statusMessage = "Restored. Close and reopen Five Skies to see everything."
            successCount += 1
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    // MARK: - Feedback

    private var feedbackCard: some View {
        card {
            ForEach(FeedbackKind.allCases) { kind in
                Button {
                    startMail(kind)
                } label: {
                    row(symbol: kind.symbol, title: kind.buttonTitle)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("feedback-\(kind.rawValue)")
            }

            Text(verbatim: "Opens your mail app, addressed to \(FeedbackMail.address). Nothing is sent until you send it.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
        }
    }

    private func startMail(_ kind: FeedbackKind) {
        if MFMailComposeViewController.canSendMail() {
            composing = kind
            return
        }
        guard let url = FeedbackMail.mailtoURL(kind: kind, body: FeedbackMail.currentBody()) else {
            showsMailFallback = true
            return
        }
        openURL(url) { accepted in
            if !accepted {
                showsMailFallback = true
            }
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        card {
            NavigationLink {
                MissionView()
            } label: {
                row(symbol: "sparkles", title: "Our promise")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("preferencesMission")

            Button {
                showsWhatsNew = true
            } label: {
                row(symbol: "star", title: "What's new")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("preferencesWhatsNew")
        }
    }

    // MARK: - Pieces

    private func row(symbol: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MorePalette.gold)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .accessibilityHidden(true)
            Text(title)
                .font(.headline.weight(.heavy))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(MorePalette.secondaryText)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
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
