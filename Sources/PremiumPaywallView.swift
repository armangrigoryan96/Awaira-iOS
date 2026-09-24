import SwiftUI

/// The in-app purchase surface Apple reviews. It deliberately names the product, shows the
/// localized StoreKit price, and describes the one-time entitlement without implying a renewal.
struct PremiumPaywallView: View {
    @ObservedObject var store: PremiumStore
    /// When this paywall is the app's access gate, there is intentionally no close button: the
    /// customer can restore a purchase or select a plan, but not bypass Premium access.
    var isRequired = false
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlanID = PremiumPaywallView.initialPlanID

    /// StoreKit cannot retrieve live App Store products in an ordinary simulator. This is only for
    /// the repeatable, in-app review-screenshot route; release builds always use `displayPrice`.
    private let isScreenshotDemo = ProcessInfo.processInfo.arguments.contains("-ScreenshotPaywall")

    /// Each submitted IAP needs its own review image. These launch arguments let the screenshot
    /// script open the same genuine in-app paywall with the relevant product selected.
    private static var initialPlanID: String {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ScreenshotMonthly") { return PremiumPlan.monthly.id }
        if arguments.contains("-ScreenshotLifetime") { return PremiumPlan.lifetime.id }
        return PremiumPlan.yearly.id
    }

    private var selectedPlan: PremiumPlan {
        PremiumPlan.all.first { $0.id == selectedPlanID } ?? .yearly
    }

    private var purchaseButtonTitle: String {
        if store.isPremiumUnlocked { return "Premium is active" }
        if store.state == .purchasing { return "Purchasing…" }
        if let trial = store.freeTrialDescription(for: selectedPlan.id) { return "Start \(trial)" }
        if let price = displayedPrice(for: selectedPlan) { return "Continue for \(price)" }
        return "Loading purchase options…"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                        .padding(.top, 18)

                    planChoices
                        .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 12) {
                        PremiumBenefit(icon: "checkmark.circle.fill", text: "Full awareness insights and patterns")
                        PremiumBenefit(icon: "checkmark.circle.fill", text: "Your complete private journal history")
                        PremiumBenefit(icon: "checkmark.circle.fill", text: "All future Premium updates")
                    }
                    .padding(.top, 20)

                    purchaseControls
                        .padding(.top, 24)

                    Text(legalDisclosure)
                        .awairaCaption(12)
                        .foregroundStyle(AwairaPalette.ink.opacity(0.52))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)

                    HStack(spacing: 16) {
                        Link("Privacy Policy", destination: MobileLegal.privacy)
                        Link("Terms of Use", destination: MobileLegal.terms)
                    }
                    .awairaCaption(12)
                    .foregroundStyle(AwairaPalette.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(AwairaPalette.window.ignoresSafeArea())
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AwairaPalette.window, for: .navigationBar)
            .toolbar {
                if !isRequired {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .foregroundStyle(AwairaPalette.accent)
                    }
                }
            }
        }
        .tint(AwairaPalette.accent)
        .presentationBackground(AwairaPalette.window)
        .accessibilityIdentifier("premiumPaywall")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AwairaPalette.accent)
                .frame(width: 52, height: 52)
                .background(AwairaPalette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("Unlock Awaira Premium")
                .awairaDisplay(29)
                .foregroundStyle(AwairaPalette.text)
            Text("Get every Premium feature, including future updates.")
                .awairaCaption(15)
                .foregroundStyle(AwairaPalette.ink.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var planChoices: some View {
        VStack(spacing: 10) {
            ForEach(PremiumPlan.all) { plan in
                Button {
                    selectedPlanID = plan.id
                } label: {
                    PlanChoice(plan: plan,
                               price: displayedPrice(for: plan),
                               detail: detail(for: plan),
                               isSelected: selectedPlanID == plan.id)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("premiumPlan.\(plan.id)")
            }
        }
    }

    @ViewBuilder private var purchaseControls: some View {
        if store.isPremiumUnlocked {
            Label("Awaira Premium is active", systemImage: "checkmark.seal.fill")
                .scaledFont(15, weight: .semibold)
                .foregroundStyle(AwairaPalette.live)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AwairaPalette.live.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Button {
                Task { await store.purchase(productID: selectedPlan.id) }
            } label: {
                HStack(spacing: 8) {
                    if store.state == .purchasing { ProgressView().tint(AwairaPalette.window) }
                    Text(purchaseButtonTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(AwairaPrimaryButton(enabled: displayedPrice(for: selectedPlan) != nil && store.state != .purchasing))
            .disabled(displayedPrice(for: selectedPlan) == nil || store.state == .purchasing)
            .accessibilityIdentifier("premiumPurchaseButton")

            Button("Restore Purchases") {
                Task { await store.restorePurchases() }
            }
            .scaledFont(14, weight: .medium)
            .foregroundStyle(AwairaPalette.accent)
            .frame(maxWidth: .infinity)
            .padding(.top, 13)
            .disabled(store.state == .purchasing)

            if let trial = store.freeTrialDescription(for: selectedPlan.id),
               let price = displayedPrice(for: selectedPlan) {
                Text("\(trial), then \(price) \(selectedPlan.period). Cancel anytime in Apple Account settings.")
                    .awairaCaption(12)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }

        if case .pending = store.state {
            Text("Your purchase is awaiting approval.")
                .awairaCaption(13)
                .foregroundStyle(AwairaPalette.ink.opacity(0.62))
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
        if let message = unavailableMessage {
            VStack(spacing: 9) {
                Text(message)
                    .awairaCaption(13)
                    .foregroundStyle(AwairaPalette.alert)
                    .multilineTextAlignment(.center)
                Button("Try Again") { Task { await store.refresh() } }
                    .scaledFont(14, weight: .medium)
                    .foregroundStyle(AwairaPalette.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        }
    }

    /// Shown whenever the plans cannot be bought, so a customer on the required paywall is never left
    /// with only a disabled button and no way to retry.
    private var unavailableMessage: String? {
        switch store.state {
        case .failed(let message): return message
        case .unavailable where !isScreenshotDemo:
            return "Purchase options aren't available right now. Please check your connection and try again."
        default: return nil
        }
    }

    private func detail(for plan: PremiumPlan) -> String {
        if let trial = store.freeTrialDescription(for: plan.id) { return trial }
        if let monthly = store.monthlyEquivalentPrice(for: plan.id) { return "About \(monthly) per month" }
        return plan.detail
    }

    private func displayedPrice(for plan: PremiumPlan) -> String? {
        store.product(for: plan.id)?.displayPrice ?? (isScreenshotDemo ? plan.reviewPrice : nil)
    }

    private var legalDisclosure: String {
        "Monthly and yearly plans renew automatically unless cancelled at least 24 hours before the end of the current period. Lifetime Unlock is a one-time purchase. Payment is charged to your Apple Account after confirmation."
    }
}

@MainActor
private struct PremiumPlan: Identifiable {
    let id: String
    let title: String
    let detail: String
    let reviewPrice: String
    let period: String
    let badge: String?

    static let monthly = PremiumPlan(id: PremiumStore.monthlyProductID,
                                     title: "Monthly", detail: "Flexible monthly access",
                                     reviewPrice: "$9.99", period: "per month", badge: nil)
    static let yearly = PremiumPlan(id: PremiumStore.yearlyProductID,
                                    title: "Yearly", detail: "Best price for a full year",
                                    reviewPrice: "$24.99", period: "per year", badge: "BEST VALUE")
    static let lifetime = PremiumPlan(id: PremiumStore.lifetimeProductID,
                                      title: "Lifetime Unlock", detail: "Pay once. Keep Premium forever.",
                                      reviewPrice: "$49.99", period: "one-time purchase", badge: nil)
    static let all = [monthly, yearly, lifetime]
}

private struct PlanChoice: View {
    let plan: PremiumPlan
    let price: String?
    let detail: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .scaledFont(21)
                .foregroundStyle(isSelected ? AwairaPalette.accent : AwairaPalette.ink.opacity(0.35))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(plan.title)
                        .awairaCardTitle(17)
                        .foregroundStyle(AwairaPalette.text)
                    if let badge = plan.badge {
                        Text(badge)
                            .awairaEyebrow(9, tracking: 0.8)
                            .foregroundStyle(AwairaPalette.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(AwairaPalette.accent.opacity(0.12), in: Capsule())
                    }
                }
                Text(detail)
                    .awairaCaption(13)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.58))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                if let price {
                    Text(price)
                        .awairaCardTitle(18)
                        .foregroundStyle(AwairaPalette.text)
                    Text(plan.period)
                        .awairaCaption(11)
                        .foregroundStyle(AwairaPalette.ink.opacity(0.50))
                } else {
                    ProgressView().tint(AwairaPalette.accent)
                }
            }
        }
        .padding(15)
        .background(AwairaPalette.statsSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(isSelected ? AwairaPalette.accent.opacity(0.82) : AwairaPalette.cardBorder,
                              lineWidth: isSelected ? 1.5 : 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct PremiumBenefit: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text)
                .awairaCaption(15)
                .foregroundStyle(AwairaPalette.ink.opacity(0.78))
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(AwairaPalette.accent)
        }
    }
}
