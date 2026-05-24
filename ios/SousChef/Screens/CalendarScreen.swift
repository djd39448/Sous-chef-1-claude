import SwiftUI

/// The Calendar screen — Week list OR Month grid view of plans + lists.
/// Pushed from the Plan tab.
///
/// `viewMode = .week` (the default, matching the original web app)
/// shows a vertical list of the current week's 7 meal-plan days plus
/// a shopping-list summary card. `viewMode = .month` shows a grid that
/// marks days whose week has a plan (terra dot) or a list (sage dot).
struct CalendarScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthModel.self) private var auth

    @State private var viewMode: ViewMode = .week
    @State private var currentWeek: String = DateUtil.todaysMondayString()
    @State private var mode: Mode = .plans
    @State private var displayedMonth: Date = Self.firstOfMonth(Date())
    @State private var loadState: LoadState = .loading
    /// Loaded by the Week view — meal plan + shopping list for the
    /// currently-shown week. Nil while loading or when the user is in
    /// month mode and hasn't fetched a week yet.
    @State private var weekData: WeekResponse?
    @State private var isWeekLoading = false
    /// Sheet driver for tapping a meal-plan day on the week list.
    @State private var openDay: MealPlanDay?

    enum ViewMode: String, CaseIterable {
        case week, month
    }

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
                    largeTitle: navTitle,
                    leading: AnyView(IconButton(icon: "chevL") { dismiss() }),
                    trailing: AnyView(viewToggle)
                )
                topNav
                if viewMode == .month {
                    segmented
                    weekdayHeader
                    grid
                    dayDetail
                } else {
                    weekViewBody
                }
            }
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
        .task {
            await load()
            await loadWeek()
        }
        .refreshable {
            await load()
            await loadWeek()
        }
        .sheet(item: $openDay) { day in
            RecipeScreen(source: .mealPlanDay(day))
                .environment(auth)
        }
    }

    private var navTitle: String {
        viewMode == .month ? monthTitle : weekTitle
    }

    private var weekTitle: String {
        DateUtil.weekRangeString(weekStart: currentWeek)
    }

    private var viewToggle: some View {
        HStack(spacing: 4) {
            toggleButton(icon: "filter", mode: .week)  // list icon stand-in
            toggleButton(icon: "calendar", mode: .month)
        }
    }

    private func toggleButton(icon: String, mode: ViewMode) -> some View {
        Button { viewMode = mode } label: {
            SCIcon(icon, size: 16, color: viewMode == mode ? .white : Theme.ink2)
                .frame(width: 32, height: 32)
                .background(viewMode == mode ? Theme.terra : Theme.elev)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var topNav: some View {
        HStack(spacing: 16) {
            Button {
                if viewMode == .week {
                    shiftWeek(-1)
                } else {
                    shiftMonth(-1)
                }
            } label: {
                SCIcon("chevL", size: 18, color: Theme.ink)
                    .frame(width: 36, height: 36)
                    .background(Theme.card)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.hairline2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                if viewMode == .week {
                    currentWeek = DateUtil.todaysMondayString()
                    Task { await loadWeek() }
                } else {
                    displayedMonth = Self.firstOfMonth(Date())
                }
            } label: {
                Text(viewMode == .week ? "This week" : "Today")
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.terra)
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                if viewMode == .week {
                    shiftWeek(+1)
                } else {
                    shiftMonth(+1)
                }
            } label: {
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

    private func shiftWeek(_ delta: Int) {
        currentWeek = DateUtil.shiftMonday(currentWeek, weeks: delta)
        Task { await loadWeek() }
    }

    // MARK: Week view

    @ViewBuilder
    private var weekViewBody: some View {
        if isWeekLoading {
            weekLoading
        } else if let plan = weekData?.mealPlan {
            VStack(spacing: 14) {
                weekMealPlanCard(plan)
                if let list = weekData?.shoppingList, !list.items.isEmpty {
                    weekShoppingCard(list)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        } else {
            weekEmpty
        }
    }

    private func weekMealPlanCard(_ plan: MealPlanWithDays) -> some View {
        let order = [1, 2, 3, 4, 5, 6, 0]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SCIcon("calendar", size: 16, color: Theme.terra)
                Text("Meal Plan")
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.bottom, 4)
            VStack(spacing: 6) {
                ForEach(Array(order.enumerated()), id: \.offset) { _, dow in
                    let meal = plan.days.first { $0.dayOfWeek == dow }
                    weekDayRow(dow: dow, plan: plan, meal: meal)
                }
            }
        }
        .padding(14)
        .cardSurface(18)
    }

    private func weekDayRow(dow: Int, plan: MealPlanWithDays, meal: MealPlanDay?) -> some View {
        Button {
            if let meal { openDay = meal }
        } label: {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(DateUtil.dayName(dow).prefix(3).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(Theme.ink3)
                    Text(DateUtil.dayNumber(for: dow, weekStart: plan.weekStartDate))
                        .font(Theme.display(18, weight: .medium))
                        .foregroundStyle(Theme.ink)
                }
                .frame(width: 44)
                if let meal {
                    Text(meal.mealName)
                        .font(Theme.sans(14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                } else {
                    Text("No meal planned")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.ink3)
                }
                Spacer(minLength: 0)
                if meal != nil {
                    SCIcon("chevR", size: 14, color: Theme.ink4)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(meal == nil ? Color.clear : Theme.elev.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(meal == nil)
    }

    private func weekShoppingCard(_ list: ShoppingListWithItems) -> some View {
        let checked = list.items.filter { $0.checked == 1 }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SCIcon("cart", size: 16, color: Theme.sage)
                Text("Shopping List")
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            Text("\(checked) of \(list.items.count) items checked")
                .font(Theme.sans(13))
                .foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardSurface(18)
    }

    private var weekLoading: some View {
        VStack(spacing: 10) {
            ForEach(0..<7, id: \.self) { _ in
                Rectangle()
                    .fill(Theme.elev)
                    .frame(height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 16)
        .redacted(reason: .placeholder)
    }

    private var weekEmpty: some View {
        VStack(spacing: 8) {
            Text("No meals planned")
                .font(Theme.display(18, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text("Go to the Plan tab to create a meal plan for this week.")
                .font(Theme.sans(13))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
        .padding(.horizontal, 24)
    }

    @MainActor
    private func loadWeek() async {
        guard viewMode == .week else { return }
        isWeekLoading = true
        defer { isWeekLoading = false }
        let client = APIClient(baseURL: AppConfig.backendBaseURL, auth: auth)
        do {
            let resp: WeekResponse = try await client.get("/api/kitchen/week/\(currentWeek)")
            weekData = resp
        } catch let e as APIError where e.isBenignCancellation {
            return
        } catch {
            weekData = nil
        }
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

    // monthNav was inlined into `topNav` once the Week/Month toggle
    // landed — both views share the same prev/today/next row now.

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
