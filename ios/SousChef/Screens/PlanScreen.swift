import SwiftUI

/// The Plan tab — a meal plan for whatever week the user is viewing,
/// with prev/next arrows to flip weeks and a link to the calendar.
///
/// Wired to `GET /api/kitchen/week/{weekStartDate}` (returns
/// `WeekResponse`). The screen owns a `currentWeek` Monday string that
/// the arrows shift by ±7 days; each shift refetches. Loading/empty/error
/// states render in the meal-rows region; the NavBar and shopping
/// summary stay in place.
struct PlanScreen: View {
    var goToTab: (Tab) -> Void = { _ in }
    var openRecipe: (RecipeSource) -> Void = { _ in }

    @Environment(AuthModel.self) private var auth
    @State private var showCalendar = false
    @State private var loadState: LoadState = .loading
    @State private var currentWeek: String = DateUtil.todaysMondayString()
    @State private var isGenerating = false

    /// True while the user is in "check the meals to keep, regenerate
    /// the rest" mode. Toggled by the Edit Plan / Cancel button above
    /// the meal list. Resets when the week changes.
    @State private var isEditMode = false
    /// Set of meal-plan-day ids the user has *approved* (checked) in
    /// edit mode — these are the meals to KEEP. Unchecked days are
    /// what `/regenerate-days` replaces.
    @State private var approvedDayIds: Set<Int> = []
    /// True while `/regenerate-days` is in flight — drives the button
    /// spinner and disables both Regenerate and Finalize.
    @State private var isRegeneratingDays = false

    private enum LoadState {
        case loading
        case loaded(plan: MealPlanWithDays?)
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                NavBar(
                    largeTitle: "Meal Plan",
                    leading: AnyView(IconButton(icon: "calendar") { showCalendar = true })
                    // Per the original web app, the Plan view is read-only.
                    // "Editing" a plan = swapping a meal via recipe chat
                    // (open a day → ask the AI to swap). The pencil/edit
                    // sheet was removed once Dave confirmed the original
                    // doesn't have one.
                )
                weekSelector
                content
                shoppingSummary
            }
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showCalendar) { CalendarScreen() }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Loading

    private func load() async {
        loadState = .loading
        let client = APIClient(baseURL: AppConfig.backendBaseURL, auth: auth)
        do {
            let resp: WeekResponse = try await client.get("/api/kitchen/week/\(currentWeek)")
            loadState = .loaded(plan: resp.mealPlan)
        } catch let e as APIError where e.isBenignCancellation {
            return
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// One-click meal-plan generation. Posts to
    /// `/api/kitchen/generate-meal-plan` (no chat detour) and replaces
    /// the loaded plan with the result. The button stays disabled until
    /// the call returns or errors.
    @MainActor
    private func generatePlan() async {
        guard !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }
        let client = APIClient(baseURL: AppConfig.backendBaseURL, auth: auth)
        struct Body: Encodable { let weekStartDate: String }
        do {
            let plan: MealPlanWithDays = try await client.post(
                "/api/kitchen/generate-meal-plan",
                Body(weekStartDate: currentWeek)
            )
            loadState = .loaded(plan: plan)
        } catch let e as APIError where e.isBenignCancellation {
            return
        } catch {
            loadState = .failed("Couldn't generate a plan: \(error.localizedDescription)")
        }
    }

    private var plan: MealPlanWithDays? {
        if case .loaded(let p) = loadState { return p } else { return nil }
    }

    // MARK: Week selector

    private var weekSelector: some View {
        HStack(spacing: 10) {
            Button { shiftWeek(-1) } label: { circleArrow("chevL") }
                .buttonStyle(.plain)
                .disabled(isLoading)
            Text(weekRangeText)
                .font(Theme.sans(14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Theme.card)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline2, lineWidth: 1))
            Button { shiftWeek(+1) } label: { circleArrow("chevR") }
                .buttonStyle(.plain)
                .disabled(isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func circleArrow(_ icon: String) -> some View {
        SCIcon(icon, size: 18, color: Theme.ink)
            .frame(width: 36, height: 36)
            .background(Theme.card)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.hairline2, lineWidth: 1))
    }

    private var isLoading: Bool {
        if case .loading = loadState { return true } else { return false }
    }

    private func shiftWeek(_ delta: Int) {
        currentWeek = DateUtil.shiftMonday(currentWeek, weeks: delta)
        // Edit mode is per-week — leaving the week aborts the in-progress
        // keep/regenerate selection.
        exitEditMode()
        Task { await load() }
    }

    private var weekRangeText: String {
        // Drive the label off `currentWeek` (not the plan) so the arrows
        // shift the label even when the new week has no plan yet.
        DateUtil.weekRangeString(weekStart: currentWeek)
    }

    // MARK: Content (loading / empty / loaded / error)

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            loadingRows
        case .failed(let message):
            errorCard(message: message)
        case .loaded(.none):
            emptyCard
        case .loaded(.some(let plan)):
            mealRows(plan: plan)
        }
    }

    private var loadingRows: some View {
        VStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 14) {
                    Rectangle().fill(Theme.elev).frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 6) {
                        Rectangle().fill(Theme.elev).frame(height: 12).clipShape(Capsule())
                        Rectangle().fill(Theme.elev).frame(width: 80, height: 10).clipShape(Capsule())
                    }
                    Spacer()
                }
                .padding(12)
                .cardSurface(20)
            }
        }
        .padding(.horizontal, 16)
        .redacted(reason: .placeholder)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No plan for this week yet.")
                .font(Theme.display(20, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text("Tap below and Sous Chef will put one together for you.")
                .font(Theme.sans(14))
                .foregroundStyle(Theme.ink2)
            Button { Task { await generatePlan() } } label: {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView().tint(.white)
                    } else {
                        SCIcon("sparkle", size: 16, color: .white)
                    }
                    Text(isGenerating ? "Cooking up your week…" : "Plan my week")
                        .font(Theme.sans(14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(Theme.terra)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .cardSurface(24)
        .padding(.horizontal, 16)
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't load your meal plan.")
                .font(Theme.display(20, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(Theme.sans(13))
                .foregroundStyle(Theme.ink2)
            Button { Task { await load() } } label: {
                Text("Try again")
                    .font(Theme.sans(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(Theme.terra)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .cardSurface(24)
        .padding(.horizontal, 16)
    }

    // MARK: Loaded rows

    /// The header above the meal list. In normal mode shows "Tap a day
    /// to view recipe" with an Edit Plan button. In edit mode shows
    /// the keep-some-regenerate-rest instructions and a Cancel button.
    /// Mirrors the original web app's plan view exactly.
    private var planListHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isCurrentWeek ? "This Week's Dinners" : "Week of \(shortMonthDay(currentWeek))")
                    .font(Theme.display(18, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(isEditMode
                     ? "Check meals you want to keep, regenerate the rest"
                     : "Tap a day to view recipe")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                if isEditMode {
                    exitEditMode()
                } else {
                    isEditMode = true
                    approvedDayIds = []
                }
            } label: {
                Text(isEditMode ? "Cancel" : "Edit Plan")
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(isEditMode ? Theme.ink2 : Theme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(isEditMode ? Color.clear : Theme.card)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(
                        isEditMode ? Color.clear : Theme.hairline2,
                        lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isRegeneratingDays)
        }
        .padding(.bottom, 6)
    }

    private func exitEditMode() {
        isEditMode = false
        approvedDayIds = []
    }

    private var isCurrentWeek: Bool {
        currentWeek == DateUtil.todaysMondayString()
    }

    /// "May 25" — short month + day, used in the "Week of …" header.
    private func shortMonthDay(_ iso: String) -> String {
        guard let d = DateUtil.dateFromISO(iso) else { return iso }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.timeZone = DateUtil.utc.timeZone
        return f.string(from: d)
    }

    /// Plan days sorted Monday-first (Sunday last) — the display order.
    private func sortedDays(_ plan: MealPlanWithDays) -> [MealPlanDay] {
        plan.days.sorted { lhs, rhs in
            let l = lhs.dayOfWeek == 0 ? 7 : lhs.dayOfWeek
            let r = rhs.dayOfWeek == 0 ? 7 : rhs.dayOfWeek
            return l < r
        }
    }

    private func mealRows(plan: MealPlanWithDays) -> some View {
        let today = Calendar.current.component(.weekday, from: Date()) - 1  // 0..6
        let allDays = sortedDays(plan)
        return VStack(spacing: 10) {
            planListHeader
            ForEach(allDays) { day in
                Button {
                    if isEditMode {
                        toggleApproval(day)
                    } else {
                        openRecipe(.mealPlanDay(day))
                    }
                } label: {
                    mealRow(
                        day: day,
                        isToday: day.dayOfWeek == today,
                        plan: plan,
                        isApproved: approvedDayIds.contains(day.id)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRegeneratingDays)
            }
            if isEditMode {
                editModeFooter(plan: plan, allDays: allDays)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
    }

    private func toggleApproval(_ day: MealPlanDay) {
        if approvedDayIds.contains(day.id) {
            approvedDayIds.remove(day.id)
        } else {
            approvedDayIds.insert(day.id)
        }
    }

    private func editModeFooter(plan: MealPlanWithDays, allDays: [MealPlanDay]) -> some View {
        let unchecked = allDays.filter { !approvedDayIds.contains($0.id) }
        let allApproved = approvedDayIds.count == allDays.count && !allDays.isEmpty
        return VStack(spacing: 10) {
            if !unchecked.isEmpty {
                Button {
                    Task { await regenerateUnchecked(unchecked: unchecked) }
                } label: {
                    HStack(spacing: 8) {
                        if isRegeneratingDays {
                            ProgressView().tint(Theme.ink)
                        } else {
                            SCIcon("swap", size: 15, color: Theme.ink)
                        }
                        Text(isRegeneratingDays
                             ? "Regenerating…"
                             : "Regenerate \(unchecked.count) Unchecked Day\(unchecked.count == 1 ? "" : "s")")
                            .font(Theme.sans(14, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline2, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isRegeneratingDays)
            }
            Button {
                exitEditMode()
            } label: {
                HStack(spacing: 8) {
                    SCIcon("check", size: 15, color: .white)
                    Text(allApproved ? "Finalize Plan"
                         : "Approve all \(allDays.count) days to finalize")
                        .font(Theme.sans(14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(allApproved ? Theme.terra : Theme.ink4)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!allApproved || isRegeneratingDays)
        }
    }

    @MainActor
    private func regenerateUnchecked(unchecked: [MealPlanDay]) async {
        guard !isRegeneratingDays else { return }
        let daysToRegenerate = unchecked.map { $0.dayOfWeek }
        guard !daysToRegenerate.isEmpty else { return }
        isRegeneratingDays = true
        defer { isRegeneratingDays = false }

        struct Body: Encodable {
            let weekStartDate: String
            let daysToRegenerate: [Int]
        }
        let client = APIClient(baseURL: AppConfig.backendBaseURL, auth: auth)
        do {
            let updated: MealPlanWithDays = try await client.post(
                "/api/kitchen/regenerate-days",
                Body(weekStartDate: currentWeek, daysToRegenerate: daysToRegenerate)
            )
            loadState = .loaded(plan: updated)
        } catch let e as APIError where e.isBenignCancellation {
            return
        } catch {
            loadState = .failed("Couldn't regenerate: \(error.localizedDescription)")
        }
    }

    private func mealRow(day: MealPlanDay, isToday: Bool, plan: MealPlanWithDays, isApproved: Bool) -> some View {
        // In edit mode the today-tint is dropped — the approval state
        // is the visual signal that matters, and the dark "today"
        // background would fight with the terra approval ring.
        let dimmedToday = isToday && !isEditMode
        return HStack(spacing: 14) {
            if isEditMode {
                checkbox(isApproved: isApproved)
            }
            VStack(spacing: 2) {
                Text(DateUtil.dayName(day.dayOfWeek).prefix(3).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .opacity(0.6)
                Text(DateUtil.dayNumber(for: day.dayOfWeek, weekStart: plan.weekStartDate))
                    .font(Theme.display(28, weight: .medium))
            }
            .foregroundStyle(dimmedToday ? Theme.bg : Theme.ink)
            .frame(width: 56)

            Rectangle()
                .fill(Theme.elev)
                .frame(width: 60, height: 60)
                .overlay { RecipeImage(url: day.imageUrl, compact: true) }
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(day.mealName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(dimmedToday ? Theme.bg : Theme.ink)
                if let notes = day.notes, !notes.isEmpty {
                    HStack(spacing: 4) {
                        SCIcon("clock", size: 11,
                               color: dimmedToday ? Theme.bg.opacity(0.6) : Theme.ink3)
                        Text(notes).font(.system(size: 12))
                    }
                    .foregroundStyle(dimmedToday ? Theme.bg.opacity(0.6) : Theme.ink3)
                }
            }
            Spacer(minLength: 0)
            // Chevron in normal mode, check in edit-and-approved mode,
            // ink4 dot otherwise (so the row keeps its visual rhythm).
            if isEditMode {
                if isApproved {
                    SCIcon("check", size: 16, color: Theme.terra)
                }
            } else {
                SCIcon("chevR", size: 16,
                       color: dimmedToday ? Theme.bg.opacity(0.5) : Theme.ink4)
            }
        }
        .padding(12)
        .background(dimmedToday ? Theme.ink : Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    isApproved ? Theme.terra : Theme.hairline2,
                    lineWidth: isApproved ? 2 : (dimmedToday ? 0 : 1))
        )
        .shadow(color: .black.opacity(dimmedToday ? 0.18 : 0), radius: 9, y: 6)
    }

    private func checkbox(isApproved: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isApproved ? Theme.terra : Color.clear)
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isApproved ? Theme.terra : Theme.ink4, lineWidth: 1.5)
            if isApproved {
                SCIcon("check", size: 12, color: .white, weight: .bold)
            }
        }
        .frame(width: 22, height: 22)
    }

    // MARK: Shopping summary (still mock — wired with /api/kitchen/shopping-list later)

    private var shoppingSummary: some View {
        Button { goToTab(.shop) } label: {
            HStack(spacing: 14) {
                SCIcon("cart", size: 22, color: .white)
                    .frame(width: 44, height: 44)
                    .background(Theme.sage)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shopping List")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("View this week's items")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink2)
                }
                Spacer(minLength: 0)
                SCIcon("chevR", size: 16, color: Theme.ink3)
            }
            .padding(18)
            .background(Theme.sageSoft)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.hairline2, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        // Extra clearance so the last button isn't hidden behind the
        // custom tab bar (which sits in the safeAreaInset of MainView,
        // ~83pt + bottom safe area).
        .padding(.bottom, 24)
    }
}
