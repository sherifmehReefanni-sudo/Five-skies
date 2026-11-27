import MessageUI
import SwiftUI
import UIKit

/// The two kinds of message the user can write to us.
enum FeedbackKind: String, Identifiable, CaseIterable {
    case feedback
    case featureRequest

    var id: String { rawValue }

    var subject: String {
        switch self {
        case .feedback: return "Five Skies feedback"
        case .featureRequest: return "Five Skies feature request"
        }
    }

    var buttonTitle: String {
        switch self {
        case .feedback: return "Send feedback"
        case .featureRequest: return "Request a feature"
        }
    }

    var symbol: String {
        switch self {
        case .feedback: return "envelope"
        case .featureRequest: return "lightbulb"
        }
    }
}

/// Builds the mail the user writes themselves. The app never sends anything on its own.
enum FeedbackMail {
    static let address = "fiveskiesapp@gmail.com"

    /// Blank lines for the user to write in, then the app and iOS versions.
    static func body(appVersion: String, build: String, systemVersion: String) -> String {
        "\n\n\nApp version \(appVersion) (\(build))\niOS \(systemVersion)"
    }

    /// A `mailto:` link with the subject and body, for when Mail is not set up.
    static func mailtoURL(kind: FeedbackKind, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: kind.subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    /// The marketing version and build number from the app bundle.
    static func appVersion(bundle: Bundle = .main) -> (version: String, build: String) {
        let info = bundle.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        return (version, build)
    }

    /// The body for this device.
    static func currentBody() -> String {
        let app = appVersion()
        return body(appVersion: app.version, build: app.build, systemVersion: UIDevice.current.systemVersion)
    }
}

/// The system mail composer, filled in and ready for the user to edit and send.
struct MailComposeView: UIViewControllerRepresentable {
    let kind: FeedbackKind
    /// Not named `body`: that name belongs to `View`.
    let messageBody: String
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([FeedbackMail.address])
        controller.setSubject(kind.subject)
        controller.setMessageBody(messageBody, isHTML: false)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish()
        }
    }
}
