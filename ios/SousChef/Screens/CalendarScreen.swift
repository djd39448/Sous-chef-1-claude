import SwiftUI

/// The Calendar screen — month view of which days have plans or lists.
/// Pushed from the Plan tab.
///
/// Wired to `GET /api/kitchen/calendar`. The user can flip between
/// the displayed month with chevL / chevR; the grid marks days that
/// fall inside any plan's Mon-Sun week (terra dot) or any list's week
/// (sage dot). Today is highlighted.
struct CalendarScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthModel.self) private var auth

    @State private var mode: Mode = .plans
    @State private var displayedMonth: Date = Self.firstOfMonth(Date())
    @State private var loadState: LoadState = .loading

    private enum Mode: String, CaseIterable {
        case plans, lists
    }

    private enum LoadState {
        case loading
        case loaded(CalendarResponse)
        case failed(String)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                NavBar(
                    largeTitle: monthTitle,
                    leading: AnyView(IconButton(icon: "chevL") { dismiss() })
                    // Trailing chevR removed (B-20) — it duplicated nothing
                    // and went nowhere. Month navigation is the chev row
                    // below the NavBar.
                )
                monthNav
                segmented
                weekdayHeader
                grid
                dayDetail
            }
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Loading

    private func load() async {
        loadState = .loading
        let client = APIClient(baseURL: AppConfig.backendBaseURL, auth: auth)
        do {
            let resp: CalendarResponse = try await client.get("/api/kitchen/calendar")
            loadState = .loaded(resp)
        } catch let e as APIError where e.isBenignCancellation {
            return
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private var data: CalendarResponse? {
        if case .loaded(let r) = loadState { return r } else { return nil }
    }

    // MARK: Header / nav

    private var monthTitle: String {
        // displayedMonth is built with DateUtil.utc, so we must format it in
        // the same zone — otherwise EDT pushes May 1 00:00 UTC back to April
        // 30 20:00 local and the title reads one month behind the grid.
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.timeZone = DateUtil.utc.timeZone
        return f.string(from: displayedMonth)
    }

    private var monthNav: some View {
        HStack(spacing: 16) {
            Button { shiftMonth(-1) } label: {
                SCIcon("chevL", size: 18, color: Theme.ink)
                    .frame(width: 36, height: 36)
                    .background(Theme.card)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.hairline2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
            Button { displayedMonth = Self.firstOfMonth(Date()) } label: {
                Text("Today")
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.terra)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { shiftMonth(+1) } label: {
                SCIcon("chevR", size: 18, color: Theme.ink)
                    .frame(width: 36, height: 36)
                    .background(Theme.card)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.hairline2, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func shiftMonth(_ delta: Int) {
        if let next = DateUtil.utc.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = Self.firstOfMonth(next)
        }
    }

    // MARK: Segmented

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(Mode.allCases, id: \.self) { m in
                let on = mode == m
                Button { mode = m } label: {
                    Text(m == .plans ? "Meal Plans" : "Shopping Lists")
                        .font(Theme.sans(13, weight: .semibold))
                        .foregroundStyle(on ? Theme.ink : Theme.ink2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(on ? Theme.card : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 1, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(height: 32)
        .background(Theme.elev)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: Weekday header

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns) {
            ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, d in
                Text(d)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.ink3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    // MARK: Grid

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(gridCells, id: \.id) { cell in
                cellView(cell)
            }
        }
        .padding(.horizontal, 16)
    }

    private struct DayCell {
        let id: Int
        let date: Date
        let dayNumber: Int
        let inMonth: Bool
        let isToday: Bool
    }

    private var gridCells: [DayCell] {
        var out: [DayCell] = []
        let cal = DateUtil.utc
        let firstDayOfMonth = displayedMonth
        let weekdayOfFirst = cal.component(.weekday, from: firstDayOfMonth)   // 1=Sun
        let leading = weekdayOfFirst - 1
        let startDate = cal.date(byAdding: .day, value: -leading, to: firstDayOfMonth)!
        let displayedMonthValue = cal.component(.month, from: displayedMonth)
        let todayMonthDay = cal.dateComponents([.year, .month, .day], from: Date())

        for i in 0..<42 {
            let d = cal.date(byAdding: .day, value: i, to: startDate)!
            let parts = cal.dateComponents([.year, .month, .day], from: d)
            let inMonth = parts.month == displayedMonthValue
            let isToday = parts.year == todayMonthDay.year
                && parts.month == todayMonthDay.month
                && parts.day == todayMonthDay.day
            out.append(DayCell(
                id: i,
                date: d,
                dayNumber: parts.day ?? 0,
                inMonth: inMonth,
                isToday: isToday
            ))
        }
        return out
    }

    private func cellView(_ cell: DayCell) -> some View {
        let lit = isLit(date: cell.date)
        let bg: Color = cell.isToday
            ? Theme.terra
            : (lit && cell.inMonth ? Theme.card : .clear)
        let fg: Color = cell.isToday
            ? .white
            : (cell.inMonth ? Theme.ink : Theme.ink4)
        return VStack {
            Text("\(cell.dayNumber)")
                .font(.system(size: 14, weight: cell.isToday ? .semibold : .medium))
                .foregroundStyle(fg)
            Spacer(minLength: 0)
            dotIndicator(for: cell)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .aspectRatio(1.0 / 1.15, contentMode: .fit)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.hairline2,
                              lineWidth: (lit && cell.inMonth && !cell.isToday) ? 1 : 0)
        )
    }

    @ViewBuilder
    private func dotIndicator(for cell: DayCell) -> some View {
        let lit = isLit(date: cell.date)
        if lit && cell.inMonth {
            Circle()
                .fill(cell.isToday ? Color.white : (mode == .plans ? Theme.terra : Theme.sage))
                .frame(width: 5, height: 5)
        } else {
            Color.clear.frame(width: 5, height: 5)
        }
    }

    private func isLit(date: Date) -> Bool {
        guard let data = data else { return false }
        let weeks: [String] = mode == .plans
            ? data.mealPlans.map(\.weekStartDate)
            : data.shoppingLists.compactMap(\.weekStartDate)
        return weeks.contains { weekStart in
            guard let monday = DateUtil.dateFromISO(weekStart),
                  let sunday = DateUtil.utc.date(byAdding: .day, value: 6, to: monday) else {
                return false
            }
            // Compare just the date parts (UTC midnight on both sides).
            return date >= monday && date <= sunday
        }
    }

    // MARK: Day detail (basic — defers per-day fetch to a future iteration)

    private var dayDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(todayLabel.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.ink3)
                .padding(.horizontal, 6)

            HStack(spacing: 12) {
                detailIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(detailTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(detailSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink2)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .cardSurface(20)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    private var detailIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Theme.elev)
            SCIcon(mode == .plans ? "calendar" : "cart", size: 18, color: Theme.terra)
        }
        .frame(width: 52, height: 52)
    }

    private var todayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return "\(f.string(from: Date())) · Today"
    }

    private var detailTitle: String {
        switch loadState {
        case .loading: return "Loading…"
        case .failed: return "Couldn't load your calendar"
        case .loaded(let r):
            switch mode {
            case .plans:
                return r.mealPlans.isEmpty ? "No plans yet" : "\(r.mealPlans.count) week\(r.mealPlans.count == 1 ? "" : "s") with plans"
            case .lists:
                let withWeek = r.shoppingLists.filter { $0.weekStartDate != nil }.count
                return withWeek == 0 ? "No shopping lists yet" : "\(withWeek) week\(withWeek == 1 ? "" : "s") with lists"
            }
        }
    }

    private var detailSubtitle: String {
        // Copy doesn't claim "tap a marked day…" anymore (B-19) — the cells
        // aren't tappable yet, and we'd rather not promise UI we haven't
        // shipped. Restore that copy when the per-day sheet lands.
        if case .failed(let msg) = loadState { return msg }
        return mode == .plans
            ? "Marked days have a meal plan for that week."
            : "Marked days have a shopping list for that week."
    }

    // MARK: Utility

    private static func firstOfMonth(_ date: Date) -> Date {
        let parts = DateUtil.utc.dateComponents([.year, .month], from: date)
        return DateUtil.utc.date(from: parts) ?? date
    }
}
