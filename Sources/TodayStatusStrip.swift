import SwiftUI

/// The three standing figures at the foot of Today: how many days running, how long the camera has
/// been watching today, and the longest quiet stretch of yesterday.
///
/// Not a card — a row on the page under a hairline, as on the Mac. These are the day's footnotes,
/// and giving them a border of their own would make them compete with the cards above.
struct TodayStatusStrip: View {
    let streakDays: Int
    let protectedSeconds: Double
    /// `nil` when yesterday was not tracked enough to have an answer.
    let cleanStreakHours: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            stat(symbol: "flame.fill",
                 tint: AwairaPalette.streak,
                 value: streakDays > 0 ? "\(streakDays) \(streakDays == 1 ? "day" : "days")" : "—",
                 label: "Tracking streak")

            divider

            stat(symbol: "shield",
                 tint: AwairaPalette.accent,
                 value: Self.trackedTimeText(protectedSeconds),
                 label: "Protected today")

            divider

            stat(symbol: "sparkles",
                 tint: AwairaPalette.rate,
                 value: cleanStreakHours.map { "\($0) \($0 == 1 ? "hr" : "hrs")" } ?? "—",
                 label: "Clean streak")
        }
        .padding(.top, 12)
        .overlay(Rectangle().fill(AwairaPalette.cardBorder).frame(height: 1), alignment: .top)
    }

    private var divider: some View {
        Rectangle()
            .fill(AwairaPalette.cardBorder)
            .frame(width: 1, height: 32)
    }

    private func stat(symbol: String, tint: Color, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AwairaPalette.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AwairaPalette.ink.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    /// Tracked camera-on time as "6h 36m", the way the Mac's status row prints it.
    static func trackedTimeText(_ seconds: Double) -> String {
        guard seconds >= 60 else { return "<1 min" }
        let hours = Int(seconds / 3600)
        let minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
