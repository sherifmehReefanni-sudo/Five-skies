import SwiftUI

/// Why the signature shooting star played.
enum SignatureStarReason: String, Equatable {
    case appOpened
    case periodChanged
    case prayerMarked
}

/// The sky phase seen on Today, plus what it was worked out for.
/// A change in `context` (place, method or Asr rule) sets a new baseline and never plays the star.
struct SkyPhaseSample: Equatable {
    let phase: Prayer
    let context: String
}

/// Pure timing rules for the signature star, kept apart so they can be unit tested.
enum SignatureStarRules {
    /// Fewest seconds between two stars, so the flourish never stacks up.
    static let cooldown: TimeInterval = 8
    /// Time spent in the background after which coming back counts as opening the app.
    static let reopenAfter: TimeInterval = 15 * 60
    /// A star waiting for Today to be on screen is dropped after this long.
    static let pendingLifetime: TimeInterval = 5 * 60

    static func canPlay(at now: Date, lastPlayed: Date?) -> Bool {
        guard let lastPlayed = lastPlayed else { return true }
        return now.timeIntervalSince(lastPlayed) >= cooldown
    }

    static func countsAsReopen(backgroundedAt: Date?, now: Date) -> Bool {
        guard let backgroundedAt = backgroundedAt else { return false }
        return now.timeIntervalSince(backgroundedAt) >= reopenAfter
    }

    /// True only when the phase moved on for the same place and settings.
    static func isPeriodChange(previous: SkyPhaseSample?, current: SkyPhaseSample) -> Bool {
        guard let previous = previous else { return false }
        return previous.context == current.context && previous.phase != current.phase
    }

    static func isFresh(pendingSince: Date, now: Date) -> Bool {
        now.timeIntervalSince(pendingSince) <= pendingLifetime
    }
}

/// Decides when the one signature moment, a shooting star across the sky, should play:
/// when the app opens, when the prayer period changes, and when a prayer is marked done.
/// It never plays on tab changes. Today shows it through `SignatureStarOverlay`.
final class SignatureStarController: ObservableObject {
    /// Goes up by one each time a star is queued.
    @Published private(set) var playCount = 0

    private var pending: (reason: SignatureStarReason, since: Date)?
    private var lastPlayed: Date?
    private var backgroundedAt: Date?
    private var hasOpened = false
    private var lastSample: SkyPhaseSample?
    private let now: () -> Date

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    func appBecameActive() {
        let date = now()
        if !hasOpened {
            hasOpened = true
            queue(.appOpened, at: date)
        } else if SignatureStarRules.countsAsReopen(backgroundedAt: backgroundedAt, now: date) {
            queue(.appOpened, at: date)
        }
        backgroundedAt = nil
    }

    func appEnteredBackground() {
        backgroundedAt = now()
    }

    func observe(_ sample: SkyPhaseSample) {
        let previous = lastSample
        lastSample = sample
        if SignatureStarRules.isPeriodChange(previous: previous, current: sample) {
            queue(.periodChanged, at: now())
        }
    }

    func prayerMarked() {
        queue(.prayerMarked, at: now())
    }

    /// Hands the waiting star to the overlay once, or nil if there is none or it went stale.
    func takePending() -> SignatureStarReason? {
        guard let waiting = pending else { return nil }
        pending = nil
        guard SignatureStarRules.isFresh(pendingSince: waiting.since, now: now()) else { return nil }
        return waiting.reason
    }

    private func queue(_ reason: SignatureStarReason, at date: Date) {
        guard SignatureStarRules.canPlay(at: date, lastPlayed: lastPlayed) else { return }
        lastPlayed = date
        pending = (reason, date)
        playCount += 1
    }
}

/// Feeds app lifecycle events to the controller. Applied once at the root of the window.
struct SignatureStarLifecycle: ViewModifier {
    @ObservedObject var controller: SignatureStarController
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .active:
                    controller.appBecameActive()
                case .background:
                    controller.appEnteredBackground()
                default:
                    break
                }
            }
    }
}

/// Draws the signature star when the controller queues one. Sits between the sky and the
/// content on Today, never takes touches, and draws nothing with motion off.
struct SignatureStarOverlay: View {
    @EnvironmentObject private var controller: SignatureStarController
    @Environment(\.motionEnabled) private var motionEnabled
    @State private var startedAt: Date?

    var body: some View {
        ZStack {
            if motionEnabled, let start = startedAt {
                TimelineView(.animation) { context in
                    let elapsed = context.date.timeIntervalSince(start)
                    Canvas { canvas, size in
                        SignatureStarDrawing.draw(in: &canvas, size: size, elapsed: elapsed)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: controller.playCount) {
            guard motionEnabled, let reason = controller.takePending() else { return }
            // On opening, the headline and tiles rise in first; the star follows them.
            let delay: Double = reason == .appOpened ? 0.7 : 0.15
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            startedAt = Date()
            let total = SignatureStarDrawing.duration + SignatureStarDrawing.afterglow
            try? await Task.sleep(nanoseconds: UInt64(total * 1_000_000_000))
            startedAt = nil
        }
    }
}

/// The geometry and look of the signature star, all worked out from elapsed seconds.
/// A bright head with a warm glow and a four point glint travels a gentle arc across the
/// upper sky, trailing a tapering tail and a few sparks that drift down and fade.
enum SignatureStarDrawing {
    /// Seconds for the head to cross the screen.
    static let duration: Double = 1.4
    /// Extra seconds for the last sparks to fade.
    static let afterglow: Double = 0.7

    private static let tailSpan: Double = 0.2
    private static let tailSegments = 26
    private static let sparkCount = 14
    private static let sparkLife: Double = 0.75

    private static let warm = Color(hex: 0xFFE2A0)

    /// The arc, in fractions of the canvas: starts off the left edge, ends off the right.
    static func point(at t: Double, in size: CGSize) -> CGPoint {
        let start = CGPoint(x: -0.12, y: 0.17)
        let control = CGPoint(x: 0.42, y: 0.03)
        let end = CGPoint(x: 1.14, y: 0.31)
        let u = 1 - t
        let x = u * u * Double(start.x) + 2 * u * t * Double(control.x) + t * t * Double(end.x)
        let y = u * u * Double(start.y) + 2 * u * t * Double(control.y) + t * t * Double(end.y)
        return CGPoint(x: CGFloat(x) * size.width, y: CGFloat(y) * size.height)
    }

    /// Eased progress of the head along the arc for a 0...1 share of the crossing.
    static func progress(_ share: Double) -> Double {
        let clamped = min(max(share, 0), 1)
        return 0.5 - 0.5 * cos(Double.pi * clamped)
    }

    /// Overall strength of head and tail: fades in quickly and out near the end.
    static func strength(_ share: Double) -> Double {
        guard share > 0, share < 1 else { return 0 }
        let fadeIn = min(1, share / 0.08)
        let fadeOut = min(1, (1 - share) / 0.18)
        return fadeIn * fadeOut
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, elapsed: Double) {
        guard elapsed >= 0 else { return }
        let share = elapsed / duration
        drawSparks(in: &context, size: size, elapsed: elapsed)
        let alpha = strength(share)
        guard alpha > 0 else { return }
        let head = progress(share)
        drawTail(in: &context, size: size, head: head, alpha: alpha)
        drawHead(in: &context, at: point(at: head, in: size), alpha: alpha)
    }

    private static func drawTail(in context: inout GraphicsContext, size: CGSize, head: Double, alpha: Double) {
        let tailStart = max(0, head - tailSpan)
        guard head > tailStart else { return }
        var previous = point(at: tailStart, in: size)
        for index in 1...tailSegments {
            let fraction = Double(index) / Double(tailSegments)
            let t = tailStart + (head - tailStart) * fraction
            let current = point(at: t, in: size)
            var segment = Path()
            segment.move(to: previous)
            segment.addLine(to: current)
            let width = CGFloat(0.4 + 2.8 * fraction * fraction)
            let color = fraction > 0.6 ? Color.white : warm
            context.stroke(
                segment,
                with: .color(color.opacity(alpha * fraction * 0.9)),
                style: StrokeStyle(lineWidth: width, lineCap: .round)
            )
            previous = current
        }
    }

    private static func drawHead(in context: inout GraphicsContext, at center: CGPoint, alpha: Double) {
        let glowRadius: CGFloat = 18
        let glowRect = CGRect(x: center.x - glowRadius, y: center.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)
        context.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [warm.opacity(0.6 * alpha), warm.opacity(0)]),
                center: center,
                startRadius: 0,
                endRadius: glowRadius
            )
        )
        let glint: CGFloat = 11
        var cross = Path()
        cross.move(to: CGPoint(x: center.x - glint, y: center.y))
        cross.addLine(to: CGPoint(x: center.x + glint, y: center.y))
        cross.move(to: CGPoint(x: center.x, y: center.y - glint))
        cross.addLine(to: CGPoint(x: center.x, y: center.y + glint))
        context.stroke(cross, with: .color(.white.opacity(0.55 * alpha)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
        let core: CGFloat = 2.8
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)),
            with: .color(.white.opacity(alpha))
        )
    }

    /// Sparks are shed along the path while the head crosses, then drift down and fade.
    private static func drawSparks(in context: inout GraphicsContext, size: CGSize, elapsed: Double) {
        for index in 0..<sparkCount {
            let shedShare = 0.12 + 0.72 * Double(index) / Double(sparkCount - 1)
            let shedTime = shedShare * duration
            let age = elapsed - shedTime
            guard age >= 0, age < sparkLife else { continue }
            let life = age / sparkLife
            let origin = point(at: progress(shedShare), in: size)
            let jitterX = CGFloat(MotionWave.hash(index, salt: 11) - 0.5) * 10
            let jitterY = CGFloat(MotionWave.hash(index, salt: 12) - 0.5) * 6
            let drift = CGFloat(life) * 14
            let center = CGPoint(x: origin.x + jitterX, y: origin.y + jitterY + drift)
            let radius = CGFloat(1.5 - 1.0 * life)
            let tint = MotionWave.hash(index, salt: 13) < 0.5 ? Color.white : warm
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(tint.opacity(0.9 * (1 - life)))
            )
        }
    }
}
