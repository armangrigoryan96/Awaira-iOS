import SwiftUI

@main
struct AwairaApp: App {
    /// Bumped when the first-run flow materially changes, so an earlier short introduction never
    /// hides the full desktop-equivalent onboarding from an existing iPhone install.
    @AppStorage("awairaOnboardingVersion") private var onboardingVersion = 0
    @StateObject private var trial = MobileTrialManager()

    private var isUITest: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITest")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingVersion >= 3 || isUITest {
                    if case .expired = trial.state, !isUITest {
                        MobileTrialExpiredView()
                    } else {
                        ContentView()
                    }
                } else {
                    IPhoneOnboardingView {
                        onboardingVersion = 3
                        Task { await trial.resolve() }
                    }
                }
            }
                .preferredColorScheme(.dark)
                .task {
                    if onboardingVersion >= 3 && !isUITest { await trial.resolve() }
                }
        }
    }
}
