import SwiftUI

/// The one switch for decorative motion in the app.
/// Motion is on only when the system Reduce Motion setting is off and the app is not in the
/// fixed phase screenshot mode. `-FSAnimate` turns motion back on in the fixed phase mode,
/// so UI tests can capture it. Without it, `-FSFixedPhase` frames stay still and deterministic.
enum MotionPolicy {
    static let animateArgument = "-FSAnimate"

    static func isEnabled(reduceMotion: Bool, isFixedPhase: Bool, forcesAnimation: Bool) -> Bool {
        guard !reduceMotion else { return false }
        return !isFixedPhase || forcesAnimation
    }

    /// Whether `-FSAnimate` is among the launch arguments.
    static func forcesAnimation(processInfo: ProcessInfo = .processInfo) -> Bool {
        processInfo.arguments.contains(animateArgument)
    }
}

private struct MotionEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

private struct AmbientMotionEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// One shot motion such as entrances, tap feedback and value changes.
    var motionEnabled: Bool {
        get { self[MotionEnabledKey.self] }
        set { self[MotionEnabledKey.self] = newValue }
    }

    /// Continuous motion such as the living sky. Also off while the scene is not active.
    var ambientMotionEnabled: Bool {
        get { self[AmbientMotionEnabledKey.self] }
        set { self[AmbientMotionEnabledKey.self] = newValue }
    }
}

/// Sets both motion values for everything below it. Applied once, at the root of the window.
struct MotionEnvironment: ViewModifier {
    let isFixedPhase: Bool
    let forcesAnimation: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        let enabled = MotionPolicy.isEnabled(
            reduceMotion: reduceMotion,
            isFixedPhase: isFixedPhase,
            forcesAnimation: forcesAnimation
        )
        return content
            .environment(\.motionEnabled, enabled)
            .environment(\.ambientMotionEnabled, enabled && scenePhase == .active)
    }
}

/// Small pure helpers for time driven motion. Time is seconds from a TimelineView date.
enum MotionWave {
    /// Eases from 0 up to 1 and back over `period` seconds; 0 at whole periods.
    static func breath(_ time: Double, period: Double, offset: Double = 0) -> Double {
        0.5 - 0.5 * cos(2 * Double.pi * (time / period + offset))
    }

    /// The fractional part of `value`, in 0..<1.
    static func fraction(_ value: Double) -> Double {
        value - floor(value)
    }

    /// A stable pseudo random number in 0..<1 for an index, so nothing random happens at render time.
    static func hash(_ index: Int, salt: Double = 0) -> Double {
        fraction(sin(Double(index) * 12.9898 + salt * 78.233) * 43758.5453)
    }
}

/// A one time pulse: animate `progress` from one whole number to the next and the view swells
/// slightly and fades in and out. At any whole number it is invisible and at its normal size.
struct PulseEffect: ViewModifier, Animatable {
    var progress: Double
    var growth: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let bump = sin(Double.pi * MotionWave.fraction(progress))
        return content
            .scaleEffect(1 + growth * CGFloat(bump))
            .opacity(bump)
    }
}

/// Fades and rises a view into place once `revealed` turns true.
/// With motion off it is always shown in place.
struct RiseInModifier: ViewModifier {
    let revealed: Bool
    let delay: Double
    let distance: CGFloat
    let duration: Double

    @Environment(\.motionEnabled) private var motionEnabled

    func body(content: Content) -> some View {
        let shown = revealed || !motionEnabled
        return content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : distance)
            .animation(motionEnabled ? .easeOut(duration: duration).delay(delay) : nil, value: shown)
    }
}

extension View {
    func riseIn(revealed: Bool, delay: Double, distance: CGFloat = 14, duration: Double = 0.5) -> some View {
        modifier(RiseInModifier(revealed: revealed, delay: delay, distance: distance, duration: duration))
    }
}

/// A button style that shrinks the label a little while pressed and springs back.
struct PressScaleButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        PressScaleLabel(label: configuration.label, isPressed: configuration.isPressed, pressedScale: pressedScale)
    }
}

struct PressScaleLabel<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let pressedScale: CGFloat

    @Environment(\.motionEnabled) private var motionEnabled

    var body: some View {
        label
            .scaleEffect(motionEnabled && isPressed ? pressedScale : 1)
            .animation(motionEnabled ? .spring(response: 0.3, dampingFraction: 0.6) : nil, value: isPressed)
    }
}
