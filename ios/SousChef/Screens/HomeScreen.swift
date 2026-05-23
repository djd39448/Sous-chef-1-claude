import SwiftUI

/// The Home tab — tonight's dinner, the week strip, a chat shortcut, the pantry.
///
/// Data-wired sections: header (greeting, date, avatar from `Profile`),
/// tonight card (today's `MealPlanDay`), week strip (the plan's 7 days).
/// Chat shortcut and pantry are still on mock content; both are wired in
/// follow-up iterations.
struct HomeScreen: View {
    var goToTab: (Tab) -> Void = { _ in }
    var openRecipe: () -> Void = {}

    @Environment(AuthModel.self) private var auth

    @State private var loadState: LoadState = .loading

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
        let hour = Calendar.current.component(.hour, from: Date())
        let timeWord = hour < 12 ? "Morning" : hour < 17 ? "Afternoon" : "Evening"
        let name = profile?.firstName
            ?? profile?.email?.split(separator: "@").first.map(String.init)
            ?? "there"
        return "\(timeWord), \(name)."
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
            Text("Ask Sous Chef to plan your week from the chat.")
                .font(Theme.sans(14))
                .foregroundStyle(Theme.ink2)
            Button { goToTab(.chat) } label: {
                HStack(spacing: 8) {
                    SCIcon("sparkle", size: 16, color: .white)
                    Text("Plan my week").font(Theme.sans(14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(Theme.terra)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .cardSurface(24)
        .padding(.horizontal, 16)
    }

    private func tonightLoaded(meal: MealPlanDay) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.elev)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay { FoodImage(url: ImageLookup.url(for: meal.mealName)) }
                .clipped()
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
                HStack(spacing: 8) {
                    Button(action: openRecipe) {
                        Text("View Recipe")
                            .font(Theme.sans(14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Theme.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    Button { } label: {
                        HStack(spacing: 6) {
                            SCIcon("swap", size: 15, color: Theme.ink)
                            Text("Swap").font(Theme.sans(14, weight: .medium))
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(Theme.elev)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
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
        HStack(spacing: 14) {
            metaItem("clock", notes ?? "—")
            metaDot
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
                        ForEach(weekDays) { day in dayCard(day) }
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
