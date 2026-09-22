import SwiftUI

/// The production access boundary. A completed Apple subscription trial, active subscription, or
/// Lifetime Unlock is required to enter Awaira's tracking surfaces. There is no device-local trial
/// that can be reset by reinstalling the app.
struct PremiumAccessGate: View {
    @ObservedObject var store: PremiumStore

    var body: some View {
        Group {
            if store.state == .loading && store.products.isEmpty {
                VStack(spacing: 14) {
                    ProgressView().tint(AwairaPalette.accent)
                    Text("Checking Awaira access…")
                        .awairaCaption(14)
                        .foregroundStyle(AwairaPalette.ink.opacity(0.62))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AwairaPalette.window.ignoresSafeArea())
            } else {
                PremiumPaywallView(store: store, isRequired: true)
            }
        }
        .accessibilityIdentifier("premiumAccessGate")
    }
}
