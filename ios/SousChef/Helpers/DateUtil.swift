import Foundation

// DateUtil — date helpers used by screens that show a meal-plan week.
//
// Depends on:     Foundation.
// Depended on by: PlanScreen, HomeScreen (and later, anywhere that
//                 displays day-of-week or week ranges).
// Why it exists:  one place for the date math, kept in UTC so it lines
//                 up with the backend's `getWeekStartDate()` (which also
//                 works in UTC). Mixing local and UTC date math is the
//                 fastest way to display Sunday's plan as Monday's.
enum DateUtil {
    /// The date for a `dayOfWeek` (0=Sun…6=Sat) inside the week starting
    /// at `weekStart` (a `YYYY-MM-DD` Monday). UTC.
    static func date(for dayOfWeek: Int, weekStart: String) -> Date? {
        guard let monday = parseUTCDate(weekStart) else { return nil }
        let offset = dayOfWeek == 0 ? 6 : dayOfWeek - 1
        return utcCalendar.date(byAdding: .day, value: offset, to: monday)
    }

    /// "Sunday" … "Saturday" for `dayOfWeek` 0…6.
    static func dayName(_ dayOfWeek: Int) -> String {
        [
            "Sunday", "Monday", "Tuesday", "Wednesday",
            "Thursday", "Friday", "Saturday",
        ][max(0, min(6, dayOfWeek))]
    }

    /// The day-of-month for a `dayOfWeek` inside `weekStart`, formatted as
    /// "25". Empty string if `weekStart` doesn't parse.
    static func dayNumber(for dayOfWeek: Int, weekStart: String) -> String {
        guard let d = date(for: dayOfWeek, weekStart: weekStart) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "d"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: d)
    }

    /// "May 25 – 31" (or "Apr 27 – May 3" when the week spans months).
    /// Appends " · This week" when `weekStart` is the current week's Monday.
    static func weekRangeString(weekStart: String) -> String {
        guard let monday = parseUTCDate(weekStart),
              let sunday = utcCalendar.date(byAdding: .day, value: 6, to: monday) else {
            return weekStart
        }
        let mf = DateFormatter()
        mf.dateFormat = "MMM d"
        mf.timeZone = TimeZone(identifier: "UTC")

        let sameMonth = utcCalendar.component(.month, from: monday)
            == utcCalendar.component(.month, from: sunday)
        let endText: String
        if sameMonth {
            let df = DateFormatter()
            df.dateFormat = "d"
            df.timeZone = TimeZone(identifier: "UTC")
            endText = df.string(from: sunday)
        } else {
            endText = mf.string(from: sunday)
        }
        let suffix = (weekStart == todaysMondayString()) ? " · This week" : ""
        return "\(mf.string(from: monday)) – \(endText)\(suffix)"
    }

    /// Today's week's Monday formatted as `YYYY-MM-DD`, in UTC. Matches the
    /// backend's `getWeekStartDate()` so string comparison works.
    static func todaysMondayString() -> String {
        let now = Date()
        let weekday = utcCalendar.component(.weekday, from: now)   // 1=Sun…7=Sat
        let offset = weekday == 1 ? -6 : (2 - weekday)
        let monday = utcCalendar.date(byAdding: .day,
                                      value: offset,
                                      to: utcCalendar.startOfDay(for: now)) ?? now
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: monday)
    }

    /// Parse a `YYYY-MM-DD` date as UTC midnight. Public for callers that
    /// need to do their own arithmetic (e.g. the calendar grid).
    static func dateFromISO(_ s: String) -> Date? { parseUTCDate(s) }

    /// Shift a `YYYY-MM-DD` Monday by `weeks` (negative goes back). Returns
    /// a fresh `YYYY-MM-DD` string in UTC. The Plan view's prev/next
    /// arrows live on this helper.
    static func shiftMonday(_ monday: String, weeks: Int) -> String {
        guard let d = parseUTCDate(monday),
              let next = utcCalendar.date(byAdding: .day, value: weeks * 7, to: d) else {
            return monday
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: next)
    }

    /// The UTC Gregorian calendar — match the backend's day math.
    static var utc: Calendar { utcCalendar }

    // MARK: Internal

    private static var utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static func parseUTCDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)
    }
}
