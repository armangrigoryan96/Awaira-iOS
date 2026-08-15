import SwiftUI

@main
struct AwairaApp: App {
    /// Bumped when the first-run flow materially changes, so an earlier short introduction never
    /// hides the full desktop-equivalent onboarding from an existing iPhone install.
    @AppStorage("awairaOnboardingVersion") private var onboardingVersion = 0
    @StateObject private var trial = MobileTrialManager()
    @StateObject private var license = MobileLicenseManager()

    private var isUITest: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITest")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isUITest {
                    ContentView().environmentObject(license)
                } else if onboardingVersion >= 3 {
                    accessGate
                } else {
                    IPhoneOnboardingView {
                        onboardingVersion = 3
                        Task { await resolveAccess() }
                    }
                }
            }
                .task {
                    if onboardingVersion >= 3 && !isUITest { await resolveAccess() }
                }
        }
    }

    @ViewBuilder private var accessGate: some View {
        if case .unresolved = trial.state {
            MobileAccessCheckingView()
        } else if case .unresolved = license.state {
            MobileAccessCheckingView()
        } else if trial.isActive || license.isValid {
            ContentView().environmentObject(license)
        } else {
            MobileLicenseEntryView().environmentObject(license)
        }
    }

    private func resolveAccess() async {
        async let trialDone: Void = trial.resolve()
        async let licenseDone: Void = license.resolve()
        _ = await (trialDone, licenseDone)
    }
}
