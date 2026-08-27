import SwiftUI

/// The daily dashboard follows one calm reading path: the day, one awareness number, the week in
/// context, a useful next moment, and the places a person has noticed.
struct TodayView: View {
    @ObservedObject var detector: Detector
    let cameraRequested: Bool
    let onToggleCamera: () -> Void
    let onOpenSettings: () -> Void

    @State private var selectedDayID: String?
    @State private var showingGuidance = false
    @AppStorage("touchZonesMirrored") private var zonesMirrored = false

    private static let minTrackedSeconds = 60.0

    var body: some View {
        MobilePage(title: Self.dateFormatter.string(from: Date()),
                   subtitle: "Awareness today. Progress tomorrow.",
                   accessory: AnyView(brandRow)) {
            if let errorText = detector.errorText { errorBanner(errorText) }
            awarenessCard
            weekStrip
            guidanceCard
            TouchZonesCard(counts: shownZones, mirrored: $zonesMirrored)
        }
        .alert("A gentle cue", isPresented: $showingGuidance) {
            Button("Done", role: .cancel) { }
        } message: {
            Text("When the next peak window arrives, lower your hand, take one slow breath, and continue with what matters.")
        }
    }

    // MARK: - Header

    private var brandRow: some View {
        MobileBrandRow {
            HStack(spacing: 8) {
                cameraPill
                settingsButton
            }
        }
    }

    /// The camera switch, and the app's only one — there is nowhere else in the design for it, so
    /// losing it from the header left no way to pause detection at all. It reads as a state, not an
    /// instruction: a lit dot and "Camera on" while detection runs, a dull one and "Camera off"
    /// while it does not. The Mac says the same thing with the same two pieces.
    private var cameraPill: some View {
        Button(action: onToggleCamera) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isLive ? AwairaPalette.live : AwairaPalette.ink.opacity(0.3))
                    .frame(width: 7, height: 7)
                Text(isLive ? "Camera on" : "Camera off")
                    .scaledFont(13, weight: .medium)
                    .lineLimit(1)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.8))
            }
            .awairaPill(horizontal: 11, vertical: 7)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("toggleCamera")
        .accessibilityLabel(isLive ? "Camera on" : "Camera off")
        .animation(.easeInOut(duration: 0.15), value: isLive)
    }

    /// Detection is on because the user asked for it and has not switched it back off. Deliberately
    /// the user's intent rather than `detector.connected`: capture also stops for a phone call or a
    /// stashed PiP window, and the switch must not appear to flip itself in those moments.
    private var isLive: Bool { cameraRequested && !detector.paused && detector.errorText == nil }

    private var settingsButton: some View {
        Group {
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .scaledFont(15)
                    .foregroundStyle(AwairaPalette.text)
                    .frame(width: 44, height: 44)
                    .background(AwairaPalette.statsSurface, in: Circle())
                    .overlay(Circle().strokeBorder(AwairaPalette.cardBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settingsToggle")
            .accessibilityLabel("Settings")
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .scaledFont(13)
                .foregroundStyle(AwairaPalette.alert)
            Text(text)
                .awairaCaption()
                .foregroundStyle(AwairaPalette.alert)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AwairaPalette.alert.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: AwairaPalette.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AwairaPalette.cardRadius, style: .continuous)
                .strokeBorder(AwairaPalette.alert.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Awareness

    private var awarenessCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            MobileEyebrow(text: "TODAY'S AWARENESS")

            HStack(alignment: .bottom, spacing: 8) {
                Text(tracked ? String(format: "%.0f", todayRate) : "—")
                    .awairaFigure(58)
                    .foregroundStyle(tracked ? AwairaPalette.accent : AwairaPalette.ink.opacity(0.28))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if tracked {
                    Text("/hr")
                        .awairaFigure(26, weight: .medium)
                        .foregroundStyle(AwairaPalette.text)
                        .padding(.bottom, 11)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(detector.count)")
                    .awairaFigure(22)
                    .foregroundStyle(AwairaPalette.text)
                    .accessibilityIdentifier("todayCount")
                Text(detector.count == 1 ? "approach today" : "approaches today")
                    .awairaCaption(14)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.6))
            }

            HStack(spacing: 8) {
                Circle().fill(awarenessTint).frame(width: 10, height: 10)
                Text(awarenessLabel)
                    .scaledFont(16, weight: .semibold)
                    .foregroundStyle(awarenessTint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(awarenessTint.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(awarenessTint.opacity(0.32), lineWidth: 1))

            Text(tracked ? "\(detector.preventedPulls) approaches interrupted early"
                         : "Tracking builds a gentle daily baseline")
                .awairaCaption(14)
                .foregroundStyle(AwairaPalette.ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            AwarenessTrend(values: trendValues)
                .frame(height: 96)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .awairaCard(padding: 16)
    }

    private var awarenessLabel: String {
        guard tracked else { return "Building baseline" }
        switch todayRate {
        case 20...: return "Elevated"
        case 8...: return "Noticeable"
        default: return "Calm"
        }
    }

    private var awarenessTint: Color {
        tracked && todayRate >= 20 ? AwairaPalette.rate : AwairaPalette.accent
    }

    // MARK: - Week

    private var weekStrip: some View {
        VStack(alignment: .leading, spacing: 13) {
            MobileEyebrow(text: "THIS WEEK")
            HStack(spacing: 0) {
                ForEach(Array(detector.week.enumerated()), id: \.element.id) { index, day in
                    weekColumn(day)
                        .frame(maxWidth: .infinity)
                    if index < detector.week.count - 1 {
                        AwairaVerticalRule(height: 92)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .awairaCard(padding: 16)
        .animation(.easeInOut(duration: 0.18), value: selectedDayID)
    }

    private func weekColumn(_ day: MobileStatsStore.DayBar) -> some View {
        let isSelected = day.id == effectiveDayID
        let isToday = Calendar.current.isDateInToday(day.date)
        let dayTracked = day.activeSeconds >= Self.minTrackedSeconds
        let rate = MobileStatsStore.hourlyRate(interruptions: day.interruptions,
                                               activeSeconds: day.activeSeconds)

        return Button { selectedDayID = day.id } label: {
            VStack(spacing: 0) {
                Text(Self.weekdayFormatter.string(from: day.date).uppercased())
                    .scaledFont(10, weight: .semibold)
                    .tracking(0.6)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.58))
                Text("\(Calendar.current.component(.day, from: day.date))")
                    .awairaFigure(25)
                    .foregroundStyle(isSelected ? AwairaPalette.text : AwairaPalette.ink.opacity(0.76))
                    .padding(.top, 4)
                Text(String(format: "%.0f/hr", rate))
                    .scaledFont(11)
                    .monospacedDigit()
                    .foregroundStyle(AwairaPalette.ink.opacity(0.62))
                    .padding(.top, 4)
                    .opacity(dayTracked ? 1 : 0)
                Image(systemName: "flame.fill")
                    .scaledFont(13)
                    .foregroundStyle(AwairaPalette.streak)
                    .padding(.top, 4)
                    .opacity(dayTracked && day.interruptions > 0 ? 1 : 0)
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? AwairaPalette.accent : (isToday ? AwairaPalette.accent.opacity(0.32) : .clear))
                    .frame(width: 30, height: 3)
                    .padding(.top, 7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day.date.formatted(date: .abbreviated, time: .omitted)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Guidance

    private var guidanceCard: some View {
        HStack(spacing: 13) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .scaledFont(25, weight: .medium)
                .foregroundStyle(AwairaPalette.accent)
                .frame(width: 58, height: 58)
                .background(AwairaPalette.accent.opacity(0.12), in: Circle())
                .overlay(Circle().strokeBorder(AwairaPalette.accent.opacity(0.28), lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                Text("Next best moment")
                    .awairaCaption(14)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.64))
                Text("Peak window")
                    .scaledFont(17, weight: .semibold)
                    .foregroundStyle(AwairaPalette.text)
                    .lineLimit(1)
                Text(peakWindowText)
                    .awairaStat(14)
                    .foregroundStyle(AwairaPalette.accent)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                showingGuidance = true
            } label: {
                Text("Guidance")
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(AwairaPalette.accent)
                    .awairaPill(horizontal: 14, vertical: 8)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .awairaCard(padding: 14)
    }

    // MARK: - Data

    private var effectiveDayID: String? {
        if let selectedDayID, detector.week.contains(where: { $0.id == selectedDayID }) {
            return selectedDayID
        }
        return detector.week.last?.id
    }

    private var shownDay: [MobileStatsStore.DayBar] {
        guard let effectiveDayID, let hours = detector.hoursByDay[effectiveDayID] else {
            return detector.chartDay
        }
        return hours
    }

    private var shownZones: [String: Int] {
        guard let effectiveDayID else { return detector.zoneCounts }
        return detector.zonesByDay[effectiveDayID] ?? [:]
    }

    private var trendValues: [Int] {
        let calendar = Calendar.current
        return [0, 6, 12, 18, 22].map { hour in
            shownDay.first { calendar.component(.hour, from: $0.date) == hour }?.interruptions ?? 0
        }
    }

    private var tracked: Bool { detector.activeSecondsToday >= Self.minTrackedSeconds }

    private var todayRate: Double {
        MobileStatsStore.hourlyRate(interruptions: detector.count,
                                    activeSeconds: detector.activeSecondsToday)
    }

    private var peakWindowText: String {
        let calendar = Calendar.current
        let source = shownDay.filter { $0.interruptions > 0 }
        guard let peak = source.max(by: { $0.interruptions < $1.interruptions }) else { return "Build your baseline" }
        let start = calendar.component(.hour, from: peak.date)
        return "\(Self.hourText(start))–\(Self.hourText((start + 2) % 24))"
    }

    private static func hourText(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE, MMMM d")
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f
    }()
}

/// A small, source-free line chart: its values come from the selected day, while its simple curve
/// preserves the visual rhythm of the reference dashboard.
private struct AwarenessTrend: View {
    let values: [Int]
    private let labels = ["00", "06", "12", "18", "22"]

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geo in
                let points = normalizedPoints(in: geo.size)
                ZStack(alignment: .bottomLeading) {
                    ForEach(1..<labels.count, id: \.self) { index in
                        Path { path in
                            let x = geo.size.width * CGFloat(index) / CGFloat(labels.count - 1)
                            path.move(to: CGPoint(x: x, y: geo.size.height * 0.23))
                            path.addLine(to: CGPoint(x: x, y: geo.size.height))
                        }
                        .stroke(AwairaPalette.ink.opacity(0.20), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    }
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height - 1))
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - 1))
                    }
                    .stroke(AwairaPalette.ink.opacity(0.20), lineWidth: 1)
                    TrendPath(points: points)
                        .stroke(AwairaPalette.accent,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    if let last = points.last {
                        Circle()
                            .fill(AwairaPalette.rate)
                            .frame(width: 13, height: 13)
                            .overlay(Circle().strokeBorder(AwairaPalette.statsSurface, lineWidth: 1.5))
                            .position(last)
                    }
                }
            }
            .frame(height: 106)
            HStack {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .scaledFont(10)
                        .foregroundStyle(AwairaPalette.ink.opacity(0.60))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let maximum = max(values.max() ?? 0, 1)
        return values.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
            let normalized = CGFloat(value) / CGFloat(maximum)
            let y = size.height - 10 - normalized * (size.height - 34)
            return CGPoint(x: x, y: y)
        }
    }
}

private struct TrendPath: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        guard let first = points.first else { return Path() }
        var path = Path()
        path.move(to: first)
        for index in points.indices.dropFirst() {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: midpoint, control: previous)
            path.addQuadCurve(to: current, control: midpoint)
        }
        return path
    }
}
