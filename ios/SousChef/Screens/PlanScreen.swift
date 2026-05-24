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
        return VStack(spacing: 10) {
            ForEach(sortedDays(plan)) { day in
                Button { openRecipe(.mealPlanDay(day)) } label: {
                    mealRow(day: day, isToday: day.dayOfWeek == today, plan: plan)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private func mealRow(day: MealPlanDay, isToday: Bool, plan: MealPlanWithDays) -> some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(DateUtil.dayName(day.dayOfWeek).prefix(3).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .opacity(0.6)
                Text(DateUtil.dayNumber(for: day.dayOfWeek, weekStart: plan.weekStartDate))
                    .font(Theme.display(28, weight: .medium))
            }
            .foregroundStyle(isToday ? Theme.bg : Theme.ink)
            .frame(width: 56)

            Rectangle()
                .fill(Theme.elev)
                .frame(width: 60, height: 60)
                .overlay { RecipeImage(url: day.imageUrl, compact: true) }
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(day.mealName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isToday ? Theme.bg : Theme.ink)
                if let notes = day.notes, !notes.isEmpty {
                    HStack(spacing: 4) {
                        SCIcon("clock", size: 11,
                               color: isToday ? Theme.bg.opacity(0.6) : Theme.ink3)
                        Text(notes).font(.system(size: 12))
                    }
                    .foregroundStyle(isToday ? Theme.bg.opacity(0.6) : Theme.ink3)
                }
            }
            Spacer(minLength: 0)
            SCIcon("chevR", size: 16,
                   color: isToday ? Theme.bg.opacity(0.5) : Theme.ink4)
        }
        .padding(12)
        .background(isToday ? Theme.ink : Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Theme.hairline2, lineWidth: isToday ? 0 : 1)
        )
        .shadow(color: .black.opacity(isToday ? 0.18 : 0), radius: 9, y: 6)
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
    }
}
