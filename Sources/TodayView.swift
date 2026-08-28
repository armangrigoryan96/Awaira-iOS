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
                    TouchZonesCard(counts: detector.zoneCounts)
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
            Text(Self.dateFormatter.string(from: Date()))
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
            tile(label: "PER HOUR", value: tracked ? String(format: "%.0f", todayRate) : "—",
                 suffix: tracked ? "/hr" : nil, tint: AwairaPalette.rate,
                 symbol: "stopwatch", identifier: nil)
            tile(label: "TOTAL APPROACHES", value: "\(detector.count)", suffix: nil,
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
        HStack(spacing: 4) {
            ForEach(detector.week) { day in
                weekColumn(day)
            }
        }
        .awairaCard(padding: 6)
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

    private var tracked: Bool { detector.activeSecondsToday >= Self.minTrackedSeconds }

    private var todayRate: Double {
        MobileStatsStore.hourlyRate(interruptions: detector.count,
                                    activeSeconds: detector.activeSecondsToday)
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
}
