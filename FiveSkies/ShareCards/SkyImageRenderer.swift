import SwiftUI
import UIKit

/// Renders a SwiftUI view to an image of an exact pixel size, for sharing and wallpapers.
enum SkyImageRenderer {
    /// Points are rendered at this scale, so a 1290 x 2796 pixel image is laid out at 430 x 932 points.
    static let scale: CGFloat = 3

    /// The layout size in points for an image of `pixels`.
    static func pointSize(forPixels pixels: CGSize) -> CGSize {
        CGSize(width: pixels.width / scale, height: pixels.height / scale)
    }

    /// Renders `content` laid out at the point size for `pixels`. Motion is off, so the frame is still.
    @MainActor
    static func render<Content: View>(_ content: Content, pixels: CGSize) -> UIImage? {
        let size = pointSize(forPixels: pixels)
        let framed = content
            .frame(width: size.width, height: size.height)
            .environment(\.ambientMotionEnabled, false)
            .environment(\.motionEnabled, false)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: framed)
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// A rendered image waiting to be handed to the share sheet.
struct SkySharedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
