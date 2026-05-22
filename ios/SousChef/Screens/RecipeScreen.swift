import SwiftUI

/// The full-screen recipe detail — hero, ingredients, instructions, and the
/// floating "ask about this recipe" pill. Presented over the tab bar.
struct RecipeScreen: View {
    var onClose: () -> Void = {}

    @State private var saved = true
    @State private var have: Set<Int> = [1, 4, 5]

    private let ingredients = [
        "12 oz spaghetti",
        "6 oz guanciale or pancetta, diced",
        "4 large egg yolks",
        "1 whole egg",
        "1 cup pecorino romano, grated",
        "½ cup parmesan, grated",
        "2 garlic cloves, smashed",
        "freshly ground black pepper",
        "kosher salt",
    ]

    private let steps = [
        "Bring a large pot of well-salted water to a boil.",
        "Whisk egg yolks, whole egg, pecorino, and parmesan in a bowl until thick.",
        "Crisp the guanciale in a dry skillet over medium heat, 6–8 min. Add garlic; cook 30 seconds.",
        "Cook spaghetti until just shy of al dente. Reserve 1 cup pasta water.",
        "Off heat: toss pasta with guanciale, then with the cheese-egg mixture. Add pasta water in splashes until silky.",
        "Finish with cracked pepper. Serve immediately.",
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            scrollContent
            floatingPill
        }
        .background(Theme.bg)
        .overlay(alignment: .top) { topButtons }
    }

    // MARK: Scroll content

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                titleBlock
                ingredientsSection
                instructionsSection
                Color.clear.frame(height: 110)   // clearance for the floating pill
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: Hero

    private var hero: some View {
        Rectangle()
            .fill(Theme.elev)
            .frame(height: 380)
            .overlay {
                FoodImage(url: Food.carbonara)
            }
            .clipped()
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.35), location: 0.0),
                        .init(color: .clear, location: 0.30),
                        .init(color: .clear, location: 0.70),
                        .init(color: Theme.bg, location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) { generatedBadge }
    }

    private var generatedBadge: some View {
        HStack(spacing: 6) {
            SCIcon("sparkle", size: 11, color: Theme.terraDeep, weight: .bold)
            Text("GENERATED FOR TUESDAY")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
        }
        .foregroundStyle(Theme.terraDeep)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.leading, 20)
        .padding(.bottom, 22)
    }

    // MARK: Top buttons (over hero)

    private var topButtons: some View {
        HStack {
            heroButton("chevL", action: onClose)
            Spacer()
            HStack(spacing: 8) {
                heroButton(saved ? "bookmarkF" : "bookmark",
                           color: saved ? Theme.terra : Theme.ink) {
                    withAnimation { saved.toggle() }
                }
                heroButton("photo")
            }
        }
        .padding(.horizontal, 14)
    }

    private func heroButton(_ icon: String, color: Color = Theme.ink, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            SCIcon(icon, size: 18, color: color)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.92))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pasta Carbonara")
                .font(Theme.display(32, weight: .medium))
                .foregroundStyle(Theme.ink)
                .tracking(-1)

            Text("Silky, peppery, deeply savoury — the Roman classic, made with what's in your fridge.")
                .font(Theme.sans(15))
                .foregroundStyle(Theme.ink2)
                .lineSpacing(3)
                .padding(.top, 6)
                .padding(.bottom, 16)

            metaCard
        }
        .padding(.horizontal, 20)
        .padding(.top, -8)
    }

    private var metaCard: some View {
        HStack(spacing: 0) {
            metaCell("PREP", "10 min")
            divider
            metaCell("COOK", "20 min")
            divider
            metaCell("SERVES", "4")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .cardSurface(14)
    }

    private func metaCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.ink3)
            Text(value)
                .font(Theme.display(18, weight: .medium))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 0.5)
    }

    // MARK: Ingredients

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ingredients")
                    .font(Theme.display(22, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("3 of 9 you have")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.bottom, 14)

            VStack(spacing: 0) {
                ForEach(Array(ingredients.enumerated()), id: \.offset) { index, ing in
                    ingredientRow(index: index, text: ing)
                    if index < ingredients.count - 1 { Hairline() }
                }
            }
            .cardSurface(18)

            Button { } label: {
                HStack(spacing: 6) {
                    SCIcon("cart", size: 16, color: Theme.ink)
                    Text("Add 6 missing to shopping list")
                        .font(Theme.sans(13, weight: .semibold))
                }
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Theme.sageSoft)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
    }

    private func ingredientRow(index: Int, text: String) -> some View {
        let checked = have.contains(index)
        return Button {
            if checked { have.remove(index) } else { have.insert(index) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    if checked {
                        RoundedRectangle(cornerRadius: 6).fill(Theme.sage)
                        SCIcon("check", size: 12, color: .white, weight: .bold)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.ink4, lineWidth: 1.5)
                    }
                }
                .frame(width: 20, height: 20)
                Text(text)
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.ink)
                    .strikethrough(checked)
                    .opacity(checked ? 0.5 : 1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Instructions")
                .font(Theme.display(22, weight: .medium))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 0)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 14) {
                    Text("\(index + 1)")
                        .font(Theme.display(14, weight: .semibold))
                        .foregroundStyle(Theme.terraDeep)
                        .frame(width: 28, height: 28)
                        .background(Theme.terraSoft)
                        .clipShape(Circle())
                    Text(step)
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(4)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 32)
    }

    // MARK: Floating pill

    private var floatingPill: some View {
        HStack(spacing: 10) {
            SCIcon("sparkle", size: 16, color: Theme.butter, weight: .bold)
            Text("Ask about this recipe…")
                .font(Theme.sans(14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 0)
            Button { } label: {
                SCIcon("send", size: 18, color: .white)
                    .frame(width: 40, height: 40)
                    .background(Theme.terra)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(height: 56)
        .background(Theme.ink)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.35), radius: 15, y: 12)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
}
