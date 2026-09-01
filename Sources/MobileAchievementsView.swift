import SwiftUI

/// The phone carries the same private, progress-focused achievement set as the desktop app. The
/// rules are evaluated from aggregate on-device history only; camera frames never leave the phone
/// and are never retained for a badge.
struct MobileAchievementsView: View {
    @ObservedObject var detector: Detector
    let onOpenSettings: () -> Void
    @State private var selectedBadge: MobileAchievement?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        MobilePage(title: "Badges",
                   subtitle: "A private record of awareness and progress — never a leaderboard.",
                   accessory: AnyView(brandRow)) {
            ForEach(MobileAchievementDifficulty.allCases) { difficulty in
                collection(for: difficulty)
            }
        }
        .sheet(item: $selectedBadge) { badge in
            MobileBadgeDetail(badge: badge,
                              unlocked: detector.unlockedAchievementIDs.contains(badge.id))
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

    private var momentum: Int {
        let weekly = max(0, min(50, Int((detector.weeklyImprovement ?? 0).rounded())))
        let practice = min(25, MobileAchievementEvaluator.currentPracticeStreak(in: detector.history) * 5)
        let redirects = min(25, detector.preventedPulls)
        return weekly + practice + redirects
    }

    private var momentumCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(AwairaPalette.cardBorder, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: Double(momentum) / 100)
                    .stroke(AwairaPalette.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(momentum)")
                    .awairaFigure(28)
                    .foregroundStyle(AwairaPalette.text)
            }
            .frame(width: 66, height: 66)

            VStack(alignment: .leading, spacing: 3) {
                Text("This week’s local activity")
                    .scaledFont(16, weight: .semibold)
                    .foregroundStyle(AwairaPalette.text)
                Text("Your local activity, continued use, and movements that ended before the stronger cue all appear here.")
                    .awairaCaption(13)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .awairaCard(padding: 14)
    }

    private func collection(for difficulty: MobileAchievementDifficulty) -> some View {
        let badges = MobileAchievement.all.filter { $0.difficulty == difficulty }
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(difficulty.title)
                    .scaledFont(19, weight: .bold)
                    .foregroundStyle(AwairaPalette.text)
                Text(difficulty.subtitle)
                    .awairaCaption(13)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.58))
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(badges) { badge in
                    MobileAchievementTile(badge: badge,
                                          unlocked: detector.unlockedAchievementIDs.contains(badge.id)) {
                        selectedBadge = badge
                    }
                }
            }
        }
        .padding(.top, 6)
    }
}

private struct MobileAchievementTile: View {
    let badge: MobileAchievement
    let unlocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                MobileRosetteBadge(glyph: badge.glyph, color: badge.difficulty.color, unlocked: unlocked,
                                   size: 42, lockedBlur: 2.1)
                    .frame(width: 42, height: 49, alignment: .top)
                Text(badge.title)
                    .scaledFont(10, weight: .semibold)
                    .foregroundStyle(AwairaPalette.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 25)
                Label(unlocked ? "EARNED" : "LOCKED", systemImage: unlocked ? "checkmark" : "lock.fill")
                    .scaledFont(8, weight: .bold)
                    .foregroundStyle(badge.difficulty.color.opacity(unlocked ? 1 : 0.58))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.18))
                    .overlay(Rectangle().strokeBorder(badge.difficulty.color.opacity(unlocked ? 0.72 : 0.30), lineWidth: 1))
            }
            .padding(7)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(
                Circle().fill(
                    RadialGradient(colors: [Color.white.opacity(unlocked ? 0.055 : 0.025),
                                            AwairaPalette.statsSurface, Color.black.opacity(0.22)],
                                   center: .top, startRadius: 3, endRadius: 90)
                )
            )
            .overlay(Circle().strokeBorder(badge.difficulty.color.opacity(unlocked ? 0.76 : 0.32), lineWidth: 1.25))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open to see exactly how to earn this badge")
    }
}

private struct MobileBadgeDetail: View {
    let badge: MobileAchievement
    let unlocked: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                MobileRosetteBadge(glyph: badge.glyph, color: badge.difficulty.color, unlocked: unlocked,
                                   size: 72)
                    .frame(width: 72, height: 94, alignment: .top)
                VStack(alignment: .leading, spacing: 3) {
                    Text(badge.title)
                        .awairaDisplay(25)
                        .foregroundStyle(AwairaPalette.text)
                    Text(unlocked ? "EARNED" : "LOCKED")
                        .awairaCaption(12)
                        .foregroundStyle(badge.difficulty.color)
                }
            }
            Divider().overlay(AwairaPalette.cardBorder)
            VStack(alignment: .leading, spacing: 8) {
                Label("REQUIREMENT", systemImage: "checkmark.seal")
                    .awairaCaption(11)
                    .foregroundStyle(badge.difficulty.color)
                Text(badge.requirement)
                    .scaledFont(16)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.80))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AwairaPalette.window, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(badge.difficulty.color.opacity(0.24), lineWidth: 1))
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(AwairaPrimaryButton())
        }
        .padding(20)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .presentationBackground(AwairaPalette.statsSurface)
    }
}

private struct MobileRosetteBadge: View {
    let glyph: String
    let color: Color
    let unlocked: Bool
    let size: CGFloat
    var lockedBlur: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: -5) {
                MobileRibbonTail(flipped: false).fill(color.opacity(unlocked ? 0.72 : 0.18))
                MobileRibbonTail(flipped: true).fill(color.opacity(unlocked ? 0.56 : 0.14))
            }
            .frame(width: size * 0.76, height: size * 0.52)
            .offset(y: size * 0.48)
            MobileRosetteSeal(points: 18)
                .fill(color.opacity(unlocked ? 0.95 : 0.22))
            MobileRosetteSeal(points: 18)
                .strokeBorder(AwairaPalette.ink.opacity(unlocked ? 0.20 : 0.10), lineWidth: 1)
                .padding(size * 0.045)
            Circle().fill(AwairaPalette.statsSurface).padding(size * 0.17)
            Circle().strokeBorder(color.opacity(unlocked ? 0.85 : 0.30), lineWidth: 2).padding(size * 0.20)
            MobileBadgeIconView(path: glyph, size: size * 0.42, lineWidth: max(1.4, size / 38),
                                color: color.opacity(unlocked ? 1 : 0.46))
        }
        .frame(width: size, height: size * 1.30, alignment: .top)
        .blur(radius: unlocked ? 0 : lockedBlur)
    }
}

private struct MobileRosetteSeal: InsettableShape {
    let points: Int
    private var insetAmount: CGFloat = 0

    init(points: Int) { self.points = points }

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let center = CGPoint(x: box.midX, y: box.midY)
        let outer = min(box.width, box.height) / 2
        let inner = outer * 0.84
        var path = Path()
        for index in 0..<(points * 2) {
            let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / CGFloat(points)
            let radius = index.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> MobileRosetteSeal {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct MobileRibbonTail: Shape {
    let flipped: Bool

    func path(in rect: CGRect) -> Path {
        let left = flipped ? rect.maxX : rect.minX
        let right = flipped ? rect.minX : rect.maxX
        var path = Path()
        path.move(to: CGPoint(x: left, y: 0))
        path.addLine(to: CGPoint(x: right, y: 0))
        path.addLine(to: CGPoint(x: right, y: rect.height * 0.80))
        path.addLine(to: CGPoint(x: (left + right) / 2, y: rect.height * 0.60))
        path.addLine(to: CGPoint(x: left, y: rect.height))
        path.closeSubpath()
        return path
    }
}

private enum MobileAchievementDifficulty: String, CaseIterable, Identifiable {
    case easy, medium, hard
    var id: String { rawValue }
    var title: String { rawValue == "easy" ? "Easy" : (rawValue == "medium" ? "Medium" : "Hard") }
    var subtitle: String {
        switch self {
        case .easy: return "Bronze · awareness and a first routine."
        case .medium: return "Silver · steady effort and measurable change."
        case .hard: return "Gold · long runs and ambitious progress."
        }
    }
    var color: Color {
        switch self {
        case .easy: return Color(hex: 0xB87333)
        case .medium: return Color(hex: 0xAEB7C2)
        case .hard: return Color(hex: 0xD9A72E)
        }
    }
}

private struct MobileAchievement: Identifiable {
    let id: String
    let title: String
    let requirement: String
    let glyph: String
    let difficulty: MobileAchievementDifficulty

    static let all: [MobileAchievement] = [
        .init(id: "first_awareness", title: "First touch noticed", requirement: "With monitoring on, let Awaira notice your hand reaching your face for the first time.", glyph: MobileBadgeIcon.eye, difficulty: .easy),
        .init(id: "five_redirects", title: "5 early hand endings", requirement: "Have 5 hand movements end before Awaira’s stronger cue starts in one day.", glyph: MobileBadgeIcon.uTurn, difficulty: .easy),
        .init(id: "steady_practice", title: "Tracked 3 days in a row", requirement: "Track for at least 5 minutes a day, 3 days in a row.", glyph: MobileBadgeIcon.calendarCheck, difficulty: .easy),
        .init(id: "gentle_goal", title: "Met your daily goal", requirement: "Track for at least 1 hour today and finish the day at or below the hourly goal you set.", glyph: MobileBadgeIcon.target, difficulty: .easy),
        .init(id: "week_ahead", title: "5% better than last week", requirement: "Average at least 5% fewer touches per tracked hour over the last 7 days than in the 7 days before.", glyph: MobileBadgeIcon.trendUp, difficulty: .easy),
        .init(id: "ten_redirects", title: "10 early hand endings", requirement: "Have 10 hand movements end before Awaira’s stronger cue starts in one day.", glyph: MobileBadgeIcon.cycle, difficulty: .easy),
        .init(id: "seven_day_routine", title: "Tracked 7 days in a row", requirement: "Track for at least 5 minutes a day, 7 days in a row.", glyph: MobileBadgeIcon.weekDial, difficulty: .easy),
        .init(id: "full_tracking_week", title: "An hour a day for a week", requirement: "Track for at least 1 hour a day, 7 days in a row.", glyph: MobileBadgeIcon.checkCircle, difficulty: .easy),
        .init(id: "seven_days_under_50", title: "A week under 50/hr", requirement: "Track for at least 1 hour a day, 7 days in a row, and stay under 50 touches per tracked hour every one of those days.", glyph: MobileBadgeIcon.sprout, difficulty: .easy),
        .init(id: "seven_days_under_40", title: "A week under 40/hr", requirement: "Track for at least 1 hour a day, 7 days in a row, and stay under 40 touches per tracked hour every one of those days.", glyph: MobileBadgeIcon.leaf, difficulty: .easy),
        .init(id: "twenty_five_redirects", title: "25 early hand endings", requirement: "Have 25 hand movements end before Awaira’s stronger cue starts in one day.", glyph: MobileBadgeIcon.compass, difficulty: .medium),
        .init(id: "fourteen_day_routine", title: "Tracked 14 days in a row", requirement: "Track for at least 5 minutes a day, 14 days in a row.", glyph: MobileBadgeIcon.calendarTwoWeeks, difficulty: .medium),
        .init(id: "week_15_ahead", title: "15% better than last week", requirement: "Average at least 15% fewer touches per tracked hour over the last 7 days than in the 7 days before.", glyph: MobileBadgeIcon.bars, difficulty: .medium),
        .init(id: "quicker_release", title: "Let go 10% faster", requirement: "Make your average time from touch to letting go at least 10% shorter than it was in the 7 days before.", glyph: MobileBadgeIcon.bolt, difficulty: .medium),
        .init(id: "seven_days_under_30", title: "A week under 30/hr", requirement: "Track for at least 1 hour a day, 7 days in a row, and stay under 30 touches per tracked hour every one of those days.", glyph: MobileBadgeIcon.hill, difficulty: .medium),
        .init(id: "seven_days_under_20", title: "A week under 20/hr", requirement: "Track for at least 1 hour a day, 7 days in a row, and stay under 20 touches per tracked hour every one of those days.", glyph: MobileBadgeIcon.droplet, difficulty: .medium),
        .init(id: "seven_days_under_15", title: "A week under 15/hr", requirement: "Track for at least 1 hour a day, 7 days in a row, and stay under 15 touches per tracked hour every one of those days.", glyph: MobileBadgeIcon.bubbles, difficulty: .medium),
        .init(id: "fourteen_days_under_30", title: "2 weeks under 30/hr", requirement: "Track for at least 1 hour a day, 14 days in a row, and stay under 30 touches per tracked hour every one of those days.", glyph: MobileBadgeIcon.branch, difficulty: .medium),
        .init(id: "fourteen_days_under_20", title: "2 weeks under 20/hr", requirement: "Track for at least 1 hour a day, 14 days in a row, and stay under 20 touches per tracked hour every one of those days.", glyph: MobileBadgeIcon.gem, difficulty: .medium),
        .init(id: "thirty_day_routine", title: "Tracked 30 days in a row", requirement: "Track for at least 5 minutes a day, 30 days in a row.", glyph: MobileBadgeIcon.crescent, difficulty: .hard),
        .init(id: "week_30_ahead", title: "30% better than last week", requirement: "Average at least 30% fewer touches per tracked hour over the last 7 days than in the 7 days before.", glyph: MobileBadgeIcon.rocket, difficulty: .hard),
        .init(id: "week_50_ahead", title: "50% better than last week", requirement: "Average at least 50% fewer touches per tracked hour over the last 7 days than in the 7 days before.", glyph: MobileBadgeIcon.sun, difficulty: .hard),
        .init(id: "seven_days_under_10", title: "A week under 10/hr", requirement: "Track for at least 1 hour a day, 7 days in a row, and stay under 10 touches per tracked hour every one of those days.", glyph: MobileBadgeIcon.spark, difficulty: .hard),
        .init(id: "seven_days_under_5", title: "A week under 5/hr", requirement: "Track for at least 1 hour a day, 7 days in a row, and stay under 5 touches per tracked hour every one of those days.", glyph: MobileBadgeIcon.cup, difficulty: .hard),
        .init(id: "fourteen_days_under_10", title: "2 weeks under 10/hr", requirement: "Track for at least 1 hour a day, 14 days in a row, and stay under 10 touches per tracked hour every one of those days.", glyph: MobileBadgeIcon.crystal, difficulty: .hard),
        .init(id: "fourteen_days_under_5", title: "2 weeks under 5/hr", requirement: "Track for at least 1 hour a day, 14 days in a row, and stay under 5 touches per tracked hour every one of those days.", glyph: MobileBadgeIcon.crown, difficulty: .hard),
        .init(id: "thirty_days_under_30", title: "A month under 30/hr", requirement: "Track for at least 1 hour a day, 30 days in a row, and stay under 30 touches per tracked hour every one of those days.", glyph: MobileBadgeIcon.fir, difficulty: .hard),
        .init(id: "thirty_days_under_20", title: "A month under 20/hr", requirement: "Track for at least 1 hour a day, 30 days in a row, and stay under 20 touches per tracked hour every one of those days.", glyph: MobileBadgeIcon.lotus, difficulty: .hard),
        .init(id: "thirty_days_under_10", title: "A month under 10/hr", requirement: "Track for at least 1 hour a day, 30 days in a row, and stay under 10 touches per tracked hour every one of those days.", glyph: MobileBadgeIcon.comet, difficulty: .hard),
        .init(id: "thirty_days_under_5", title: "A month under 5/hr", requirement: "Track for at least 1 hour a day, 30 days in a row, and stay under 5 touches per tracked hour every one of those days.", glyph: MobileBadgeIcon.medal, difficulty: .hard)
    ]
}

enum MobileAchievementEvaluator {
    static func currentPracticeStreak(in history: [MobileStatsStore.DayBar]) -> Int {
        history.reversed().prefix { $0.activeSeconds >= 5 * 60 }.count
    }

    static func eligible(in history: [MobileStatsStore.DayBar], weeklyImprovement: Double?) -> Set<String> {
        guard let today = history.last else { return [] }
        var ids: Set<String> = []
        if history.contains(where: { $0.interruptions > 0 }) { ids.insert("first_awareness") }
        if today.prevented >= 5 { ids.insert("five_redirects") }
        if today.prevented >= 10 { ids.insert("ten_redirects") }
        if today.prevented >= 25 { ids.insert("twenty_five_redirects") }
        if practiceStreak(history, days: 3) { ids.insert("steady_practice") }
        if practiceStreak(history, days: 7) { ids.insert("seven_day_routine") }
        if practiceStreak(history, days: 14) { ids.insert("fourteen_day_routine") }
        if practiceStreak(history, days: 30) { ids.insert("thirty_day_routine") }
        if trackingStreak(history, days: 7) { ids.insert("full_tracking_week") }
        if today.activeSeconds >= 3600 && MobileStatsStore.hourlyRate(interruptions: today.interruptions, activeSeconds: today.activeSeconds) <= 20 {
            ids.insert("gentle_goal")
        }
        if let weeklyImprovement {
            if weeklyImprovement >= 5 { ids.insert("week_ahead") }
            if weeklyImprovement >= 15 { ids.insert("week_15_ahead") }
            if weeklyImprovement >= 30 { ids.insert("week_30_ahead") }
            if weeklyImprovement >= 50 { ids.insert("week_50_ahead") }
        }
        if quickerRelease(history) { ids.insert("quicker_release") }
        for threshold in [50, 40, 30, 20, 15, 10, 5] where rateStreak(history, days: 7, under: Double(threshold)) {
            ids.insert("seven_days_under_\(threshold)")
        }
        for threshold in [30, 20, 10, 5] where rateStreak(history, days: 14, under: Double(threshold)) {
            ids.insert("fourteen_days_under_\(threshold)")
        }
        for threshold in [30, 20, 10, 5] where rateStreak(history, days: 30, under: Double(threshold)) {
            ids.insert("thirty_days_under_\(threshold)")
        }
        return ids
    }

    private static func practiceStreak(_ history: [MobileStatsStore.DayBar], days: Int) -> Bool {
        history.suffix(days).count == days && history.suffix(days).allSatisfy { $0.activeSeconds >= 5 * 60 }
    }

    private static func trackingStreak(_ history: [MobileStatsStore.DayBar], days: Int) -> Bool {
        history.suffix(days).count == days && history.suffix(days).allSatisfy { $0.activeSeconds >= 3600 }
    }

    private static func rateStreak(_ history: [MobileStatsStore.DayBar], days: Int, under threshold: Double) -> Bool {
        history.suffix(days).count == days && history.suffix(days).allSatisfy {
            $0.activeSeconds >= 3600 && MobileStatsStore.hourlyRate(interruptions: $0.interruptions, activeSeconds: $0.activeSeconds) < threshold
        }
    }

    private static func quickerRelease(_ history: [MobileStatsStore.DayBar]) -> Bool {
        let recent = Array(history.suffix(7))
        let prior = Array(history.dropLast(7).suffix(7))
        func average(_ days: [MobileStatsStore.DayBar]) -> Double? {
            let touches = days.reduce(0) { $0 + $1.prevented + $1.pulls }
            let seconds = days.reduce(0.0) { $0 + $1.totalTouchSeconds }
            return touches >= 5 && seconds > 0 ? seconds / Double(touches) : nil
        }
        guard let current = average(recent), let before = average(prior), before > 0 else { return false }
        return (before - current) / before * 100 >= 10
    }
}
