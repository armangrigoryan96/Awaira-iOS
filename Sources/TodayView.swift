import SwiftUI

/// The compact daily dashboard: headline numbers, a week strip, the hourly heatmap, and today's
/// touch-location map.
struct TodayView: View {
    @ObservedObject var detector: Detector
    let cameraRequested: Bool
    let onToggleCamera: () -> Void
    let onOpenSettings: () -> Void

    @State private var selectedDayID: String?

    private static let minTrackedSeconds = 60.0

    var body: some View {
        GeometryReader { viewport in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if let errorText = detector.errorText { errorBanner(errorText) }
                    greeting
                    tiles
                    weekStrip
                    HourHeatmapView(day: shownDay)
                    TouchZonesCard(counts: shownZones)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .frame(minHeight: viewport.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.always)
        }
        .background(AwairaPalette.window.ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image("logo")
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(Circle())

            Text("Awaira")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AwairaPalette.text)

            Spacer(minLength: 8)

            cameraPill
            settingsButton
        }
    }

    private var cameraPill: some View {
        Button(action: onToggleCamera) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isLive ? AwairaPalette.live : AwairaPalette.ink.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .shadow(color: isLive ? AwairaPalette.live.opacity(0.35) : .clear, radius: 4)
                Text(isLive ? "Camera on" : "Camera off")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AwairaPalette.ink.opacity(0.8))
                    .accessibilityIdentifier("statusLine")
            }
            .awairaPill()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("toggleCamera")
        .accessibilityLabel(isLive ? "Camera on" : "Camera off")
        .animation(.easeInOut(duration: 0.15), value: isLive)
    }

    private var settingsButton: some View {
        Button(action: onOpenSettings) {
            Image(systemName: "gearshape")
                .font(.system(size: 16))
                .foregroundStyle(AwairaPalette.ink.opacity(0.8))
                .frame(width: 36, height: 36)
                .background(AwairaPalette.window, in: Circle())
                .overlay(Circle().strokeBorder(AwairaPalette.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settingsToggle")
        .accessibilityLabel("Settings")
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(AwairaPalette.alert)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(AwairaPalette.alert)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Date and headline numbers

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.dateFormatter.string(from: selectedDay?.date ?? Date()))
                .font(.system(size: 28, design: .serif))
                .foregroundStyle(AwairaPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Awareness today. Progress tomorrow.")
                .font(.system(size: 15))
                .foregroundStyle(AwairaPalette.ink.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tiles: some View {
        HStack(spacing: 12) {
            tile(label: "PER HOUR", value: tracked ? String(format: "%.0f", selectedRate) : "—",
                 suffix: tracked ? "/hr" : nil, tint: AwairaPalette.rate,
                 symbol: "stopwatch", identifier: nil)
            tile(label: "TOTAL APPROACHES", value: "\(selectedDay?.interruptions ?? 0)", suffix: nil,
                 tint: AwairaPalette.accent, symbol: "waveform.path.ecg", identifier: "todayCount")
        }
    }

    private func tile(label: String, value: String, suffix: String?, tint: Color,
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
        .awairaCard(padding: 12)
    }

    // MARK: - Week strip

    private var weekStrip: some View {
        VStack(spacing: 5) {
            HStack {
                Button { moveSelection(by: -7) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(canMoveBack ? AwairaPalette.text : AwairaPalette.ink.opacity(0.24))
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(!canMoveBack)

                Text(weekRangeLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AwairaPalette.ink.opacity(0.68))
                    .frame(maxWidth: .infinity)

                Button { moveSelection(by: 7) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(canMoveForward ? AwairaPalette.text : AwairaPalette.ink.opacity(0.24))
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(!canMoveForward)
            }

            HStack(spacing: 4) {
                ForEach(visibleDays) { day in
                    weekColumn(day)
                }
            }
        }
        .awairaCard(padding: 6)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width > 32 { moveSelection(by: -7) }
                    if value.translation.width < -32 { moveSelection(by: 7) }
                }
        )
        .animation(.easeInOut(duration: 0.18), value: selectedDayID)
    }

    private func weekColumn(_ day: MobileStatsStore.DayBar) -> some View {
        let isSelected = day.id == effectiveDayID
        let dayTracked = day.activeSeconds >= Self.minTrackedSeconds
        let rate = MobileStatsStore.hourlyRate(interruptions: day.interruptions,
                                               activeSeconds: day.activeSeconds)

        return Button {
            selectedDayID = day.id
        } label: {
            VStack(spacing: 1) {
                Text(Self.weekdayFormatter.string(from: day.date).uppercased())
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? AwairaPalette.navSelectedText.opacity(0.85)
                                               : AwairaPalette.ink.opacity(0.6))
                Text("\(Calendar.current.component(.day, from: day.date))")
                    .font(.system(size: 21, design: .serif))
                    .foregroundStyle(isSelected ? AwairaPalette.navSelectedText : AwairaPalette.text)
                    .monospacedDigit()
                Text(String(format: "%.0f/hr", rate))
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? AwairaPalette.navSelectedText.opacity(0.85)
                                               : AwairaPalette.ink.opacity(0.7))
                    .monospacedDigit()
                    .opacity(dayTracked ? 1 : 0)
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
        .accessibilityLabel(Text(day.date.formatted(date: .abbreviated, time: .omitted)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Data

    private var effectiveDayID: String? {
        if let selectedDayID, detector.history.contains(where: { $0.id == selectedDayID }) {
            return selectedDayID
        }
        return detector.history.last?.id
    }

    private var selectedDay: MobileStatsStore.DayBar? {
        guard let effectiveDayID else { return nil }
        return detector.history.first(where: { $0.id == effectiveDayID })
    }

    /// The seven-day strip is a movable calendar window. Selecting any day updates the detail
    /// cards below; swiping or using the chevrons moves the whole window through saved history.
    private var visibleDays: [MobileStatsStore.DayBar] {
        guard let effectiveDayID,
              let selectedIndex = detector.history.firstIndex(where: { $0.id == effectiveDayID }) else {
            return detector.week
        }
        let start = max(0, selectedIndex - 6)
        let end = min(detector.history.count, start + 7)
        return Array(detector.history[start..<end])
    }

    private var weekRangeLabel: String {
        guard let first = visibleDays.first, let last = visibleDays.last else { return "" }
        return "\(Self.shortDateFormatter.string(from: first.date)) – \(Self.shortDateFormatter.string(from: last.date))"
    }

    private var canMoveBack: Bool {
        guard let first = visibleDays.first,
              let index = detector.history.firstIndex(where: { $0.id == first.id }) else { return false }
        return index > 0
    }

    private var canMoveForward: Bool {
        guard let last = visibleDays.last,
              let index = detector.history.firstIndex(where: { $0.id == last.id }) else { return false }
        return index < detector.history.count - 1
    }

    private func moveSelection(by offset: Int) {
        guard let effectiveDayID,
              let currentIndex = detector.history.firstIndex(where: { $0.id == effectiveDayID }),
              !detector.history.isEmpty else { return }
        let nextIndex = min(max(0, currentIndex + offset), detector.history.count - 1)
        guard nextIndex != currentIndex else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedDayID = detector.history[nextIndex].id
        }
    }

    private var shownDay: [MobileStatsStore.DayBar] {
        guard let effectiveDayID, let hours = detector.hoursByDay[effectiveDayID] else {
            return detector.chartDay
        }
        return hours
    }

    private var tracked: Bool { (selectedDay?.activeSeconds ?? 0) >= Self.minTrackedSeconds }

    private var selectedRate: Double {
        MobileStatsStore.hourlyRate(interruptions: selectedDay?.interruptions ?? 0,
                                    activeSeconds: selectedDay?.activeSeconds ?? 0)
    }

    private var shownZones: [String: Int] {
        guard let effectiveDayID else { return detector.zoneCounts }
        return detector.zonesByDay[effectiveDayID] ?? [:]
    }

    private var isLive: Bool { cameraRequested && !detector.paused && detector.errorText == nil }

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

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()
}
