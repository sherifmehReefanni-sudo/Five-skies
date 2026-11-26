import SwiftUI

/// Shared placeholder for tabs that are not built yet.
struct ComingSoonView: View {
    let title: String

    var body: some View {
        ZStack {
            Color(hex: 0x120B1F)
                .ignoresSafeArea()
            VStack(spacing: 8) {
                Text(title)
                    .font(.largeTitle.weight(.heavy))
                Text("Coming soon")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding()
        }
    }
}
