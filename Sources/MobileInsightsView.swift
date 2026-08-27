import SwiftUI

/// The phone's Patterns surface. It presents the same calm, on-device aggregate data as the
/// desktop dashboard, but in the compact hierarchy from the mobile design.
struct MobileInsightsView: View {
    @ObservedObject var detector: Detector
    @State private var range: PatternRange = .today

    private let goalRate = 24.0
    private let chartHours = [0, 5, 10, 14, 15, 20, 23]
    private let chartLabels = ["12 AM", "5 AM", "10 AM", "2 PM", "3 PM", "8 PM", "11 PM"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                brand
                Text("Patterns")
                    .font(.system(size: 39, weight: .regular, design: .serif))
                    .foregroundStyle(AwairaPalette.text)

                rangePicker
                goalCard
                chartCard
                momentsCard
                progressCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 18)
        }
        .background(AwairaPalette.window.ignoresSafeArea())
        .tint(AwairaPalette.navSelected)
    }

    private var brand: some View {
        HStack(spacing: 9) {
            Image("logo")
                .resizable()
                .scaledToFill()
                .frame(width: 31, height: 31)
                .clipShape(Circle())
            Text("Awaira")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(AwairaPalette.text)
        }
        .padding(.top, 3)
    }

    private var rangePicker: some View {
        HStack(spacing: 3) {
            ForEach(PatternRange.allCases) { item in
                Button {
                    range = item
                } label: {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(range == item ? Color.white : AwairaPalette.ink.opacity(0.68))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(range == item ? AwairaPalette.navSelected : .clear,
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AwairaPalette.statsSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(AwairaPalette.cardBorder, lineWidth: 1))
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your goal")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AwairaPalette.text)
            Text(goalStatus)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AwairaPalette.accent)

            HStack(alignment: .bottom, spacing: 20) {
                goalValue(title: "Current", value: rateText(currentRate), suffix: "/hr")
                Divider()
                    .frame(height: 50)
                    .overlay(AwairaPalette.cardBorder)
                goalValue(title: "Goal", value: "Under \(Int(goalRate))", suffix: "/hr")
            }
        }
        .awairaCard(padding: 16)
    }

    private func goalValue(title: String, value: String, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(AwairaPalette.ink.opacity(0.58))
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 29, design: .serif))
                Text(suffix)
                    .font(.system(size: 17, design: .serif))
            }
            .foregroundStyle(AwairaPalette.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Your patterns")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AwairaPalette.text)
                Spacer()
                metricPicker
            }

            Text("Peak window")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AwairaPalette.rate)
                .frame(maxWidth: .infinity, alignment: .center)

            hourlyBars
        }
        .awairaCard(padding: 16)
    }

    private var metricPicker: some View {
        HStack(spacing: 0) {
            Text("Hourly rate")
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AwairaPalette.navSelected, in: Capsule())
            Text("Total touches")
                .foregroundStyle(AwairaPalette.ink.opacity(0.65))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .font(.system(size: 11, weight: .medium))
        .background(AwairaPalette.window, in: Capsule())
        .overlay(Capsule().strokeBorder(AwairaPalette.cardBorder, lineWidth: 1))
    }

    private var hourlyBars: some View {
        let values = chartHours.map { hour in
            detector.hourOfWeek.indices.contains(hour) ? detector.hourOfWeek[hour] : 0
        }
        let maximum = max(values.max() ?? 0, 1)

        return VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 9) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 5) {
                        ZStack(alignment: .bottom) {
                            Capsule()
                                .fill(AwairaPalette.cardBorder.opacity(0.72))
                                .frame(height: 110)
                            Capsule()
                                .fill(index == peakChartIndex ? AwairaPalette.rate : AwairaPalette.navSelected)
                                .frame(height: max(3, 110 * CGFloat(value) / CGFloat(maximum)))
                        }
                        Text(chartLabels[index])
                            .font(.system(size: 9))
                            .foregroundStyle(AwairaPalette.ink.opacity(0.58))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 137)

            Text(chartFootnote)
                .font(.system(size: 12))
                .foregroundStyle(AwairaPalette.ink.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var momentsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Most common moments")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AwairaPalette.text)
                .padding(.bottom, 4)
            moment("book.closed", "Reading", 8)
            Divider().overlay(AwairaPalette.cardBorder)
            moment("iphone", "Phone scrolling", 6)
            Divider().overlay(AwairaPalette.cardBorder)
            moment("brain.head.profile", "Thinking", 5)
        }
        .awairaCard(padding: 16)
    }

    private func moment(_ symbol: String, _ title: String, _ count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(AwairaPalette.text)
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(AwairaPalette.cardBorder, lineWidth: 1))
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(AwairaPalette.text)
            Spacer()
            Text("\(count)")
                .font(.system(size: 24, design: .serif))
                .foregroundStyle(AwairaPalette.accent)
        }
        .padding(.vertical, 3)
    }

    private var progressCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AWARENESS PROGRESS")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.5)
                    .foregroundStyle(AwairaPalette.navSelected)
                Text("\(detector.weeklyTotal)")
                    .font(.system(size: 37, design: .serif))
                    .foregroundStyle(AwairaPalette.accent)
                Text("You noticed the pattern\n\(detector.weeklyTotal) times this week")
                    .font(.system(size: 13))
                    .foregroundStyle(AwairaPalette.ink.opacity(0.58))
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(AwairaPalette.accent)
                    .frame(width: 66, height: 66)
                    .overlay(Circle().strokeBorder(AwairaPalette.accent, lineWidth: 1.5))
                Label("4-day streak", systemImage: "flame")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AwairaPalette.streak)
            }
        }
        .awairaCard(padding: 16)
    }

    private var currentRate: Double {
        detector.weeklyRate
    }

    private var goalStatus: String {
        let difference = Int(abs(goalRate - currentRate).rounded())
        return currentRate <= goalRate ? "\(difference) touches/hr under your goal" : "\(difference) touches/hr above your goal"
    }

    private var peakChartIndex: Int {
        let values = chartHours.map { detector.hourOfWeek.indices.contains($0) ? detector.hourOfWeek[$0] : 0 }
        return values.indices.max(by: { values[$0] < values[$1] }) ?? 0
    }

    private var chartFootnote: String {
        let hour = chartHours[peakChartIndex]
        let next = (hour + 1) % 24
        return "Peak window: \(hourText(hour))–\(hourText(next))."
    }

    private func hourText(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h) \(hour < 12 ? "AM" : "PM")"
    }

    private func rateText(_ value: Double) -> String {
        value >= 10 ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
    }
}

private enum PatternRange: String, CaseIterable, Identifiable {
    case today, sevenDays, thirtyDays, ninetyDays

    var id: Self { self }
    var title: String {
        switch self {
        case .today: "Today"
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        case .ninetyDays: "90 days"
        }
    }
}
