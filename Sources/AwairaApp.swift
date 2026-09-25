import SwiftUI

@main
struct AwairaApp: App {
    /// Bumped when the first-run flow materially changes, so an earlier short introduction never
    /// hides the full onboarding from an existing iPhone install. Version 1.3 changes the
    /// first-run experience, so people arriving from the earlier flow should see it once.
    private static let requiredOnboardingVersion = 5
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
                } else if onboardingVersion >= Self.requiredOnboardingVersion {
                    ContentView(detector: detector)
                } else {
                    IPhoneOnboardingView(detector: detector) {
                        onboardingVersion = Self.requiredOnboardingVersion
                    }
                }
            }
        }
    }
}
