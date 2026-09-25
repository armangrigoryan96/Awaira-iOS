import SwiftUI

/// The production access boundary. A one-time seven-day trial, active StoreKit subscription, or
/// Lifetime Unlock is required to enter Awaira's tracking surfaces.
struct PremiumAccessGate: View {
    @ObservedObject var store: PremiumStore
    @ObservedObject var trial: TrialAccess

    var body: some View {
        Group {
            if store.state == .loading && store.products.isEmpty && !trial.canStart {
                VStack(spacing: 14) {
                    ProgressView().tint(AwairaPalette.accent)
                    Text("Checking Awaira access…")
                        .awairaCaption(14)
                        .foregroundStyle(AwairaPalette.ink.opacity(0.62))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AwairaPalette.window.ignoresSafeArea())
            } else {
                PremiumPaywallView(store: store, trial: trial, isRequired: true)
            }
        }
        .accessibilityIdentifier("premiumAccessGate")
    }
}
