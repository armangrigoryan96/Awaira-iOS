import Foundation

/// The shared reading of a day's 24 hour-bars: which stretch of them to draw, and where the busy
/// part of it is.
///
/// Both hour views on the phone — the bar chart on Today and the heatmap on the detail screen —
/// have to crop and peak-detect identically, or the same day would appear to have two different
/// busy windows depending on which card you were looking at.
enum DayHourWindow {
    /// A fixed waking window, as in the design: showing only the hours that have activity would
    /// stretch a handful of cells into long bars. The window only ever widens — for an early riser,
    /// or past midnight.
    static let from = 6, to = 22

    /// The day cropped to the display window. Hours the day has not reached yet still get a slot, so
    /// the row keeps its shape from morning on rather than growing through the day.
    static func hours(in day: [MobileStatsStore.DayBar]) -> [MobileStatsStore.DayBar] {
        let calendar = Calendar.current
        let active = { (bar: MobileStatsStore.DayBar) in bar.interruptions > 0 || bar.pulls > 0 }
        let firstActive = day.first(where: active)
        let from = min(Self.from, firstActive.map { calendar.component(.hour, from: $0.date) } ?? Self.from)
        let lastActive = day.last(where: active)
        let to = max(Self.to, lastActive.map { calendar.component(.hour, from: $0.date) } ?? Self.to)
        guard from <= to else { return [] }
        return day.filter { bar in
            let hour = calendar.component(.hour, from: bar.date)
            return hour >= from && hour <= to
        }
    }

    /// The busiest hour plus the run of hours around it that are nearly as bad — the peak *window*,
    /// not the peak hour: one cell under a label saying "window" was the wrong promise.
    ///
    /// Indices are into the cropped array `hours(in:)` returns, not into the 24-hour day.
    static func peak(in hours: [MobileStatsStore.DayBar], max maxCount: Int) -> ClosedRange<Int>? {
        guard maxCount > 0,
              let peak = hours.firstIndex(where: { $0.interruptions == maxCount }) else { return nil }
        let floor = Double(maxCount) * 0.8
        var first = peak, last = peak
        while first > 0, Double(hours[first - 1].interruptions) >= floor { first -= 1 }
        while last < hours.count - 1, Double(hours[last + 1].interruptions) >= floor { last += 1 }
        return first...last
    }
}
