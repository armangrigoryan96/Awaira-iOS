import SwiftUI

/// The Patterns tab turns the private, on-device record into one readable weekly story: how much,
/// when it clustered, and the optional reflections that give it context.
struct MobileInsightsView: View {
    @ObservedObject var detector: Detector
    @ObservedObject var journal: JournalStore
    let onOpenSettings: () -> Void
    @State private var range: PatternRange = .seven
    @State private var showingPatternHelp = false

    var body: some View {
        MobilePage(title: "Patterns",
                   subtitle: "Your week at a glance.",
                   titleSize: 32,
                   accessory: AnyView(brandRow)) {
            MobileSegmented(options: PatternRange.allCases, selection: $range, label: \.title, compact: true)
            weeklyRhythmCard
            patternAndReflectionsCard
            dailyRhythmCard
        }
        .alert("Understanding a pattern", isPresented: $showingPatternHelp) {
            Button("Done", role: .cancel) { }
        } message: {
            Text("Patterns are observations, not scores. A peak window is simply a useful time to make a little more room for a pause.")
        }
    }

    private var brandRow: some View {
        HStack(spacing: 11) {
            Image("logo")
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            Text("Awaira")
                .scaledFont(23, weight: .semibold)
                .foregroundStyle(AwairaPalette.text)
            Spacer(minLength: 8)
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .scaledFont(21, weight: .medium)
                    .foregroundStyle(AwairaPalette.text)
                    .frame(width: 44, height: 44)
                    .background(AwairaPalette.statsSurface, in: Circle())
                    .overlay(Circle().strokeBorder(AwairaPalette.cardBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Weekly rhythm

    private var weeklyRhythmCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(range == .seven ? "Weekly rhythm" : "Your rhythm")
                .awairaCardTitle(20)
                .foregroundStyle(AwairaPalette.text)

            HStack(alignment: .bottom, spacing: 12) {
                HStack(alignment: .lastTextBaseline, spacing: 9) {
                    Text("\(rangeTotal)")
                        .awairaFigure(39)
                        .foregroundStyle(AwairaPalette.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                    Text("approaches")
                        .scaledFont(15, weight: .medium)
                        .foregroundStyle(AwairaPalette.text)
                        .padding(.bottom, 5)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle().fill(AwairaPalette.rate).frame(width: 10, height: 10)
                        Text("\(rateText(rangeRate) ?? "—")/hr")
                            .awairaStat(14)
                            .foregroundStyle(AwairaPalette.rate)
                    }
                    Text("average")
                        .awairaSubtitle(12)
                        .foregroundStyle(AwairaPalette.ink.opacity(0.58))
                }
                .padding(.bottom, 4)
            }

            WeeklyRhythmChart(values: rhythmValues, labels: rhythmLabels)
                .frame(height: 80)
                .accessibilityLabel("Activity by day")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .awairaCard(padding: 12)
    }

    // MARK: - Pattern summary

    /// Keeping the strongest window and the short "what happened" breakdown together gives the
    /// page a compact middle beat without losing the context people have recorded.
    private var patternAndReflectionsCard: some View {
        Button { showingPatternHelp = true } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 11) {
                    Image(systemName: "moon.fill")
                        .scaledFont(20, weight: .medium)
                        .foregroundStyle(AwairaPalette.rate)
                        .frame(width: 44, height: 44)
                        .background(AwairaPalette.rate.opacity(0.12), in: Circle())
                        .overlay(Circle().strokeBorder(AwairaPalette.rate.opacity(0.52), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Strongest pattern")
                            .awairaSubtitle(12)
                            .foregroundStyle(AwairaPalette.ink.opacity(0.62))
                        Text(patternTitle)
                            .awairaCardTitle(17)
                            .foregroundStyle(AwairaPalette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                        Text(patternWindow)
                            .awairaStat(13)
                            .foregroundStyle(AwairaPalette.accent)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Reflections")
                            .awairaSubtitle(12)
                            .foregroundStyle(AwairaPalette.ink.opacity(0.62))
                        Text("\(rangeJournalEntries.count) captured")
                            .awairaStat(13)
                            .foregroundStyle(AwairaPalette.text)
                    }
                }

                Divider().overlay(AwairaPalette.cardBorder)

                if contextBreakdown.isEmpty {
                    HStack {
                        Text("What happened")
                            .awairaSubtitle(12)
                            .foregroundStyle(AwairaPalette.ink.opacity(0.62))
                        Spacer()
                        Text("No moments yet")
                            .awairaSubtitle(12)
                            .foregroundStyle(AwairaPalette.ink.opacity(0.55))
                    }
                } else {
                    VStack(spacing: 5) {
                        ForEach(Array(contextBreakdown.prefix(3).enumerated()), id: \.element.activity) { index, item in
                            reflectionSummaryRow(item, color: contextColor(index: index))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Learn how patterns are calculated. It also shows your reflection count.")
        .awairaCard(padding: 12)
    }

    private func reflectionSummaryRow(_ item: ContextBreakdown, color: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(item.activity)
                .awairaSubtitle(12)
                .foregroundStyle(AwairaPalette.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            GeometryReader { proxy in
                Capsule()
                    .fill(AwairaPalette.ink.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color).frame(width: max(4, proxy.size.width * item.share))
                    }
            }
            .frame(width: 54, height: 6)
            Text("\(Int((item.share * 100).rounded()))%")
                .awairaStat(12)
                .foregroundStyle(AwairaPalette.text)
                .frame(width: 30, alignment: .trailing)
        }
    }

    // MARK: - Daily rhythm

    private var dailyRhythmCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("Daily rhythm")
                    .awairaCardTitle(20)
                    .foregroundStyle(AwairaPalette.text)
                Spacer(minLength: 6)
                Text(range == .seven ? "Last 7 days" : "This period")
                    .awairaSubtitle(12)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.62))
            }
            DailyRhythmChart(values: hourlyValues, peakHour: peakHour)
                .frame(height: 87)
                .accessibilityLabel("Activity by hour")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .awairaCard(padding: 12)
    }

    // MARK: - Data

    private var rangeDays: [MobileStatsStore.DayBar] { Array(detector.history.suffix(range.days)) }
    private var rangeTotal: Int { rangeDays.reduce(0) { $0 + $1.interruptions } }
    private var rangeRate: Double {
        MobileStatsStore.hourlyRate(interruptions: rangeTotal,
                                    activeSeconds: rangeDays.reduce(0) { $0 + $1.activeSeconds })
    }

    private var rhythmValues: [Int] {
        let source = rangeDays.map(\.interruptions)
        guard source.count > 7 else { return source }
        let bucketSize = Int(ceil(Double(source.count) / 7.0))
        return stride(from: 0, to: source.count, by: bucketSize).map { start in
            source[start..<min(start + bucketSize, source.count)].reduce(0, +)
        }
    }

    private var rhythmLabels: [String] {
        if range == .seven { return rangeDays.map { Self.weekday($0.date) } }
        return rhythmValues.indices.map { index in index == 0 ? "Start" : (index == rhythmValues.count - 1 ? "Now" : "") }
    }

    private var hourlyValues: [Int] {
        rangeDays.reduce(into: Array(repeating: 0, count: 24)) { total, day in
            for bar in detector.hoursByDay[day.id] ?? [] {
                let hour = Calendar.current.component(.hour, from: bar.date)
                if total.indices.contains(hour) { total[hour] += bar.interruptions }
            }
        }
    }

    private var peakHour: Int? {
        guard let maximum = hourlyValues.max(), maximum > 0 else { return nil }
        return hourlyValues.firstIndex(of: maximum)
    }

    private var patternTitle: String {
        guard let peak = peakHour else { return "Still building" }
        switch peak {
        case 0..<6: return "Early morning"
        case 6..<12: return "Late morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Late evening"
        default: return "Night time"
        }
    }

    private var patternWindow: String {
        guard let peak = peakHour else { return "your baseline" }
        return "\(Self.hourText(peak))–\(Self.hourText((peak + 2) % 24))"
    }

    private var rhythmNote: String {
        guard let peak = peakHour else { return "After a few days of tracking, this chart will show your busiest hours." }
        return "Activity peaks around \(Self.hourText(peak))."
    }

    private var rangeJournalEntries: [JournalEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -(range.days - 1),
                                           to: Calendar.current.startOfDay(for: Date()))
        guard let cutoff else { return journal.entries }
        return journal.entries.filter { $0.date >= cutoff && !$0.activity.isEmpty }
    }

    private var contextBreakdown: [ContextBreakdown] {
        let counts = Dictionary(grouping: rangeJournalEntries, by: \.activity)
            .map { ContextBreakdown(activity: $0.key, count: $0.value.count,
                                    share: Double($0.value.count) / Double(max(rangeJournalEntries.count, 1))) }
        return counts.sorted {
            $0.count == $1.count ? $0.activity.localizedCaseInsensitiveCompare($1.activity) == .orderedAscending
                                 : $0.count > $1.count
        }.prefix(4).map { $0 }
    }

    private func contextColor(index: Int) -> Color {
        [AwairaPalette.accent, AwairaPalette.rate, AwairaPalette.live, AwairaPalette.streak][min(index, 3)]
    }

    private func rateText(_ value: Double) -> String? {
        guard value > 0 else { return nil }
        return value >= 10 ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
    }

    private static func hourText(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h) \(hour < 12 ? "AM" : "PM")"
    }

    private static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }
}

private enum PatternRange: CaseIterable, Identifiable, Hashable {
    case today, seven, thirty, ninety, year
    var id: Self { self }
    var days: Int {
        switch self { case .today: return 1; case .seven: return 7; case .thirty: return 30; case .ninety: return 90; case .year: return 365 }
    }
    var title: String {
        switch self { case .today: return "Today"; case .seven: return "7 days"; case .thirty: return "30 days"; case .ninety: return "90 days"; case .year: return "1 year" }
    }
}

private struct ContextBreakdown {
    let activity: String
    let count: Int
    let share: Double
}

/// A compact column chart with subdued guides: it makes the latest active day read immediately
/// while zero-activity days remain visible as dots on the baseline.
private struct WeeklyRhythmChart: View {
    let values: [Int]
    let labels: [String]

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geo in
                let source = values.isEmpty ? [0] : values
                let top = chartTop(for: source)
                let plot = CGRect(x: 30, y: 5, width: max(1, geo.size.width - 30), height: max(1, geo.size.height - 24))
                ZStack(alignment: .topLeading) {
                    ForEach([0.0, 0.5, 1.0], id: \.self) { fraction in
                        let y = plot.maxY - plot.height * fraction
                        Path { path in
                            path.move(to: CGPoint(x: plot.minX, y: y))
                            path.addLine(to: CGPoint(x: plot.maxX, y: y))
                        }
                        .stroke(AwairaPalette.ink.opacity(fraction == 0 ? 0.48 : 0.16),
                                style: StrokeStyle(lineWidth: fraction == 0 ? 1 : 0.8, dash: fraction == 0 ? [] : [5, 5]))
                        Text("\(Int((Double(top) * fraction).rounded()))")
                            .scaledFont(11, weight: .medium)
                            .foregroundStyle(AwairaPalette.ink.opacity(0.72))
                            .frame(width: 23, alignment: .trailing)
                            .position(x: 11, y: y)
                    }

                    ForEach(source.indices, id: \.self) { index in
                        let unit = plot.width / CGFloat(source.count)
                        let height = max(0, plot.height * CGFloat(source[index]) / CGFloat(top))
                        let x = plot.minX + unit * (CGFloat(index) + 0.5)
                        if height > 0 {
                            RoundedRectangle(cornerRadius: min(10, max(3, height / 2)), style: .continuous)
                                .fill(LinearGradient(colors: [AwairaPalette.accent.opacity(0.82), AwairaPalette.accent],
                                                     startPoint: .bottom, endPoint: .top))
                                .frame(width: min(36, max(12, unit * 0.40)), height: height)
                                .position(x: x, y: plot.maxY - height / 2)
                        } else {
                            Circle()
                                .fill(AwairaPalette.accent)
                                .frame(width: 9, height: 9)
                                .position(x: x, y: plot.maxY)
                        }
                    }
                }
            }
            .clipped()

            HStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .scaledFont(12, weight: .medium)
                        .foregroundStyle(AwairaPalette.ink.opacity(0.70))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.leading, 30)
        }
    }

    private func chartTop(for source: [Int]) -> Int {
        let maximum = max(source.max() ?? 0, 1)
        return max(3, Int(ceil(Double(maximum) / 6.0)) * 6)
    }
}

private struct DailyRhythmChart: View {
    let values: [Int]
    let peakHour: Int?

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geo in
                let plot = CGRect(x: 0, y: 20, width: geo.size.width, height: max(1, geo.size.height - 29))
                let points = chartPoints(in: plot)
                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.move(to: CGPoint(x: plot.minX, y: plot.maxY))
                        path.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
                    }
                    .stroke(AwairaPalette.ink.opacity(0.42), lineWidth: 1)

                    PatternLine(points: points)
                        .stroke(AwairaPalette.accent,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    if let peakHour, values.indices.contains(peakHour), values[peakHour] > 0 {
                        let peak = points[peakHour]
                        Path { path in
                            path.move(to: CGPoint(x: peak.x, y: peak.y + 8))
                            path.addLine(to: CGPoint(x: peak.x, y: plot.maxY))
                        }
                        .stroke(AwairaPalette.rate.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        Text(hourText(peakHour))
                            .scaledFont(12, weight: .medium)
                            .foregroundStyle(AwairaPalette.text)
                            .position(x: peak.x, y: 8)
                        Circle()
                            .fill(AwairaPalette.rate)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(AwairaPalette.statsSurface, lineWidth: 2))
                            .position(peak)
                    }

                    HStack(spacing: 0) {
                        ForEach(0..<25, id: \.self) { _ in
                            Rectangle()
                                .fill(AwairaPalette.ink.opacity(0.35))
                                .frame(width: 1, height: 5)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .position(x: plot.midX, y: plot.maxY)
                }
            }
            HStack {
                Text("12 AM")
                Spacer()
                Text("6 AM")
                Spacer()
                Text("12 PM")
                Spacer()
                Text("6 PM")
                Spacer()
                Text("12 AM")
            }
            .scaledFont(11, weight: .medium)
            .foregroundStyle(AwairaPalette.ink.opacity(0.68))
        }
    }

    private func chartPoints(in plot: CGRect) -> [CGPoint] {
        let source = values.count == 24 ? values : Array(repeating: 0, count: 24)
        let maximum = max(source.max() ?? 0, 1)
        return source.enumerated().map { index, value in
            let x = plot.minX + plot.width * CGFloat(index) / CGFloat(max(source.count - 1, 1))
            let y = plot.maxY - 9 - CGFloat(value) / CGFloat(maximum) * (plot.height - 22)
            return CGPoint(x: x, y: y)
        }
    }

    private func hourText(_ hour: Int) -> String {
        let value = hour % 12 == 0 ? 12 : hour % 12
        return "\(value) \(hour < 12 ? "AM" : "PM")"
    }
}

private struct PatternLine: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        guard let first = points.first else { return Path() }
        var path = Path()
        path.move(to: first)
        for index in points.indices.dropFirst() {
            let prior = points[index - 1]
            let current = points[index]
            let middle = CGPoint(x: (prior.x + current.x) / 2, y: (prior.y + current.y) / 2)
            path.addQuadCurve(to: middle, control: prior)
            path.addQuadCurve(to: current, control: middle)
        }
        return path
    }
}
