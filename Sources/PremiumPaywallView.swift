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
        if selectedPlan.isFreeTrial { return "Start 7-day free trial" }
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
        VStack(spacing: 10) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(AwairaPalette.accent)
                .frame(width: 48, height: 48)
                .background(AwairaPalette.accent.opacity(0.14), in: Circle())

            Text("Unlock Awaira Premium")
                .scaledFont(26, weight: .bold)
                .foregroundStyle(AwairaPalette.text)
                .multilineTextAlignment(.center)
            Text("Get every Premium feature, including future updates.")
                .awairaCaption(13)
                .foregroundStyle(AwairaPalette.ink.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var planChoices: some View {
        VStack(spacing: 10) {
            ForEach(PremiumPlan.all) { plan in
                if plan.isFreeTrial {
                    PlanChoice(plan: plan,
                               price: displayedPrice(for: plan),
                               detail: detail(for: plan),
                               isSelected: selectedPlanID == plan.id,
                               canStartFreeTrial: store.freeTrialStartedAt == nil,
                               onStartFreeTrial: { store.startFreeTrial() })
                        .onTapGesture { selectedPlanID = plan.id }
                        .accessibilityIdentifier("premiumPlan.\(plan.id)")
                } else {
                    Button {
                        selectedPlanID = plan.id
                    } label: {
                        PlanChoice(plan: plan,
                                   price: displayedPrice(for: plan),
                                   detail: detail(for: plan),
                                   isSelected: selectedPlanID == plan.id,
                                   canStartFreeTrial: false,
                                   onStartFreeTrial: nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("premiumPlan.\(plan.id)")
                }
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
        } else if selectedPlan.isFreeTrial {
            EmptyView()
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
        if plan.isFreeTrial { return plan.reviewPrice }
        return store.product(for: plan.id)?.displayPrice ?? (isScreenshotDemo ? plan.reviewPrice : nil)
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
    let features: [String]
    let isFreeTrial: Bool

    static let free = PremiumPlan(id: "free-trial",
                                  title: "Free Trial", detail: "7 days of full access · No card needed",
                                  reviewPrice: "Free", period: "for 7 days", badge: nil,
                                  features: ["Full access for 7 days", "No credit card", "No account needed"],
                                  isFreeTrial: true)
    static let monthly = PremiumPlan(id: PremiumStore.monthlyProductID,
                                     title: "Monthly", detail: "Flexible monthly access",
                                     reviewPrice: "$9.99", period: "per month", badge: nil,
                                     features: ["Hand-to-face awareness", "Personal insights and journal", "Cancel anytime"],
                                     isFreeTrial: false)
    static let yearly = PremiumPlan(id: PremiumStore.yearlyProductID,
                                    title: "Yearly", detail: "Best price for a full year",
                                    reviewPrice: "$24.99", period: "per year", badge: "BEST VALUE",
                                    features: ["Everything in Monthly", "Full awareness insights and patterns", "Best value for long-term progress"],
                                    isFreeTrial: false)
    static let lifetime = PremiumPlan(id: PremiumStore.lifetimeProductID,
                                      title: "Lifetime Unlock", detail: "Pay once. Keep Premium forever.",
                                      reviewPrice: "$49.99", period: "one-time purchase", badge: nil,
                                      features: ["Everything in Yearly", "All future Premium updates", "One payment, ongoing access"],
                                      isFreeTrial: false)
    static let all = [free, monthly, yearly, lifetime]
}

private struct PlanChoice: View {
    let plan: PremiumPlan
    let price: String?
    let detail: String
    let isSelected: Bool
    let canStartFreeTrial: Bool
    let onStartFreeTrial: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            if let badge = plan.badge {
                Text(badge)
                    .awairaEyebrow(10, tracking: 0.9)
                    .foregroundStyle(AwairaPalette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AwairaPalette.accent.opacity(0.18), in: Capsule())
            }

            Text(plan.title)
                .awairaCardTitle(17)
                .foregroundStyle(AwairaPalette.text)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                if let price {
                    Text(price)
                        .awairaFigure(25, weight: .semibold)
                        .foregroundStyle(AwairaPalette.text)
                } else {
                    ProgressView()
                        .tint(AwairaPalette.accent)
                }
                Text(plan.period)
                    .awairaCaption(12)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.55))
            }

            Text(detail)
                .awairaCaption(12)
                .foregroundStyle(AwairaPalette.ink.opacity(0.55))
                .multilineTextAlignment(.center)

            Rectangle()
                .fill(AwairaPalette.ink.opacity(0.08))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(plan.features, id: \.self) { feature in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark")
                            .scaledFont(12, weight: .semibold)
                            .foregroundStyle(plan.badge == nil ? AwairaPalette.ink.opacity(0.55) : AwairaPalette.accent)
                            .padding(.top, 2)
                        Text(feature)
                            .awairaCaption(12)
                            .foregroundStyle(AwairaPalette.ink.opacity(0.78))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if plan.isFreeTrial, let onStartFreeTrial {
                Button(action: onStartFreeTrial) {
                    Text(canStartFreeTrial ? "Start free trial" : "Free trial already used")
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                .background(AwairaPalette.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .disabled(!canStartFreeTrial)
                .opacity(canStartFreeTrial ? 1 : 0.5)
                .accessibilityIdentifier("premiumFreeTrialButton")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: isSelected ? 1.5 : 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var cardBackground: Color {
        if isSelected { return AwairaPalette.accent.opacity(0.12) }
        if plan.badge != nil { return AwairaPalette.accent.opacity(0.07) }
        return AwairaPalette.ink.opacity(0.05)
    }

    private var cardBorder: Color {
        if isSelected { return AwairaPalette.accent.opacity(0.82) }
        if plan.badge != nil { return AwairaPalette.accent.opacity(0.6) }
        return AwairaPalette.cardBorder
    }
}
