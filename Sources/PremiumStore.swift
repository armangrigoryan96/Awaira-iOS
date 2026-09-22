import Foundation
import StoreKit

/// The Premium products sold by the iPhone app.
///
/// Their identifiers live in Info.plist so they are visible in the target configuration and can be
/// changed without touching the purchase UI. They must match the subscription products and the
/// non-consumable Lifetime Unlock created for this bundle ID in App Store Connect.
@MainActor
final class PremiumStore: ObservableObject {
    enum PurchaseState: Equatable {
        case loading
        case ready
        case purchasing
        case pending
        case purchased
        case unavailable
        case failed(String)
    }

    static let monthlyProductID = productID(for: "AwairaMonthlyProductID",
                                             fallback: "com.awaira.ios.premium.monthly")
    static let yearlyProductID = productID(for: "AwairaYearlyProductID",
                                            fallback: "com.awaira.ios.premium.yearly")
    static let lifetimeProductID = productID(for: "AwairaLifetimeProductID",
                                              fallback: "com.awaira.app.lifetime")
    static let productIDs = [monthlyProductID, yearlyProductID, lifetimeProductID]

    @Published private(set) var products: [String: Product] = [:]
    /// Product IDs whose introductory free trial this Apple Account can still redeem. Apple only
    /// grants a trial once per subscription group, so an ineligible customer is charged right away.
    @Published private(set) var trialEligibleProductIDs: Set<String> = []
    @Published private(set) var isPremiumUnlocked = false
    @Published private(set) var state: PurchaseState = .loading

    private var transactionUpdates: Task<Void, Never>?

    init() {
        transactionUpdates = observeTransactionUpdates()
        Task { await refresh() }
    }

    deinit {
        transactionUpdates?.cancel()
    }

    func refresh() async {
        state = .loading
        // Entitlements are cryptographically verified by StoreKit and are available from the
        // device's transaction database. Check them before asking the network for products so a
        // paying customer keeps access when the storefront is temporarily unavailable.
        await refreshEntitlement()
        do {
            let fetchedProducts = try await Product.products(for: Self.productIDs)
            products = Dictionary(uniqueKeysWithValues: fetchedProducts.map { ($0.id, $0) })
            trialEligibleProductIDs = await Self.trialEligibleIDs(in: fetchedProducts)
            state = products.isEmpty ? .unavailable : (isPremiumUnlocked ? .purchased : .ready)
        } catch {
            state = .failed("We couldn't load the purchase right now. Please try again.")
        }
    }

    func product(for id: String) -> Product? {
        products[id]
    }

    /// A free trial is an App Store introductory offer, never an app-owned timer. Apple therefore
    /// decides eligibility and issues the entitlement as soon as the customer accepts the offer.
    func freeTrialDescription(for productID: String) -> String? {
        guard trialEligibleProductIDs.contains(productID),
              let offer = products[productID]?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }

        let count = offer.period.value
        let unit: String
        switch offer.period.unit {
        case .day: unit = count == 1 ? "day" : "days"
        case .week: unit = count == 1 ? "week" : "weeks"
        case .month: unit = count == 1 ? "month" : "months"
        case .year: unit = count == 1 ? "year" : "years"
        @unknown default: unit = "period"
        }
        return "\(count)-\(unit) free trial"
    }

    /// The yearly price spread over twelve months, in the customer's own storefront currency.
    func monthlyEquivalentPrice(for productID: String) -> String? {
        guard let product = products[productID],
              product.subscription?.subscriptionPeriod == .yearly else { return nil }
        return (product.price / 12).formatted(product.priceFormatStyle)
    }

    func purchase(productID: String) async {
        guard let product = products[productID] else {
            await refresh()
            return
        }

        state = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let result):
                let transaction = try verified(result)
                await transaction.finish()
                await refreshEntitlement()
                state = isPremiumUnlocked ? .purchased : .ready
            case .pending:
                state = .pending
            case .userCancelled:
                state = .ready
            @unknown default:
                state = .ready
            }
        } catch {
            state = .failed("Your purchase couldn't be completed. Please try again.")
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refresh()
        } catch {
            state = .failed("We couldn't restore purchases right now. Please try again.")
        }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard let transaction = try? self.verified(result) else { continue }
                guard Self.productIDs.contains(transaction.productID) else { continue }
                await transaction.finish()
                await self.refreshEntitlement()
                self.state = self.isPremiumUnlocked ? .purchased : .ready
            }
        }
    }

    private func refreshEntitlement() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result) else { continue }
            if Self.productIDs.contains(transaction.productID) {
                unlocked = true
                break
            }
        }
        isPremiumUnlocked = unlocked
    }

    private static func trialEligibleIDs(in products: [Product]) async -> Set<String> {
        var eligible: Set<String> = []
        for product in products {
            if let subscription = product.subscription, await subscription.isEligibleForIntroOffer {
                eligible.insert(product.id)
            }
        }
        return eligible
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw StoreError.failedVerification
        }
    }

    private static func productID(for infoKey: String, fallback: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: infoKey) as? String) ?? fallback
    }
}

private enum StoreError: Error {
    case failedVerification
}
