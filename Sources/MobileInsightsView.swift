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
                   subtitle: "Your week, brought into focus.",
                   accessory: AnyView(brandRow)) {
            MobileSegmented(options: PatternRange.allCases, selection: $range, label: \.title, compact: true)
            weeklyRhythmCard
            strongestPatternCard
            rhythmCard
            reflectionsCard
        }
        .alert("Understanding a pattern", isPresented: $showingPatternHelp) {
            Button("Done", role: .cancel) { }
        } message: {
            Text("Patterns are observations, not scores. A peak window is simply a useful time to make a little more room for a pause.")
        }
    }

    private var brandRow: some View {
        MobileBrandRow {
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
        VStack(alignment: .leading, spacing: 14) {
            MobileEyebrow(text: range == .seven ? "WEEKLY RHYTHM" : "YOUR RHYTHM")
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(rangeTotal)")
                        .scaledFont(66, weight: .bold)
                        .monospacedDigit()
                        .foregroundStyle(AwairaPalette.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text("approaches")
                        .scaledFont(25, weight: .medium)
                        .foregroundStyle(AwairaPalette.text)
                    HStack(spacing: 7) {
                        Circle().fill(AwairaPalette.rate).frame(width: 10, height: 10)
                        Text("\(rateText(rangeRate) ?? "—")/hr average")
                            .scaledFont(15, weight: .medium)
                            .foregroundStyle(AwairaPalette.rate)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(AwairaPalette.rate.opacity(0.10), in: Capsule())
                    .overlay(Capsule().strokeBorder(AwairaPalette.rate.opacity(0.34), lineWidth: 1))
                    Text(rangePrevented > 0 ? "\(rangePrevented) ended early\nthis \(range == .seven ? "week" : "period")" : "Your history will\nappear here")
                        .awairaSubtitle(15)
                        .foregroundStyle(AwairaPalette.ink.opacity(0.70))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                PatternTrend(values: rhythmValues, labels: rhythmLabels)
                    .frame(width: 210, height: 226)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .awairaCard(padding: 20)
    }

    // MARK: - Strongest pattern

    private var strongestPatternCard: some View {
        HStack(spacing: 13) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .scaledFont(25, weight: .medium)
                .foregroundStyle(AwairaPalette.accent)
                .frame(width: 62, height: 62)
                .background(AwairaPalette.accent.opacity(0.12), in: Circle())
                .overlay(Circle().strokeBorder(AwairaPalette.accent.opacity(0.28), lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                Text("Your strongest pattern")
                    .awairaCaption(14)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.64))
                HStack(spacing: 6) {
                    Text(patternTitle)
                        .scaledFont(19, weight: .semibold)
                        .foregroundStyle(AwairaPalette.text)
                    Text("•")
                        .foregroundStyle(AwairaPalette.ink.opacity(0.48))
                    Text(patternWindow)
                        .scaledFont(19, weight: .semibold)
                        .foregroundStyle(AwairaPalette.accent)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.74)
            }
            Spacer(minLength: 0)
            Button("Explore") { showingPatternHelp = true }
                .buttonStyle(AwairaPrimaryButton())
                .frame(width: 102)
        }
        .frame(maxWidth: .infinity)
        .awairaCard(padding: 14)
    }

    // MARK: - Daily rhythm

    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your rhythm")
                .awairaCardTitle(24)
                .foregroundStyle(AwairaPalette.text)
            DailyRhythm(values: hourlyValues)
                .frame(height: 142)
            Text(rhythmNote)
                .awairaSubtitle(15)
                .foregroundStyle(AwairaPalette.ink.opacity(0.70))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .awairaCard(padding: 18)
    }

    // MARK: - Reflections

    private var reflectionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reflections")
                .awairaCardTitle(24)
                .foregroundStyle(AwairaPalette.text)
            Text("\(rangeJournalEntries.count) moment\(rangeJournalEntries.count == 1 ? "" : "s") captured")
                .awairaSubtitle(15)
                .foregroundStyle(AwairaPalette.ink.opacity(0.66))

            if contextBreakdown.isEmpty {
                MobileEmptyNote(text: "Optional reflections add a little context to your rhythm.",
                                symbol: "square.and.pencil")
            } else {
                VStack(spacing: 14) {
                    ForEach(Array(contextBreakdown.enumerated()), id: \.element.activity) { index, item in
                        reflectionRow(item, color: contextColor(index: index))
                    }
                }
                .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .awairaCard(padding: 18)
    }

    private func reflectionRow(_ item: ContextBreakdown, color: Color) -> some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(item.activity)
                .scaledFont(17)
                .foregroundStyle(AwairaPalette.ink.opacity(0.78))
                .frame(width: 115, alignment: .leading)
            GeometryReader { proxy in
                Capsule()
                    .fill(AwairaPalette.ink.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color).frame(width: max(4, proxy.size.width * item.share))
                    }
            }
            .frame(height: 9)
            Text("\(Int((item.share * 100).rounded()))%")
                .awairaStat(16)
                .foregroundStyle(AwairaPalette.ink.opacity(0.75))
                .frame(width: 42, alignment: .trailing)
        }
    }

    // MARK: - Data

    private var rangeDays: [MobileStatsStore.DayBar] { Array(detector.history.suffix(range.days)) }
    private var rangeTotal: Int { rangeDays.reduce(0) { $0 + $1.interruptions } }
    private var rangePrevented: Int { rangeDays.reduce(0) { $0 + $1.prevented } }
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
        guard let peak = peakHour else { return "As your days fill in, this curve will show when activity tends to gather." }
        return "Your highest activity gathered around \(Self.hourText(peak)) in this \(range == .seven ? "week" : "period")."
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
        [Color(hex: 0xAF64E6), Color(hex: 0xFF726A), AwairaPalette.live, Color(hex: 0xFEAF01)][min(index, 3)]
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

/// A seven-point trend with the reference's blue-to-amber finish and individual day markers.
private struct PatternTrend: View {
    let values: [Int]
    let labels: [String]

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geo in
                let points = chartPoints(in: geo.size)
                ZStack(alignment: .bottomLeading) {
                    ForEach(points.indices, id: \.self) { index in
                        Path { path in
                            path.move(to: CGPoint(x: points[index].x, y: points[index].y))
                            path.addLine(to: CGPoint(x: points[index].x, y: geo.size.height))
                        }
                        .stroke(AwairaPalette.accent.opacity(0.38), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    }
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height - 1))
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - 1))
                    }
                    .stroke(AwairaPalette.ink.opacity(0.22), lineWidth: 1)
                    PatternLine(points: points)
                        .stroke(LinearGradient(colors: [Color(hex: 0x006DF1), AwairaPalette.accent, AwairaPalette.rate], startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    ForEach(points.indices, id: \.self) { index in
                        Circle()
                            .fill(index == points.count - 1 ? AwairaPalette.rate : AwairaPalette.accent)
                            .frame(width: index == points.count - 1 ? 14 : 9, height: index == points.count - 1 ? 14 : 9)
                            .overlay(Circle().strokeBorder(AwairaPalette.text.opacity(0.86), lineWidth: 2))
                            .shadow(color: index == points.count - 1 ? AwairaPalette.rate.opacity(0.55) : .clear, radius: 8)
                            .position(points[index])
                    }
                }
            }
            HStack {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .scaledFont(11)
                        .foregroundStyle(AwairaPalette.ink.opacity(0.72))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        let safeValues = values.isEmpty ? [0] : values
        let maximum = max(safeValues.max() ?? 0, 1)
        return safeValues.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(max(safeValues.count - 1, 1))
            let y = size.height - 8 - CGFloat(value) / CGFloat(maximum) * (size.height - 38)
            return CGPoint(x: x, y: y)
        }
    }
}

private struct DailyRhythm: View {
    let values: [Int]

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let points = points(in: geo.size)
                ZStack(alignment: .bottomLeading) {
                    PatternLine(points: points)
                        .stroke(LinearGradient(colors: [Color(hex: 0x006DF1), AwairaPalette.accent], startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    ForEach(points.indices, id: \.self) { index in
                        if index == peakIndex || index == 0 || index == 12 {
                            Circle()
                                .fill(index == peakIndex ? AwairaPalette.rate : AwairaPalette.live)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(AwairaPalette.text.opacity(0.86), lineWidth: 2))
                                .position(points[index])
                        }
                    }
                    HStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { _ in
                            Circle().fill(AwairaPalette.ink.opacity(0.32)).frame(width: 3, height: 3).frame(maxWidth: .infinity)
                        }
                    }
                    .position(x: geo.size.width / 2, y: geo.size.height - 4)
                }
            }
            HStack {
                Text("12 AM"); Spacer(); Text("12 PM"); Spacer(); Text("Now").foregroundStyle(AwairaPalette.accent)
            }
            .scaledFont(11)
            .foregroundStyle(AwairaPalette.ink.opacity(0.68))
        }
    }

    private var peakIndex: Int { values.indices.max(by: { values[$0] < values[$1] }) ?? 0 }

    private func points(in size: CGSize) -> [CGPoint] {
        let source = values.count == 24 ? values : Array(repeating: 0, count: 24)
        let maximum = max(source.max() ?? 0, 1)
        return source.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(max(source.count - 1, 1))
            let y = size.height - 19 - CGFloat(value) / CGFloat(maximum) * (size.height - 51)
            return CGPoint(x: x, y: y)
        }
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
