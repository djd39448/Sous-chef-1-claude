import SwiftUI

/// The Cookbook tab — saved recipes: filters, a "last saved" featured
/// card, and a 2-column grid.
///
/// Wired to `GET /api/kitchen/cookbook` ([CookbookRecipe]). Filter chips
/// are still mock (no tagging in the contract yet); when the user has no
/// saved recipes the grid is replaced by an empty-state card.
struct CookbookScreen: View {
    var openRecipe: (RecipeSource) -> Void = { _ in }

    @Environment(AuthModel.self) private var auth
    @State private var loadState: LoadState = .loading

    private enum LoadState {
        case loading
        case loaded([CookbookRecipe])
        case failed(String)
    }

    // Filter list removed in the dead-button cull (B-12); tagging on
    // cookbook_recipes is a follow-up.
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                NavBar(largeTitle: "Cookbook")
                // Filter chips, search, and the + button were all decorative
                // (B-12). Filters require backend tagging we don't have yet;
                // saving happens from the chat or the Recipe bookmark button.
                // Both reappear once their backends exist.
                content
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
            let list: [CookbookRecipe] = try await client.get("/api/kitchen/cookbook")
            loadState = .loaded(list)
        } catch let e as APIError where e.isBenignCancellation {
            // The view went away mid-fetch — leave the existing state alone
            // rather than flashing a scary error card.
            return
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: Content (loading / empty / loaded / error)

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            loadingGrid
        case .failed(let message):
            errorCard(message: message)
        case .loaded(let recipes) where recipes.isEmpty:
            emptyCard
        case .loaded(let recipes):
            VStack(spacing: 0) {
                featuredCard(recipes.first!)
                recipeGrid(recipes)
            }
        }
    }

    private var loadingGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(Theme.elev).aspectRatio(1, contentMode: .fit)
                    VStack(alignment: .leading, spacing: 8) {
                        Rectangle().fill(Theme.elev).frame(height: 12).clipShape(Capsule())
                        Rectangle().fill(Theme.elev).frame(width: 60, height: 10).clipShape(Capsule())
                    }
                    .padding(12)
                }
                .cardSurface(18)
            }
        }
        .padding(.horizontal, 16)
        .redacted(reason: .placeholder)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your cookbook is empty.")
                .font(Theme.display(20, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text("Generate a recipe in chat and save it — it'll land here.")
                .font(Theme.sans(14))
                .foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .cardSurface(22)
        .padding(.horizontal, 16)
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't load your cookbook.")
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
        .cardSurface(22)
        .padding(.horizontal, 16)
    }

    // MARK: Featured + grid

    private func featuredCard(_ recipe: CookbookRecipe) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Theme.elev)
                .frame(width: 140)
                .overlay { FoodImage(url: ImageLookup.url(for: recipe.title)) }
                .clipped()
            VStack(alignment: .leading, spacing: 0) {
                Text("LAST SAVED")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.terra)
                Text(recipe.title)
                    .font(Theme.display(19, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .padding(.top, 4)
                Text(relativeSaved(recipe.createdAt))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink3)
                    .padding(.top, 4)
                Spacer(minLength: 8)
                Button { openRecipe(.cookbook(recipe)) } label: {
                    Text("Cook again")
                        .font(Theme.sans(12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Theme.ink)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 128)
        .cardSurface(22)
        .padding(.horizontal, 16)
        .padding(.bottom, 18)
    }

    private func recipeGrid(_ recipes: [CookbookRecipe]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(recipes) { recipe in
                Button { openRecipe(.cookbook(recipe)) } label: { recipeCard(recipe) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    private func recipeCard(_ recipe: CookbookRecipe) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.elev)
                .aspectRatio(1, contentMode: .fit)
                .overlay { FoodImage(url: ImageLookup.url(for: recipe.title)) }
                .clipped()
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.title)
                    .font(Theme.display(15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    SCIcon("clock", size: 10, color: Theme.ink3)
                    Text(relativeSaved(recipe.createdAt))
                        .font(.system(size: 11))
                }
                .foregroundStyle(Theme.ink3)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(18)
    }

    private func relativeSaved(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return "Saved \(fmt.localizedString(for: date, relativeTo: Date()))"
    }
}
