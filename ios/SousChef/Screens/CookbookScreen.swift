import SwiftUI

/// The Cookbook tab — saved recipes: filters, a featured card, and a grid.
struct CookbookScreen: View {
    var openRecipe: () -> Void = {}

    private let filters = ["All · 24", "Quick", "Italian", "Asian", "Mexican", "Vegetarian"]
    private let grid = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                NavBar(
                    largeTitle: "Cookbook",
                    leading: AnyView(IconButton(icon: "search")),
                    trailing: AnyView(IconButton(icon: "plus", color: Theme.terra))
                )
                filterChips
                featured
                recipeGrid
            }
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(filters.enumerated()), id: \.offset) { index, label in
                    Chip(label: label, active: index == 0)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 16)
    }

    private var featured: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Theme.elev)
                .frame(width: 140)
                .overlay { FoodImage(url: Food.carbonara) }
                .clipped()
            VStack(alignment: .leading, spacing: 0) {
                Text("LAST COOKED")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.terra)
                Text("Pasta Carbonara")
                    .font(Theme.display(19, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 4)
                Text("4 days ago")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink3)
                    .padding(.top, 4)
                Spacer(minLength: 8)
                Button(action: openRecipe) {
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

    private var recipeGrid: some View {
        LazyVGrid(columns: grid, spacing: 12) {
            ForEach(Samples.cookbook) { recipe in
                Button(action: openRecipe) { recipeCard(recipe) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    private func recipeCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.elev)
                .aspectRatio(1, contentMode: .fit)
                .overlay { FoodImage(url: recipe.image) }
                .clipped()
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.title)
                    .font(Theme.display(15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        SCIcon("clock", size: 10, color: Theme.ink3)
                        Text(recipe.time)
                    }
                    Circle().fill(Theme.ink4).frame(width: 2, height: 2)
                    Text(recipe.tag)
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink3)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(18)
    }
}
