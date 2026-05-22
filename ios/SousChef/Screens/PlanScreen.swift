import SwiftUI

/// The Plan tab — this week's meal plan, with a link to the calendar.
struct PlanScreen: View {
    var goToTab: (Tab) -> Void = { _ in }
    var openRecipe: () -> Void = {}
    @State private var showCalendar = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                NavBar(
                    largeTitle: "Meal Plan",
                    leading: AnyView(IconButton(icon: "calendar") { showCalendar = true }),
                    trailing: AnyView(IconButton(icon: "sparkle", color: Theme.terra))
                )
                weekSelector
                mealRows
                shoppingSummary
            }
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showCalendar) { CalendarScreen() }
    }

    // MARK: Week selector

    private var weekSelector: some View {
        HStack(spacing: 10) {
            circleButton("chevL")
            Text("May 25 – 31 · This week")
                .font(Theme.sans(14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Theme.card)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline2, lineWidth: 1))
            circleButton("chevR")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func circleButton(_ icon: String) -> some View {
        SCIcon(icon, size: 18, color: Theme.ink)
            .frame(width: 36, height: 36)
            .background(Theme.card)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.hairline2, lineWidth: 1))
    }

    // MARK: Meal rows

    private var mealRows: some View {
        VStack(spacing: 10) {
            ForEach(Samples.planMeals) { meal in
                Button(action: openRecipe) { mealRow(meal) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private func mealRow(_ meal: PlanMeal) -> some View {
        let isToday = meal.state == .today
        let isCooked = meal.state == .cooked
        return HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(meal.day.prefix(3).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .opacity(0.6)
                Text(meal.date.split(separator: " ").last.map(String.init) ?? "")
                    .font(Theme.display(28, weight: .medium))
            }
            .foregroundStyle(isToday ? Theme.bg : Theme.ink)
            .frame(width: 56)

            Rectangle()
                .fill(Theme.elev)
                .frame(width: 60, height: 60)
                .overlay { FoodImage(url: meal.image) }
                .overlay {
                    if isCooked {
                        Color.white.opacity(0.45)
                            .overlay {
                                SCIcon("check", size: 14, color: .white, weight: .bold)
                                    .frame(width: 22, height: 22)
                                    .background(Theme.sage)
                                    .clipShape(Circle())
                            }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(meal.meal)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isToday ? Theme.bg : Theme.ink)
                HStack(spacing: 4) {
                    SCIcon("clock", size: 11, color: isToday ? Theme.bg.opacity(0.6) : Theme.ink3)
                    Text(meal.notes).font(.system(size: 12))
                }
                .foregroundStyle(isToday ? Theme.bg.opacity(0.6) : Theme.ink3)
            }
            Spacer(minLength: 0)
            SCIcon("chevR", size: 16, color: isToday ? Theme.bg.opacity(0.5) : Theme.ink4)
        }
        .padding(12)
        .background(isToday ? Theme.ink : Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Theme.hairline2, lineWidth: isToday ? 0 : 1)
        )
        .shadow(color: .black.opacity(isToday ? 0.18 : 0), radius: 9, y: 6)
        .opacity(isCooked ? 0.6 : 1)
    }

    // MARK: Shopping summary

    private var shoppingSummary: some View {
        Button { goToTab(.shop) } label: {
            HStack(spacing: 14) {
                SCIcon("cart", size: 22, color: .white)
                    .frame(width: 44, height: 44)
                    .background(Theme.sage)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly Shopping List")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("23 items · 8 checked off")
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
