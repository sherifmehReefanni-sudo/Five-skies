import SwiftUI

/// All skyline shapes are drawn in a 390 x 250 design space and scaled to fit.
private let designSize = CGSize(width: 390, height: 250)

private func fitted(_ path: Path, in rect: CGRect) -> Path {
    let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
        .scaledBy(x: rect.width / designSize.width, y: rect.height / designSize.height)
    return path.applying(transform)
}

/// Rolling hills behind the mosque.
struct HillShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 120))
        path.addQuadCurve(to: CGPoint(x: 130, y: 104), control: CGPoint(x: 60, y: 70))
        path.addQuadCurve(to: CGPoint(x: 270, y: 92), control: CGPoint(x: 200, y: 138))
        path.addQuadCurve(to: CGPoint(x: 390, y: 110), control: CGPoint(x: 340, y: 46))
        path.addLine(to: CGPoint(x: 390, y: 250))
        path.addLine(to: CGPoint(x: 0, y: 250))
        path.closeSubpath()
        return fitted(path, in: rect)
    }
}

/// Mosque silhouette: two minarets, two small domes and one large central dome with a finial.
struct MosqueSkylineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 250))
        path.addLine(to: CGPoint(x: 0, y: 150))
        addMinaret(to: &path, left: 18)
        path.addLine(to: CGPoint(x: 62, y: 150))
        path.addQuadCurve(to: CGPoint(x: 106, y: 150), control: CGPoint(x: 84, y: 116))
        path.addLine(to: CGPoint(x: 128, y: 150))
        path.addQuadCurve(to: CGPoint(x: 262, y: 150), control: CGPoint(x: 195, y: 62))
        path.addLine(to: CGPoint(x: 284, y: 150))
        path.addQuadCurve(to: CGPoint(x: 328, y: 150), control: CGPoint(x: 306, y: 116))
        addMinaret(to: &path, left: 350)
        path.addLine(to: CGPoint(x: 390, y: 150))
        path.addLine(to: CGPoint(x: 390, y: 250))
        path.closeSubpath()
        path.addRect(CGRect(x: 193, y: 88, width: 4, height: 20))
        return fitted(path, in: rect)
    }

    /// A 22 point wide minaret whose base starts at `left` on the 150 line.
    private func addMinaret(to path: inout Path, left: CGFloat) {
        path.addLine(to: CGPoint(x: left, y: 150))
        path.addLine(to: CGPoint(x: left, y: 132))
        path.addLine(to: CGPoint(x: left + 6, y: 132))
        path.addLine(to: CGPoint(x: left + 6, y: 98))
        path.addLine(to: CGPoint(x: left + 11, y: 80))
        path.addLine(to: CGPoint(x: left + 16, y: 98))
        path.addLine(to: CGPoint(x: left + 16, y: 132))
        path.addLine(to: CGPoint(x: left + 22, y: 132))
        path.addLine(to: CGPoint(x: left + 22, y: 150))
    }
}

/// Warm window lights in the mosque.
struct SkylineLightsShape: Shape {
    private static let windows: [CGRect] = [
        CGRect(x: 176, y: 128, width: 6, height: 12),
        CGRect(x: 192, y: 128, width: 6, height: 12),
        CGRect(x: 208, y: 128, width: 6, height: 12),
        CGRect(x: 27, y: 112, width: 4, height: 8),
        CGRect(x: 359, y: 112, width: 4, height: 8),
        CGRect(x: 80, y: 136, width: 4, height: 8),
        CGRect(x: 304, y: 136, width: 4, height: 8)
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for window in Self.windows {
            let radius = window.width / 2
            path.addRoundedRect(in: window, cornerSize: CGSize(width: radius, height: radius))
        }
        return fitted(path, in: rect)
    }
}

/// The foreground ground line in front of the mosque.
struct GroundShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 176))
        path.addQuadCurve(to: CGPoint(x: 195, y: 168), control: CGPoint(x: 100, y: 150))
        path.addQuadCurve(to: CGPoint(x: 390, y: 160), control: CGPoint(x: 290, y: 186))
        path.addLine(to: CGPoint(x: 390, y: 250))
        path.addLine(to: CGPoint(x: 0, y: 250))
        path.closeSubpath()
        return fitted(path, in: rect)
    }
}
