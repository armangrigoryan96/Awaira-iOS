import SwiftUI

/// The Today screen, built from the same pieces as the Mac dashboard: the day at a glance, the
/// hour-by-hour heatmap and the touch-location head, all on the design's page.
///
/// Deliberately not a scroll view: the design puts the whole day on one screen, and the head is the
/// one flexible element — it takes whatever height the cards above it leave, so the card below the
/// fold never happens.
struct TodayView: View {
    @ObservedObject var detector: Detector
    /// Whether the user has asked for the camera at all — the header pill's off state.
    let cameraRequested: Bool
    let onToggleCamera: () -> Void
    let onOpenSettings: () -> Void
    /// Where a card's chevron leads: the fuller version of that card, which lives under Patterns.
    let onOpenPatterns: () -> Void

    /// Which day the strip has selected; the heatmap follows it. `nil` means today.
    @State private var selectedDayID: String?

    /// The gentle target, seeded at launch and changed in Settings.
    @AppStorage(MobileGoal.storageKey) private var goalRate = MobileGoal.defaultRate

    /// Under a minute of tracking a rate says more about the clock than about the day.
    private static let minTrackedSeconds = TodayGlanceCard.minTrackedSeconds

    var body: some View {
        GeometryReader { viewport in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if let errorText = detector.errorText { errorBanner(errorText) }
                    TodayGlanceCard(count: detector.count,
                                    rate: tracked ? todayRate : nil,
                                    weeklyImprovement: detector.weeklyImprovement,
                                    week: detector.week,
                                    selectedDayID: $selectedDayID,
                                    onOpenDetail: onOpenPatterns)
                    GoalProgressCard(goal: goalRate, current: tracked ? todayRate : nil)
                    // Side by side, as in the design: the head answers "where" and the chart
                    // answers "when", and the day reads as one thing when they sit together.
                    HStack(alignment: .top, spacing: 12) {
                        TouchZonesCard(counts: detector.zoneCounts,
                                       onOpenDetail: onOpenPatterns)
                        HourBarChartView(day: shownDay, onOpenDetail: onOpenPatterns)
                    }
                    WhatWasHappeningCard(prompt: detector.pendingContextPrompt,
                                         counts: detector.contextCounts,
                                         onAnswer: { choice, note in
                                             guard let prompt = detector.pendingContextPrompt else { return }
                                             detector.recordContext(choice, note: note, for: prompt)
                                         },
                                         onOpenDetail: onOpenPatterns)
                    TodayStatusStrip(streakDays: detector.streakDays,
                                     protectedSeconds: detector.activeSecondsToday,
                                     cleanStreakHours: detector.cleanStreakHours)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)
                // The day is sized to fit the screen, so this only ever pins the content to the top
                // of a taller viewport — the scroll view stays for the give of it, and for the day a
                // larger text size or a shorter phone does need it.
                .frame(minHeight: viewport.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.always)
        }
        .background(AwairaPalette.window.ignoresSafeArea())
    }

    // MARK: - Header

    /// The date sits under the wordmark rather than in a headline of its own. It is a label, not a
    /// statement — the page below it is what the screen is about — and the line it used to occupy
    /// is worth more to the cards.
    private var header: some View {
        HStack(spacing: 10) {
            Image("logo")
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text("Awaira")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AwairaPalette.text)
                Text(Self.dateFormatter.string(from: Date()))
                    .font(.system(size: 13))
                    .foregroundStyle(AwairaPalette.ink.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            todayPill
            settingsButton
        }
    }

    /// The camera switch, and the app's only one — there is nowhere else in the design for it. It
    /// reads as a state, not as an instruction: "Camera on" with a lit dot while detection runs,
    /// "Camera off" with a dull one while it does not, and a tap flips it either way. The Mac says
    /// the same thing with the same two pieces, a dot and a word.
    private var todayPill: some View {
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

    // MARK: - Data

    /// The selected day, falling back to today whenever nothing is selected or the selection has
    /// aged out of the seven days the strip shows.
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

    /// Detection is on because the user asked for it and has not switched it back off. Deliberately
    /// the user's intent rather than `detector.connected`: capture also stops for a phone call or a
    /// stashed PiP window, and the switch must not appear to flip itself in those moments.
    private var isLive: Bool { cameraRequested && !detector.paused && detector.errorText == nil }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        return f
    }()
}
