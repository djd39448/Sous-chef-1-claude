import SwiftUI

private struct CalDay: Identifiable {
    let id = UUID()
    let d: Int
    var dim = false
    var today = false
    var hasPlan = false
    var hasList = false
}

/// The Calendar screen — a month grid of weeks that have plans or lists.
/// Pushed from the Plan tab.
struct CalendarScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "plans"   // "plans" or "lists"

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private let days: [CalDay] = [
        CalDay(d: 26, dim: true), CalDay(d: 27, dim: true), CalDay(d: 28, dim: true),
        CalDay(d: 29, dim: true), CalDay(d: 30, dim: true),
        CalDay(d: 1, hasPlan: true), CalDay(d: 2, hasPlan: true, hasList: true),
        CalDay(d: 3, hasPlan: true, hasList: true), CalDay(d: 4, hasPlan: true),
        CalDay(d: 5, hasPlan: true), CalDay(d: 6, hasPlan: true), CalDay(d: 7, hasPlan: true),
        CalDay(d: 8, hasPlan: true), CalDay(d: 9, hasPlan: true, hasList: true),
        CalDay(d: 10, hasPlan: true, hasList: true), CalDay(d: 11, hasPlan: true),
        CalDay(d: 12, hasPlan: true), CalDay(d: 13, hasPlan: true), CalDay(d: 14, hasPlan: true),
        CalDay(d: 15, hasPlan: true), CalDay(d: 16, hasPlan: true, hasList: true),
        CalDay(d: 17, hasPlan: true, hasList: true), CalDay(d: 18, hasPlan: true),
        CalDay(d: 19, hasPlan: true), CalDay(d: 20, hasPlan: true), CalDay(d: 21, hasPlan: true),
        CalDay(d: 22, hasPlan: true), CalDay(d: 23, hasPlan: true, hasList: true),
        CalDay(d: 24, hasPlan: true, hasList: true), CalDay(d: 25, hasPlan: true),
        CalDay(d: 26, today: true, hasPlan: true), CalDay(d: 27, hasPlan: true),
        CalDay(d: 28, hasPlan: true), CalDay(d: 29, hasPlan: true),
        CalDay(d: 30, hasPlan: true, hasList: true),
        CalDay(d: 31, hasPlan: true), CalDay(d: 1, dim: true), CalDay(d: 2, dim: true),
        CalDay(d: 3, dim: true), CalDay(d: 4, dim: true), CalDay(d: 5, dim: true),
        CalDay(d: 6, dim: true),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                NavBar(
                    largeTitle: "May 2026",
                    leading: AnyView(IconButton(icon: "chevL") { dismiss() }),
                    trailing: AnyView(IconButton(icon: "chevR"))
                )
                segmented
                weekdayHeader
                grid
                dayDetail
            }
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(["plans", "lists"], id: \.self) { id in
                let on = mode == id
                Button { mode = id } label: {
                    Text(id == "plans" ? "Meal Plans" : "Shopping Lists")
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

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days) { day in
                cell(day)
            }
        }
        .padding(.horizontal, 16)
    }

    private func cell(_ day: CalDay) -> some View {
        let lit = (day.hasPlan && mode == "plans") || (day.hasList && mode == "lists")
        let bg: Color = day.today ? Theme.terra : (lit ? Theme.card : .clear)
        let fg: Color = day.today ? .white : (day.dim ? Theme.ink4 : Theme.ink)
        return VStack {
            Text("\(day.d)")
                .font(.system(size: 14, weight: day.today ? .semibold : .medium))
                .foregroundStyle(fg)
            Spacer(minLength: 0)
            Group {
                if mode == "plans" && day.hasPlan {
                    Circle().fill(day.today ? Color.white : Theme.terra).frame(width: 5, height: 5)
                } else if mode == "lists" && day.hasList {
                    Circle().fill(day.today ? Color.white : Theme.sage).frame(width: 5, height: 5)
                } else {
                    Color.clear.frame(width: 5, height: 5)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .aspectRatio(1.0 / 1.15, contentMode: .fit)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.hairline2, lineWidth: (lit && !day.today) ? 1 : 0)
        )
    }

    private var dayDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TUESDAY, MAY 26 · TODAY")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.ink3)
                .padding(.horizontal, 6)

            HStack(spacing: 12) {
                Rectangle()
                    .fill(Theme.elev)
                    .frame(width: 52, height: 52)
                    .overlay { FoodImage(url: Food.carbonara) }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pasta Carbonara")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("30 min · Tonight's plan")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink2)
                }
                Spacer(minLength: 0)
                SCIcon("chevR", size: 16, color: Theme.ink4)
            }
            .padding(16)
            .cardSurface(20)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }
}
