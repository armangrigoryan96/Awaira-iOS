import Foundation

/// Sends the single first-run "How did you hear about us?" answer, exactly as the Mac's
/// `AcquisitionReporter` does (awaira/frontend/Sources/Backend.swift).
///
/// The response id is generated once and kept forever, so editing the answer in a later run of
/// onboarding updates that one row instead of adding another — and a timed-out request can never
/// create a duplicate either.
enum MobileAcquisitionReporter {
    static let sourceKey = "acquisitionSource"
    static let otherKey = "acquisitionOther"
    static let submittedKey = "acquisitionSubmitted"
    static let responseIDKey = "acquisitionResponseID"

    static let validSources: Set<String> = [
        "youtube", "tiktok", "instagram", "google_search", "facebook", "reddit", "other",
    ]

    private struct Response: Decodable { let ok: Bool }

    static func submitIfNeeded() async {
        let defaults = UserDefaults.standard
        let source = defaults.string(forKey: sourceKey) ?? ""
        let other = (defaults.string(forKey: otherKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !defaults.bool(forKey: submittedKey),
              validSources.contains(source),
              source != "other" || !other.isEmpty else { return }

        let responseID: String
        if let existing = defaults.string(forKey: responseIDKey), !existing.isEmpty {
            responseID = existing
        } else {
            responseID = UUID().uuidString
            defaults.set(responseID, forKey: responseIDKey)
        }

        var body: [String: Any] = [
            "response_id": responseID,
            "source": source,
            "device": "ios",
        ]
        if source == "other" { body["other_text"] = other }

        do {
            var request = URLRequest(url: URL(string: "https://awaira.app/api/acquisition")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let result = try JSONDecoder().decode(Response.self, from: data)

            // Do not mark a newly edited answer as submitted if an older request finished later.
            let currentSource = defaults.string(forKey: sourceKey) ?? ""
            let currentOther = (defaults.string(forKey: otherKey) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if result.ok, currentSource == source, currentOther == other {
                defaults.set(true, forKey: submittedKey)
            }
        } catch {
            // Keep the answer pending. The app retries on the next launch.
        }
    }
}
