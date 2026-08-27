import Foundation
import SwiftUI
import UIKit

/// Stable, anonymous per-install identifier used solely for licence activation. It deliberately
/// contains no camera, detection, or progress data, and matches the desktop's one-device licence
/// contract without trying to derive a hardware fingerprint from iOS.
enum MobileIdentity {
    private static let key = "awaira.mobile.license.installation"

    static var uuid: String {
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: key), !value.isEmpty { return value }
        let value = UUID().uuidString
        defaults.set(value, forKey: key)
        return value
    }
}

/// The iPhone equivalent of the desktop's server-owned trial check. Only an anonymous device
/// token is sent; camera frames, detections, and history never leave the phone.
@MainActor
final class MobileTrialManager: ObservableObject {
    enum State: Equatable { case unresolved, active(expires: Date?), expired }

    @Published private(set) var state: State = .unresolved
    @Published private(set) var checking = false

    private let cacheKey = "awaira.mobile.trial.cache"
    private let grace: TimeInterval = 3 * 86_400

    private struct Cache: Codable { let expires: Date?; let lastVerified: Date }
    private struct Response: Decodable { let valid: Bool; let expires: String? }

    var isActive: Bool {
        if case .active = state { return true }
        return false
    }

    func resolve() async {
        checking = true
        defer { checking = false }
        do {
            var request = URLRequest(url: URL(string: "https://awaira.app/api/trial")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["device": deviceID,
                                                                             "platform": "ios"])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let result = try JSONDecoder().decode(Response.self, from: data)
            let expires = result.expires.flatMap(parse)
            if result.valid {
                save(Cache(expires: expires, lastVerified: Date()))
                state = .active(expires: expires)
            } else {
                UserDefaults.standard.removeObject(forKey: cacheKey)
                state = .expired
            }
        } catch {
            guard let cache = load(),
                  cache.expires.map({ $0 > Date() }) ?? true,
                  Date().timeIntervalSince(cache.lastVerified) < grace else {
                state = .expired
                return
            }
            state = .active(expires: cache.expires)
        }
    }

    private var deviceID: String {
        let key = "awaira.mobile.trial.device"
        if let stored = UserDefaults.standard.string(forKey: key), !stored.isEmpty { return stored }
        let value = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    private func save(_ cache: Cache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private func load() -> Cache? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

/// iPhone counterpart to the desktop `LicenseManager`. A real Lemon Squeezy key is activated and
/// checked by the same backend endpoints as the Mac app. A recent valid response is cached for a
/// short offline grace period; an expired, revoked, or already-bound key always stays locked.
@MainActor
final class MobileLicenseManager: ObservableObject {
    enum State: Equatable {
        case unresolved
        case valid(plan: String, expires: Date?)
        case invalid(reason: String)
    }

    @Published private(set) var state: State = .unresolved
    @Published private(set) var checking = false

    private let keyKey = "awaira.mobile.license.key"
    private let cacheKey = "awaira.mobile.license.cache"
    private let grace: TimeInterval = 7 * 86_400

    private struct Cache: Codable { let plan: String; let expires: Date?; let lastVerified: Date }
    private struct Response: Decodable {
        let valid: Bool
        let plan: String?
        let expires: String?
        let reason: String?
    }
    private struct DeactivationResponse: Decodable { let ok: Bool }

    var isValid: Bool {
        if case .valid = state { return true }
        return false
    }

    var key: String? { UserDefaults.standard.string(forKey: keyKey) }

    /// Validates a previously entered key at launch. No key is a resolved, locked state rather
    /// than an error, so an expired trial can offer a clean licence-entry screen.
    func resolve() async {
        guard let key, !key.isEmpty else {
            state = .invalid(reason: "none")
            return
        }
        await validate(key)
    }

    /// Stores and activates a customer-provided key. The backend creates or validates that key's
    /// one-device Lemon Squeezy instance, exactly as it does for the desktop app.
    @discardableResult
    func activate(_ raw: String) async -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty else { return false }
        UserDefaults.standard.set(key, forKey: keyKey)
        await validate(key)
        return isValid
    }

    func recheck() async {
        guard let key, !key.isEmpty else {
            state = .invalid(reason: "none")
            return
        }
        await validate(key)
    }

    /// Removes the key from this iPhone and releases its server-side activation, allowing the
    /// customer to move the licence to another device. Local access is removed even if the
    /// device is offline; the backend call is best-effort, matching desktop behaviour.
    func removeLicense() {
        let currentKey = key
        UserDefaults.standard.removeObject(forKey: keyKey)
        UserDefaults.standard.removeObject(forKey: cacheKey)
        state = .invalid(reason: "none")
        guard let currentKey, !currentKey.isEmpty else { return }
        Task {
            _ = try? await Self.post("api/license_deactivate",
                                     body: ["key": currentKey, "uuid": MobileIdentity.uuid],
                                     as: DeactivationResponse.self)
        }
    }

    private func validate(_ key: String) async {
        checking = true
        defer { checking = false }
        do {
            let response = try await Self.post("api/license",
                                               body: ["key": key, "uuid": MobileIdentity.uuid],
                                               as: Response.self)
            if response.valid {
                let plan = response.plan ?? "monthly"
                let expires = response.expires.flatMap(Self.parse)
                save(Cache(plan: plan, expires: expires, lastVerified: Date()))
                state = .valid(plan: plan, expires: expires)
            } else {
                // The server's answer is authoritative; revoked/expired licences must not keep
                // using a previous offline cache.
                UserDefaults.standard.removeObject(forKey: cacheKey)
                state = .invalid(reason: response.reason ?? "invalid")
            }
        } catch {
            if let cache = load(),
               cache.expires.map({ $0 > Date() }) ?? true,
               Date().timeIntervalSince(cache.lastVerified) < grace {
                state = .valid(plan: cache.plan, expires: cache.expires)
            } else {
                state = .invalid(reason: "offline")
            }
        }
    }

    private func save(_ cache: Cache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private func load() -> Cache? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private static func post<Output: Decodable>(_ path: String, body: [String: String],
                                                 as _: Output.Type) async throws -> Output {
        let configuredBase = UserDefaults.standard.string(forKey: "apiBase")
        let base = URL(string: configuredBase ?? "https://awaira.app") ?? URL(string: "https://awaira.app")!
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Output.self, from: data)
    }

    private static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

/// Replaces the previous dead-end trial expiry screen. Customers can enter the real licence key
/// delivered after purchase, retry a failed check, or open the hosted checkout to buy a licence.
struct MobileLicenseEntryView: View {
    @EnvironmentObject private var license: MobileLicenseManager
    @State private var keyText = ""
    @FocusState private var keyFocused: Bool

    private let checkoutURL = URL(string: "https://awaira.lemonsqueezy.com/checkout/buy/a612bf42-ca5b-4232-b2e5-b31f50df5710")!

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .scaledFont(32, weight: .medium)
                .foregroundStyle(AwairaPalette.accent)
                .frame(width: 72, height: 72)
                .background(AwairaPalette.accent.opacity(0.12), in: Circle())

            VStack(spacing: 6) {
                Text("Unlock Awaira")
                    .awairaDisplay(27)
                    .foregroundStyle(AwairaPalette.text)
                    .multilineTextAlignment(.center)
                Text("Your trial has ended. Enter the licence key from your purchase email to continue.")
                    .awairaSubtitle()
                    .foregroundStyle(AwairaPalette.ink.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("AWRA-XXXX-XXXX-XXXX", text: $keyText)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(AwairaPalette.text)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .submitLabel(.done)
                .focused($keyFocused)
                .onSubmit(activate)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(AwairaPalette.statsSurface,
                            in: RoundedRectangle(cornerRadius: AwairaPalette.cardRadius,
                                                 style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AwairaPalette.cardRadius, style: .continuous)
                        .strokeBorder(AwairaPalette.cardBorder, lineWidth: 1)
                }
                .padding(.top, 4)

            if let message = errorMessage {
                Text(message)
                    .awairaCaption()
                    .foregroundStyle(AwairaPalette.alert)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: activate) {
                Group {
                    if license.checking {
                        ProgressView().tint(.white)
                    } else {
                        Text("Activate licence")
                    }
                }
            }
            .buttonStyle(AwairaPrimaryButton(enabled: !activateDisabled))
            .disabled(activateDisabled)

            Link("Buy a licence", destination: checkoutURL)
                .scaledFont(14, weight: .semibold)
                .foregroundStyle(AwairaPalette.accent)
                .padding(.top, 2)

            Text("A licence is activated on one device at a time. You can remove it in Settings to transfer it later.")
                .scaledFont(12)
                .foregroundStyle(AwairaPalette.ink.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AwairaPalette.window.ignoresSafeArea())
        .onAppear {
            keyText = license.key ?? ""
            keyFocused = keyText.isEmpty
        }
    }

    private var activateDisabled: Bool {
        license.checking || keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func activate() {
        let key = keyText
        Task { _ = await license.activate(key) }
    }

    private var errorMessage: String? {
        guard case .invalid(let reason) = license.state else { return nil }
        switch reason {
        case "none": return nil
        case "expired": return "This licence has expired."
        case "revoked": return "This licence is no longer active."
        case "bound_elsewhere": return "This licence is active on another device. Remove it there before transferring it."
        case "offline": return "Awaira could not verify this licence. Check your connection and try again."
        default: return "That licence could not be activated. Check the key and try again."
        }
    }
}

struct MobileAccessCheckingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView().tint(AwairaPalette.accent)
            Text("Checking your access…")
                .awairaSubtitle()
                .foregroundStyle(AwairaPalette.ink.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AwairaPalette.window.ignoresSafeArea())
    }
}

/// Kept for source compatibility with older previews; production routing now uses
/// `MobileLicenseEntryView` so expiry is never a dead end.
struct MobileTrialExpiredView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "hourglass")
                .scaledFont(34, weight: .medium)
                .foregroundStyle(AwairaPalette.accent)
            Text("Your Awaira trial has ended")
                .awairaDisplay(24)
                .foregroundStyle(AwairaPalette.text)
                .multilineTextAlignment(.center)
            Text("Thanks for giving Awaira a try. Visit awaira.app on your computer to continue with Awaira.")
                .awairaSubtitle()
                .foregroundStyle(AwairaPalette.ink.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AwairaPalette.window.ignoresSafeArea())
    }
}
