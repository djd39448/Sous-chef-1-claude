import Foundation

// DateUtil — date helpers used by screens that show a meal-plan week.
//
// Depends on:     Foundation.
// Depended on by: PlanScreen, HomeScreen, CalendarScreen (and anywhere
//                 that displays day-of-week or week ranges).
// Why it exists:  one place for the date math, anchored to the user's
//                 local calendar (`Calendar.current`). The original port
//                 ran this in UTC to match the backend's `getWeekStartDate()`,
//                 but that produced three disagreeing "todays" across
//                 screens (Sunday evening EDT = Monday UTC, so PlanScreen
//                 jumped a week ahead while HomeScreen still showed
//                 Sunday). The contract was updated 2026-05-27: week
//                 strings are interpreted in the user's local calendar,
//                 the iOS client always sends them, and the backend's
//                 UTC math is a fallback for server-driven jobs only.
enum DateUtil {
    /// The date for a `dayOfWeek` (0=Sun…6=Sat) inside the week starting
    /// at `weekStart` (a `YYYY-MM-DD` Monday). Interpreted in the user's
    /// local calendar.
    static func date(for dayOfWeek: Int, weekStart: String) -> Date? {
        guard let monday = parseLocalDate(weekStart) else { return nil }
        let offset = dayOfWeek == 0 ? 6 : dayOfWeek - 1
        return cal.date(byAdding: .day, value: offset, to: monday)
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
        f.calendar = cal
        f.timeZone = cal.timeZone
        return f.string(from: d)
    }

    /// "May 25 – 31" (or "Apr 27 – May 3" when the week spans months).
    /// Appends " · This week" when `weekStart` is the current week's Monday.
    static func weekRangeString(weekStart: String) -> String {
        guard let monday = parseLocalDate(weekStart),
              let sunday = cal.date(byAdding: .day, value: 6, to: monday) else {
            return weekStart
        }
        let mf = DateFormatter()
        mf.dateFormat = "MMM d"
        mf.calendar = cal
        mf.timeZone = cal.timeZone

        let sameMonth = cal.component(.month, from: monday)
            == cal.component(.month, from: sunday)
        let endText: String
        if sameMonth {
            let df = DateFormatter()
            df.dateFormat = "d"
            df.calendar = cal
            df.timeZone = cal.timeZone
            endText = df.string(from: sunday)
        } else {
            endText = mf.string(from: sunday)
        }
        let suffix = (weekStart == todaysMondayString()) ? " · This week" : ""
        return "\(mf.string(from: monday)) – \(endText)\(suffix)"
    }

    /// Today's week's Monday formatted as `YYYY-MM-DD`, in the user's
    /// local calendar. Sent to the backend on every write so plan/list
    /// weeks bucket where the user expects.
    static func todaysMondayString() -> String {
        let now = Date()
        let weekday = cal.component(.weekday, from: now)   // 1=Sun…7=Sat
        let offset = weekday == 1 ? -6 : (2 - weekday)
        let monday = cal.date(byAdding: .day,
                              value: offset,
                              to: cal.startOfDay(for: now)) ?? now
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = cal
        f.timeZone = cal.timeZone
        return f.string(from: monday)
    }

    /// Parse a `YYYY-MM-DD` date as local midnight. Public for callers
    /// that need to do their own arithmetic (e.g. the calendar grid).
    static func dateFromISO(_ s: String) -> Date? { parseLocalDate(s) }

    /// Shift a `YYYY-MM-DD` Monday by `weeks` (negative goes back). Returns
    /// a fresh `YYYY-MM-DD` string. The Plan view's prev/next arrows live
    /// on this helper.
    static func shiftMonday(_ monday: String, weeks: Int) -> String {
        guard let d = parseLocalDate(monday),
              let next = cal.date(byAdding: .day, value: weeks * 7, to: d) else {
            return monday
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = cal
        f.timeZone = cal.timeZone
        return f.string(from: next)
    }

    /// The user's local Gregorian calendar — every screen formats and
    /// compares dates through this so "today" is consistent.
    static var cal: Calendar { Calendar.current }

    // MARK: Internal

    private static func parseLocalDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = cal
        f.timeZone = cal.timeZone
        return f.date(from: s)
    }
}
