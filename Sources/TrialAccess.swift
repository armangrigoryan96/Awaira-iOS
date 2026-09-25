import Foundation
import Security

/// The seven-day first-use access window. It is deliberately stored in the Keychain instead of
/// `UserDefaults`, so deleting and reinstalling the app does not create a new trial on the same
/// iPhone. It grants use of the app only; purchases remain verified by StoreKit in `PremiumStore`.
@MainActor
final class TrialAccess: ObservableObject {
    enum State: Equatable {
        case available
        case active(expires: Date)
        case expired
    }

    static let durationDays = 7

    @Published private(set) var state: State
    private var expiryTask: Task<Void, Never>?

    init() {
        state = Self.state(for: Self.savedExpiry(), now: Date())
        scheduleExpiryCheck()
    }

    deinit {
        expiryTask?.cancel()
    }

    var isActive: Bool {
        if case .active = state { return true }
        return false
    }

    var canStart: Bool {
        if case .available = state { return true }
        return false
    }

    var hasExpired: Bool {
        if case .expired = state { return true }
        return false
    }

    var daysLeft: Int? {
        guard case .active(let expiry) = state else { return nil }
        return Self.calendarDaysLeft(until: expiry, now: Date())
    }

    /// Starts the one free window. Returns false only when the Keychain could not save it; in that
    /// case the app stays on the access screen rather than accidentally granting an untracked trial.
    @discardableResult
    func start() -> Bool {
        guard canStart else { return isActive }
        guard let expiry = Calendar.autoupdatingCurrent.date(byAdding: .day,
                                                              value: Self.durationDays,
                                                              to: Date()),
              Self.save(expiry) else { return false }
        state = .active(expires: expiry)
        scheduleExpiryCheck()
        return true
    }

    /// Call when the app becomes active, so a trial that ended while the app was closed immediately
    /// reaches the paid-only gate.
    func refresh() {
        state = Self.state(for: Self.savedExpiry(), now: Date())
        scheduleExpiryCheck()
    }

    static func calendarDaysLeft(until expiry: Date, now: Date) -> Int {
        guard expiry > now else { return 0 }
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: expiry)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(1, days)
    }

    private func scheduleExpiryCheck() {
        expiryTask?.cancel()
        guard case .active(let expiry) = state else { return }
        let nanoseconds = UInt64(max(0, expiry.timeIntervalSinceNow) * 1_000_000_000)
        expiryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    static func state(for expiry: Date?, now: Date) -> State {
        guard let expiry else { return .available }
        return expiry > now ? .active(expires: expiry) : .expired
    }

    private static let service = "com.awaira.ios"
    private static let account = "seven-day-trial-expiry"

    private static func savedExpiry() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let seconds = TimeInterval(String(decoding: data, as: UTF8.self)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func save(_ expiry: Date) -> Bool {
        let value = Data(String(expiry.timeIntervalSince1970).utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var add = query
        add[kSecValueData as String] = value
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
