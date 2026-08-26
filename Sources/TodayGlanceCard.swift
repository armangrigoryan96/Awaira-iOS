import SwiftUI

/// "Today at a glance": the two headline numbers, how the week compares to the last one, and the
/// seven-day strip — one card rather than the three the page used to stack.
///
/// The three used to be separate cards with their own borders and their own padding, which cost
/// about 90pt of the page for nothing but repetition: they are all the same subject, read together,
/// in the order the design lists them. The chevron opens the fuller version of the same subject.
struct TodayGlanceCard: View {
    let count: Int
    /// `nil` until there is enough tracked time to state a rate — the same rule the tiles used, so
    /// the number never reads as "zero per hour" when it means "not measured yet".
    let rate: Double?
    /// Positive means this seven days ran *lower* than the previous seven, as `MobileStatsStore`
    /// builds it. `nil` when there is not enough of a previous week to compare against.
    let weeklyImprovement: Double?
    let week: [MobileStatsStore.DayBar]
    /// Which column is lit; the caller's heatmap follows the same value.
    @Binding var selectedDayID: String?
    let onOpenDetail: () -> Void

    /// Under a minute of tracking a rate says more about the clock than about the day.
    static let minTrackedSeconds = 60.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow

            headlineNumbers
                .padding(.top, 12)

            if let comparison {
                comparisonLine(comparison)
                    .padding(.top, 8)
            }

            rule.padding(.top, 14)

            Text("WEEK TREND")
                .font(.system(size: 11, weight: .medium))
                .kerning(0.6)
                .foregroundStyle(AwairaPalette.ink.opacity(0.72))
                .padding(.top, 12)

            weekStrip
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .awairaCard(padding: 14)
        .animation(.easeInOut(duration: 0.18), value: effectiveDayID)
    }

    // MARK: - Chrome

    private var eyebrowRow: some View {
        Button(action: onOpenDetail) {
            HStack(spacing: 8) {
                Text("TODAY AT A GLANCE")
                    .font(.system(size: 11, weight: .medium))
                    .kerning(0.6)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.72))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AwairaPalette.ink.opacity(0.45))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("glanceDetail")
    }

    private var rule: some View {
        Rectangle()
            .fill(AwairaPalette.cardBorder)
            .frame(height: 1)
    }

    // MARK: - Headline numbers

    /// The pair sits either side of one hairline rather than in two bordered boxes: they are a
    /// comparison — the same day counted two ways — not two unrelated statistics.
    private var headlineNumbers: some View {
        HStack(alignment: .top, spacing: 14) {
            metric(label: "PER HOUR",
                   value: rate.map { String(format: "%.0f", $0) } ?? "—",
                   suffix: rate == nil ? nil : "/hr",
                   tint: AwairaPalette.rate,
                   symbol: "stopwatch",
                   identifier: nil)

            Rectangle()
                .fill(AwairaPalette.cardBorder)
                .frame(width: 1, height: 56)

            metric(label: "TOTAL APPROACHES",
                   value: "\(count)",
                   suffix: nil,
                   tint: AwairaPalette.accent,
                   symbol: "waveform.path.ecg",
                   identifier: "todayCount")
        }
    }

    private func metric(label: String, value: String, suffix: String?, tint: Color,
                        symbol: String, identifier: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .kerning(0.6)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(tint)
            }
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(value)
                    .font(.system(size: 36, design: .serif))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .accessibilityIdentifier(identifier ?? "")
                if let suffix {
                    Text(suffix)
                        .font(.system(size: 18, design: .serif))
                        .foregroundStyle(tint.opacity(0.85))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The week-over-week line, phrased in the direction that matters: fewer approaches per hour is
    /// the good outcome, so a drop is the accent colour and a rise is the warm one.
    private func comparisonLine(_ comparison: (amount: Int, lower: Bool)) -> some View {
        let tint = comparison.lower ? AwairaPalette.accent : AwairaPalette.streak
        return HStack(spacing: 5) {
            Image(systemName: comparison.lower ? "arrow.down" : "arrow.up")
                .font(.system(size: 11, weight: .semibold))
            Text("\(comparison.amount)% \(comparison.lower ? "lower" : "higher") vs last week")
                .font(.system(size: 13))
        }
        .foregroundStyle(tint)
    }

    /// The rounded percentage and its direction, or `nil` when there is nothing to compare against
    /// or the difference rounds away to nothing.
    private var comparison: (amount: Int, lower: Bool)? {
        guard let weeklyImprovement else { return nil }
        let amount = Int(abs(weeklyImprovement).rounded())
        guard amount >= 1 else { return nil }
        return (amount, weeklyImprovement > 0)
    }

    // MARK: - Week strip

    private var weekStrip: some View {
        HStack(spacing: 4) {
            ForEach(week) { day in
                weekColumn(day)
            }
        }
    }

    private func weekColumn(_ day: MobileStatsStore.DayBar) -> some View {
        let isSelected = day.id == effectiveDayID
        let dayTracked = day.activeSeconds >= Self.minTrackedSeconds
        let isToday = day.id == week.last?.id
        let rate = MobileStatsStore.hourlyRate(interruptions: day.interruptions,
                                               activeSeconds: day.activeSeconds)

        return Button {
            selectedDayID = day.id
        } label: {
            VStack(spacing: 1) {
                // Today is named rather than abbreviated, as in the design — the strip should not
                // need the date underneath it to answer "where am I".
                Text(isToday ? "Today" : Self.weekdayFormatter.string(from: day.date).uppercased())
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? AwairaPalette.navSelectedText.opacity(0.85)
                                               : AwairaPalette.ink.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(Calendar.current.component(.day, from: day.date))")
                    .font(.system(size: 21, design: .serif))
                    .foregroundStyle(isSelected ? AwairaPalette.navSelectedText : AwairaPalette.text)
                    .monospacedDigit()

                // Present on every column and merely hidden on the untracked ones: an empty string
                // would collapse to zero height and lift that column's icon above the others.
                Text(String(format: "%.0f/hr", rate))
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? AwairaPalette.navSelectedText.opacity(0.85)
                                               : AwairaPalette.ink.opacity(0.7))
                    .monospacedDigit()
                    .opacity(dayTracked ? 1 : 0)

                // Amber on every day, the selected one included: the plate turns blue under it, the
                // icon does not change colour with it.
                Image(systemName: "stopwatch")
                    .font(.system(size: 12))
                    .foregroundStyle(AwairaPalette.rate)
                    .opacity(dayTracked && day.interruptions > 0 ? 1 : 0)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(isSelected ? AwairaPalette.navSelected : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The selected day, falling back to today whenever nothing is selected or the selection has
    /// aged out of the seven days the strip shows.
    private var effectiveDayID: String? {
        if let selectedDayID, week.contains(where: { $0.id == selectedDayID }) {
            return selectedDayID
        }
        return week.last?.id
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f
    }()
}
