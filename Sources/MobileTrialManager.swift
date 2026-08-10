import Foundation
import SwiftUI
import UIKit

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

    func resolve() async {
        checking = true
        defer { checking = false }
        do {
            var request = URLRequest(url: URL(string: "https://awaira.app/api/trial")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["device": deviceID])
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

struct MobileTrialExpiredView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "hourglass")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.mint)
            Text("Your Awaira trial has ended")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Thanks for giving Awaira a try. Visit awaira.app on your computer to continue with Awaira.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.66))
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.025, green: 0.06, blue: 0.09).ignoresSafeArea())
    }
}
