import SwiftUI

/// The in-app purchase surface Apple reviews. It deliberately names the product, shows the
/// localized StoreKit price, and describes the one-time entitlement without implying a renewal.
struct PremiumPaywallView: View {
    @ObservedObject var store: PremiumStore
    @ObservedObject var trial: TrialAccess
    /// When this paywall is the app's access gate, there is intentionally no close button: the
    /// customer can restore a purchase or select a plan, but not bypass Premium access.
    var isRequired = false
    @Environment(\.dismiss) private var dismiss

    /// Pricing is the gold step in the Android and desktop onboarding flow, rather than the blue
    /// dashboard accent. Keeping this literal shared makes the four product surfaces recognisable.
    private let pricingAccent = Color(red: 0.98, green: 0.78, blue: 0.32)

    /// StoreKit cannot retrieve live App Store products in an ordinary simulator. This is only for
    /// the repeatable, in-app review-screenshot route; release builds always use `displayPrice`.
    private let isScreenshotDemo = ProcessInfo.processInfo.arguments.contains("-ScreenshotPaywall")
    @State private var trialStartFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                        .padding(.top, 18)

                    if trial.canStart {
                        freeTrialChoice
                            .padding(.top, 24)
                    }

                    planChoices
                        .padding(.top, trial.canStart ? 14 : 24)

                    purchaseControls
                        .padding(.top, 18)

                    pricingFootnotes
                        .padding(.top, 22)

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
        .tint(pricingAccent)
        .presentationBackground(AwairaPalette.window)
        .accessibilityIdentifier("premiumPaywall")
    }

    private var hero: some View {
        VStack(spacing: 8) {
            Text(heroTitle)
                .scaledFont(28, weight: .bold, design: .rounded)
                .foregroundStyle(AwairaPalette.text)
                .multilineTextAlignment(.center)
            Text(heroSubtitle)
                .scaledFont(14, weight: .medium)
                .foregroundStyle(AwairaPalette.ink.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Awaira gently interrupts hand to face habits before they happen automatically. Progress insights help you stay motivated over time.")
                .awairaCaption(13)
                .foregroundStyle(AwairaPalette.ink.opacity(0.45))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var planChoices: some View {
        VStack(spacing: 14) {
            ForEach(PremiumPlan.all) { plan in
                PlanChoice(plan: plan,
                           price: displayedPrice(for: plan),
                           detail: detail(for: plan),
                           actionTitle: actionTitle(for: plan),
                           actionEnabled: actionEnabled(for: plan),
                           accent: pricingAccent,
                           onChoose: { choose(plan) })
                    .accessibilityIdentifier("premiumPlan.\(plan.id)")
            }
        }
    }

    /// This is app-owned access, not an App Store subscription offer: it starts seven days of full
    /// use without asking the person to select a paid plan. Once it has run, `canStart` stays false
    /// because the expiry lives in the Keychain, and the same paywall becomes paid-only.
    private var freeTrialChoice: some View {
        VStack(spacing: 12) {
            Text("START HERE")
                .scaledFont(11, weight: .bold)
                .foregroundStyle(Color.black.opacity(0.78))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(pricingAccent, in: Capsule())

            Text("7-day free trial")
                .awairaCardTitle(20)
                .foregroundStyle(AwairaPalette.text)

            Text("Full access for 7 days. No payment needed.")
                .awairaCaption(13)
                .foregroundStyle(AwairaPalette.ink.opacity(0.66))
                .multilineTextAlignment(.center)

            Rectangle()
                .fill(AwairaPalette.ink.opacity(0.08))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                trialFeature("Hand-to-face detection and your chosen cues")
                trialFeature("Patterns, journal and private history")
                trialFeature("No account or payment method")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                trialStartFailed = !trial.start()
            } label: {
                Text("Start 7-day free trial")
                    .scaledFont(14, weight: .semibold)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .background(pricingAccent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityIdentifier("premiumFreeTrialButton")

            if trialStartFailed {
                Text("We couldn't start the free trial on this iPhone. Please try again.")
                    .awairaCaption(12)
                    .foregroundStyle(AwairaPalette.alert)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(pricingAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(pricingAccent.opacity(0.6), lineWidth: 1.5)
        )
        .accessibilityElement(children: .contain)
    }

    private func trialFeature(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .scaledFont(10, weight: .semibold)
                .foregroundStyle(pricingAccent)
            Text(text)
                .awairaCaption(12)
                .foregroundStyle(AwairaPalette.ink.opacity(0.78))
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
            Button("Restore Purchases") {
                Task { await store.restorePurchases() }
            }
            .scaledFont(14, weight: .medium)
            .foregroundStyle(AwairaPalette.accent)
            .frame(maxWidth: .infinity)
            .disabled(store.state == .purchasing)
            .accessibilityIdentifier("premiumRestoreButton")

            if store.restoreFoundNothing {
                Text("No previous purchase was found for this Apple Account.")
                    .awairaCaption(13)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
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

    private var pricingFootnotes: some View {
        VStack(spacing: 16) {
            Label("Detection stays on-device.", systemImage: "lock.fill")
                .awairaCaption(12)
                .foregroundStyle(AwairaPalette.ink.opacity(0.4))

            Text("Local taxes may be added at checkout, depending on where you live.")
                .awairaCaption(11)
                .foregroundStyle(AwairaPalette.ink.opacity(0.38))
                .multilineTextAlignment(.center)

            VStack(spacing: 4) {
                Text("A private awareness tool")
                    .awairaCaption(12)
                    .fontWeight(.semibold)
                Text("Awaira is not a medical device and does not diagnose or treat a condition.")
                    .awairaCaption(12)
            }
            .foregroundStyle(AwairaPalette.ink.opacity(0.45))
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var heroTitle: String {
        if trial.canStart { return "Start free, upgrade when ready." }
        return trial.hasExpired ? "Choose your Awaira plan." : "Unlock Awaira Premium."
    }

    private var heroSubtitle: String {
        if trial.canStart { return "7 days of full access  ·  No payment needed" }
        if trial.hasExpired { return "Your 7-day free trial has ended." }
        return "No account needed  ·  Detection stays on-device"
    }

    private func actionTitle(for plan: PremiumPlan) -> String {
        if store.state == .purchasing { return "Purchasing…" }
        return "Choose plan"
    }

    private func actionEnabled(for plan: PremiumPlan) -> Bool {
        return displayedPrice(for: plan) != nil && store.state != .purchasing
    }

    private func choose(_ plan: PremiumPlan) {
        Task { await store.purchase(productID: plan.id) }
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
        if let monthly = store.monthlyEquivalentPrice(for: plan.id) { return "About \(monthly) per month" }
        return plan.detail
    }

    private func displayedPrice(for plan: PremiumPlan) -> String? {
        return store.product(for: plan.id)?.displayPrice ?? (isScreenshotDemo ? plan.reviewPrice : nil)
    }

    private var legalDisclosure: String {
        baseDisclosure
    }

    private var baseDisclosure: String {
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

    static let monthly = PremiumPlan(id: PremiumStore.monthlyProductID,
                                     title: "Monthly", detail: "Cancel anytime. No commitment.",
                                     reviewPrice: "$9.99", period: "per month", badge: nil,
                                     features: ["Hand-to-face detection", "Blur and red-frame alerts", "Sound cue on detection", "Daily and weekly insights", "Weekly and monthly progress trends"])
    static let yearly = PremiumPlan(id: PremiumStore.yearlyProductID,
                                    title: "Yearly", detail: "Best value for lasting progress.",
                                    reviewPrice: "$23.99", period: "per year", badge: "MOST POPULAR",
                                    features: ["Everything in Monthly", "A better annual price", "Best value for long-term improvement"])
    static let lifetime = PremiumPlan(id: PremiumStore.lifetimeProductID,
                                      title: "Lifetime", detail: "Pay once, keep forever",
                                      reviewPrice: "$49.99", period: "one-time purchase", badge: nil,
                                      features: ["Everything in Yearly", "All future updates included", "One payment. Lifetime access."])
    static let all = [monthly, yearly, lifetime]
}

private struct PlanChoice: View {
    let plan: PremiumPlan
    let price: String?
    let detail: String
    let actionTitle: String
    let actionEnabled: Bool
    let accent: Color
    let onChoose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let badge = plan.badge {
                Text(badge)
                    .scaledFont(11, weight: .semibold)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.18), in: Capsule())
            } else {
                Spacer().frame(height: 22)
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
                        .tint(accent)
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
                            .scaledFont(10, weight: .semibold)
                            .foregroundStyle(plan.badge == nil ? AwairaPalette.ink.opacity(0.55) : accent)
                        Text(feature)
                            .awairaCaption(12)
                            .foregroundStyle(AwairaPalette.ink.opacity(0.78))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onChoose) {
                Text(actionTitle)
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(plan.badge == nil ? AwairaPalette.ink : Color.black.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .background(plan.badge == nil ? AwairaPalette.ink.opacity(0.12) : accent,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .disabled(!actionEnabled)
            .opacity(actionEnabled ? 1 : 0.5)
            .accessibilityIdentifier("premiumPurchaseButton.\(plan.id)")
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(plan.badge == nil ? AwairaPalette.ink.opacity(0.05) : accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(plan.badge == nil ? AwairaPalette.ink.opacity(0.1) : accent.opacity(0.6), lineWidth: 1.5)
        )
        .accessibilityElement(children: .contain)
    }
}
