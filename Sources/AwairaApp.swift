import SwiftUI

@main
struct AwairaApp: App {
    /// Bumped when the first-run flow materially changes, so an earlier short introduction never
    /// hides the full desktop-equivalent onboarding from an existing iPhone install.
    @AppStorage("awairaOnboardingVersion") private var onboardingVersion = 0

    private var isUITest: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITest")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingVersion >= 2 || isUITest {
                    ContentView()
                } else {
                    IPhoneOnboardingView {
                        onboardingVersion = 2
                    }
                }
            }
                .preferredColorScheme(.dark)
        }
    }
}
