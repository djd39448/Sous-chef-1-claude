import SwiftUI

/// The Home tab — tonight's dinner, the week strip, a chat shortcut, the pantry.
///
/// Data-wired sections: header (greeting, date, avatar from `Profile`),
/// tonight card (today's `MealPlanDay`), week strip (the plan's 7 days).
/// Chat shortcut and pantry are still on mock content; both are wired in
/// follow-up iterations.
struct HomeScreen: View {
    var goToTab: (Tab) -> Void = { _ in }
    var openRecipe: (RecipeSource) -> Void = { _ in }

    @Environment(AuthModel.self) private var auth

    @State private var loadState: LoadState = .loading
    @State private var isGeneratingPlan = false

    /// Maps meal-plan-day id → just-generated image URL. Lets the
    /// tonight hero swap to the fresh image without waiting for the
    /// next load() refetch. We keep it as a dictionary so flipping
    /// between tabs (which keeps Home alive) doesn't lose what we
    /// generated for a different day this session.
    @State private var autoImageURLs: [Int: String] = [:]
    /// The set of meal-plan-day ids we've already kicked off an
    /// auto-generation for in this session — prevents a re-fire if the
    /// view body re-runs while the request is still in flight.
    @State private var autoTried: Set<Int> = []
    /// Currently auto-generating for which day id? (Drives the spinner
    /// overlay on the tonight hero.)
    @State private var autoGenerating: Int?

    private enum LoadState {
        case loading
        case loaded(profile: Profile, plan: MealPlanWithDays?, ingredients: [Ingredient])
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                tonightCard
                weekSection
                chatShortcut
                pantrySection
            }
        }
        .background(Theme.bg)
        .tabBarClearance()
        .navigationBarHidden(true)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Loading

    private func load() async {
        loadState = .loading
        let client = APIClient(baseURL: AppConfig.backendBaseURL, auth: auth)
        do {
            async let profileTask: Profile = client.get("/api/auth/user")
            async let planTask: MealPlanWithDays? = client.get("/api/kitchen/meal-plan")
            async let ingredientsTask: [Ingredient] = client.get("/api/kitchen/ingredients")
            let profile = try await profileTask
            let plan = try await planTask
            // Ingredients are best-effort: an empty pantry shouldn't break the screen.
            let ingredients = (try? await ingredientsTask) ?? []
            loadState = .loaded(profile: profile, plan: plan, ingredients: ingredients)
        } catch let e as APIError where e.isBenignCancellation {
            // The view went away mid-fetch — leave the existing state alone
            // rather than flashing a scary error card.
            return
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: Derived

    private var profile: Profile? {
        if case .loaded(let p, _, _) = loadState { return p } else { return nil }
    }

    private var plan: MealPlanWithDays? {
        if case .loaded(_, let p, _) = loadState { return p } else { return nil }
    }

    private var ingredients: [Ingredient] {
        if case .loaded(_, _, let i) = loadState { return i } else { return [] }
    }

    private var todayDayOfWeek: Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekday - 1   // Calendar's 1=Sun → 0=Sun
    }

    private var todayMeal: MealPlanDay? {
        plan?.days.first { $0.dayOfWeek == todayDayOfWeek }
    }

    /// Plan days sorted Monday-first (Sun last), matching the design's week strip.
    private var weekDays: [MealPlanDay] {
        guard let plan else { return [] }
        return plan.days.sorted { lhs, rhs in
            let l = lhs.dayOfWeek == 0 ? 7 : lhs.dayOfWeek
            let r = rhs.dayOfWeek == 0 ? 7 : rhs.dayOfWeek
            return l < r
        }
    }

    private var greeting: String {
        // Greeting tone — "Afternoon, Dave." when we know a first name,
        // otherwise just "Good afternoon." rather than pasting in the email
        // handle (B-15: "Afternoon, test2." reads wrong).
        let hour = Calendar.current.component(.hour, from: Date())
        let timeWord = hour < 12 ? "Morning" : hour < 17 ? "Afternoon" : "Evening"
        if let name = profile?.firstName, !name.isEmpty {
            return "\(timeWord), \(name)."
        }
        return "Good \(timeWord.lowercased())."
    }

    private var todayHeader: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE · MMM d"
        return fmt.string(from: Date()).uppercased()
    }

    private var avatarMenu: some View {
        Menu {
            Button(role: .destructive) {
                auth.signOut()
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            avatarCircle
        }
    }

    private var avatarCircle: some View {
        Text(avatarInitial.isEmpty ? "·" : avatarInitial)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.terraDeep)
            .frame(width: 40, height: 40)
            .background(Theme.terraSoft)
            .clipShape(Circle())
    }

    private var avatarInitial: String {
        let source = profile?.firstName ?? profile?.email ?? ""
        return source.prefix(1).uppercased()
    }

    private static let dayAbbrev = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    // MARK: Header

    private var headerRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(todayHeader)
                    .font(.system(size: 13, weight: .medium))
                    .tracking(0.2)
                    .foregroundStyle(Theme.ink3)
                Text(greeting)
                    .font(Theme.display(30, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .redacted(reason: profile == nil ? .placeholder : [])
            }
            Spacer()
            avatarMenu
        }
        .padding(.top, 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    // MARK: Tonight

    @ViewBuilder
    private var tonightCard: some View {
        switch loadState {
        case .loading:
            tonightSkeleton
        case .failed(let message):
            errorCard(message: message)
        case .loaded(_, .none, _):
            tonightEmpty
        case .loaded(_, .some, _):
            if let meal = todayMeal {
                tonightLoaded(meal: meal)
            } else {
                tonightEmpty
            }
        }
    }

    private var tonightSkeleton: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.elev)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
            VStack(alignment: .leading, spacing: 8) {
                Text("Loading tonight's dinner…")
                    .font(Theme.display(20, weight: .medium))
                    .foregroundStyle(Theme.ink3)
                ProgressView().tint(Theme.terra)
            }
            .padding(20)
        }
        .cardSurface(24)
        .padding(.horizontal, 16)
    }

    private var tonightEmpty: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No meal plan for this week yet.")
                .font(Theme.display(20, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text("Tap below — Sous Chef will put one together right now.")
                .font(Theme.sans(14))
                .foregroundStyle(Theme.ink2)
            Button { Task { await generatePlan() } } label: {
                HStack(spacing: 8) {
                    if isGeneratingPlan {
                        ProgressView().tint(.white)
                    } else {
                        SCIcon("sparkle", size: 16, color: .white)
                    }
                    Text(isGeneratingPlan ? "Cooking up your week…" : "Plan my week")
                        .font(Theme.sans(14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(Theme.terra)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isGeneratingPlan)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .cardSurface(24)
        .padding(.horizontal, 16)
    }

    /// Auto-fire image generation for tonight's dinner the first time
    /// we see a meal that has no `imageUrl` yet. Runs once per day id
    /// per session — the `autoTried` set keeps us from re-firing if the
    /// view re-renders during the in-flight call. Server persists the
    /// image to `meal_plan_days.image_url` so the next launch finds it
    /// already there and skips this whole path.
    @MainActor
    private func autoGenerateTonightImageIfNeeded(meal: MealPlanDay) async {
        // Server already has an image — nothing to do.
        if meal.imageUrl != nil { return }
        // Locally already generated this session — nothing to do.
        if autoImageURLs[meal.id] != nil { return }
        // Already started a request for this day id — guard against
        // SwiftUI's task re-fires while the in-flight call is pending.
        if autoTried.contains(meal.id) { return }
        autoTried.insert(meal.id)

        let prompt = (meal.recipeImagePrompt?.isEmpty == false)
            ? meal.recipeImagePrompt!
            : meal.mealName
        guard !prompt.isEmpty else { return }

        autoGenerating = meal.id
        defer { autoGenerating = nil }

        let client = APIClient(baseURL: AppConfig.backendBaseURL, auth: auth)
        struct Body: Encodable {
            let prompt: String
            let dayId: Int
        }
        struct Response: Decodable { let imageUrl: String }
        do {
            let resp: Response = try await client.post(
                "/api/kitchen/regenerate-image",
                Body(prompt: prompt, dayId: meal.id)
            )
            withAnimation(.easeInOut(duration: 0.25)) {
                autoImageURLs[meal.id] = resp.imageUrl
            }
        } catch let e as APIError where e.isBenignCancellation {
            // View went away mid-request; allow a retry next time by
            // clearing the "already tried" marker.
            autoTried.remove(meal.id)
        } catch {
            // Quietly fail — auto-generation is best-effort. The user
            // can still tap the photo button on the Recipe screen.
            autoTried.remove(meal.id)
        }
    }

    /// One-click plan generation from the Home tab. Calls
    /// `/api/kitchen/generate-meal-plan` directly and reloads the screen
    /// so the new plan shows up immediately, instead of bouncing the
    /// user into chat to type the request out.
    @MainActor
    private func generatePlan() async {
        guard !isGeneratingPlan else { return }
        isGeneratingPlan = true
        defer { isGeneratingPlan = false }
        let client = APIClient(baseURL: AppConfig.backendBaseURL, auth: auth)
        struct Body: Encodable { let weekStartDate: String }
        do {
            let _: MealPlanWithDays = try await client.post(
                "/api/kitchen/generate-meal-plan",
                Body(weekStartDate: DateUtil.todaysMondayString())
            )
            await load()
        } catch let e as APIError where e.isBenignCancellation {
            return
        } catch {
            loadState = .failed("Couldn't generate a plan: \(error.localizedDescription)")
        }
    }

    private func tonightLoaded(meal: MealPlanDay) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.elev)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay {
                    RecipeImage(
                        url: autoImageURLs[meal.id] ?? meal.imageUrl,
                        isGenerating: autoGenerating == meal.id
                    )
                }
                .clipped()
                .task(id: meal.id) { await autoGenerateTonightImageIfNeeded(meal: meal) }
                .overlay(alignment: .topLeading) {
                    Text("TONIGHT'S DINNER")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(14)
                }

            VStack(alignment: .leading, spacing: 0) {
                Text(meal.mealName)
                    .font(Theme.display(24, weight: .medium))
                    .foregroundStyle(Theme.ink)
                tonightMeta(notes: meal.notes)
                    .padding(.top, 8)
                // Swap button removed (B-09) — there's no swap flow yet, and
                // a button that does nothing is worse than no button. Add it
                // back when the recipe-chat update_meal tool is wired.
                Button { openRecipe(.mealPlanDay(meal)) } label: {
                    Text("View Recipe")
                        .font(Theme.sans(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .cardSurface(24)
        .padding(.horizontal, 16)
    }

    private func tonightMeta(notes: String?) -> some View {
        // Skip the clock chip entirely when notes are empty (B-16) — the
        // bare "—" next to "Serves 4 · Easy" reads as broken UI.
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespaces)
        let hasNotes = !(trimmedNotes?.isEmpty ?? true)
        return HStack(spacing: 14) {
            if hasNotes, let n = trimmedNotes {
                metaItem("clock", n)
                metaDot
            }
            metaItem("people", "Serves 4")
            metaDot
            metaItem("flame", "Easy")
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.ink2)
    }

    private func metaItem(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            SCIcon(icon, size: 14, color: Theme.ink2)
            Text(text)
        }
    }

    private var metaDot: some View {
        Circle().fill(Theme.ink4).frame(width: 2, height: 2)
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't load your kitchen.")
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

    // MARK: This week

    @ViewBuilder
    private var weekSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("This Week")
                    .font(Theme.display(20, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button { goToTab(.plan) } label: {
                    Text("See all →")
                        .font(Theme.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.terra)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if weekDays.isEmpty {
                        ForEach(0..<7, id: \.self) { _ in placeholderDayCard }
                    } else {
                        ForEach(weekDays) { day in
                            // Wrap in Button so the cards actually go somewhere
                            // (B-14) — users naturally try to tap them.
                            Button { openRecipe(.mealPlanDay(day)) } label: {
                                dayCard(day)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }

    private func dayCard(_ day: MealPlanDay) -> some View {
        let isToday = day.dayOfWeek == todayDayOfWeek
        return VStack(alignment: .leading, spacing: 0) {
            Text(Self.dayAbbrev[day.dayOfWeek])
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .opacity(0.7)
            Text(day.mealName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .frame(height: 30, alignment: .top)
                .padding(.top, 8)
        }
        .foregroundStyle(isToday ? Theme.bg : Theme.ink)
        .frame(width: 88, alignment: .leading)
        .padding(12)
        .background(isToday ? Theme.ink : Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.hairline2, lineWidth: isToday ? 0 : 1)
        )
    }

    private var placeholderDayCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("—")
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.5)
            Text("")
                .frame(height: 30)
        }
        .foregroundStyle(Theme.ink3)
        .frame(width: 88, alignment: .leading)
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.hairline2, lineWidth: 1)
        )
    }

    // MARK: Chat shortcut + pantry (still mock content)

    private var chatShortcut: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ask Sous Chef")
                .font(Theme.display(20, weight: .medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 4)
                .padding(.bottom, 12)

            Button { goToTab(.chat) } label: {
                VStack(alignment: .leading, spacing: 14) {
                    Text("What's for lunch with what's in my fridge?")
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.ink3)
                    FlowLayout(spacing: 6) {
                        Chip(label: "Plan my week", icon: "sparkle")
                        Chip(label: "I bought groceries")
                        Chip(label: "Quick dinner")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .cardSurface(18)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 26)
    }

    private var pantrySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("In Your Pantry")
                    .font(Theme.display(20, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(ingredients.isEmpty ? "Nothing yet" : "\(ingredients.count) items")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.bottom, 8)

            if ingredients.isEmpty {
                Text("Tell Sous Chef what you have on hand in the chat — it'll remember.")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(ingredients) { item in
                        HStack(spacing: 7) {
                            CatDot(category: "other")
                            Text(item.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.ink)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .cardSurface(14)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

}

/// A simple flow layout — lays children left-to-right, wrapping to new rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
