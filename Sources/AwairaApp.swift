import SwiftUI

@main
struct AwairaApp: App {
    /// Bumped when the first-run flow materially changes, so an earlier short introduction never
    /// hides the full desktop-equivalent onboarding from an existing iPhone install.
    @AppStorage("awairaOnboardingVersion") private var onboardingVersion = 0
    /// Owned here rather than by `ContentView`, because onboarding's detection checks need the same
    /// detector: two instances would be two capture sessions fighting over one camera.
    @StateObject private var detector = Detector()

    private var isUITest: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITest")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isUITest {
                    ContentView(detector: detector)
                } else if onboardingVersion >= 4 {
                    ContentView(detector: detector)
                } else {
                    IPhoneOnboardingView(detector: detector) {
                        onboardingVersion = 4
                    }
                }
            }
        }
    }
}
