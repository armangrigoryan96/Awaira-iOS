import SwiftUI

/// What happens when the hand lingers: the screen dims over everything, with one encouraging
/// line. It clears the moment the hand pulls away.
///
/// The Mac shows this across every display at screen-saver level; on the phone the app's own
/// screen is the whole surface, so a full-cover overlay is the equivalent.
struct DimOverlay: View {
    let active: Bool

    /// Picked once per appearance so it stays fresh but doesn't flicker between frames.
    @State private var cheer = Self.cheers.randomElement() ?? "You've got this."

    var body: some View {
        ZStack {
            if active {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.55))
                    .ignoresSafeArea()
                    .overlay(
                        Text(cheer)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    )
                    .transition(.opacity)
                    .onAppear { cheer = Self.cheers.randomElement() ?? cheer }
            }
        }
        .animation(.easeOut(duration: 0.18), value: active)
        .allowsHitTesting(false)
    }

    private static let cheers = [
        "Hand down — you noticed.",
        "Take a breath.",
        "You caught it. That's the work.",
        "Let your hand rest.",
        "Nice catch.",
        "Back to what you were doing.",
    ]
}
