import SwiftUI

/// A quick settle when a tab comes back on screen: the screen starts a little faded and a
/// touch larger, then eases into place in 0.3 seconds, so switching tabs reads as a soft
/// dissolve between skies instead of a hard cut. It never blocks touches, it does not play
/// the first time a tab appears (Today has its own entrance), and it is off with motion off.
struct TabArrivalModifier: ViewModifier {
    static let duration: Double = 0.3

    @Environment(\.motionEnabled) private var motionEnabled
    @State private var settled = true

    func body(content: Content) -> some View {
        content
            .opacity(settled ? 1 : 0.5)
            .scaleEffect(settled ? 1 : 1.03)
            .onDisappear {
                // Off screen by now, so this jump is never seen.
                if motionEnabled {
                    settled = false
                }
            }
            .onAppear {
                guard !settled else { return }
                withAnimation(.easeOut(duration: Self.duration)) {
                    settled = true
                }
            }
    }
}

extension View {
    /// See `TabArrivalModifier`.
    func tabArrival() -> some View {
        modifier(TabArrivalModifier())
    }
}
