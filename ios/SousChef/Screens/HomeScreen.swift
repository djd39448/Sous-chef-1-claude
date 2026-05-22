import SwiftUI

/// The Home tab — tonight's dinner, the week strip, a chat shortcut, the pantry.
struct HomeScreen: View {
    var goToTab: (Tab) -> Void = { _ in }
    var openRecipe: () -> Void = {}

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
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TUESDAY · MAY 26")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(0.2)
                    .foregroundStyle(Theme.ink3)
                Text("Evening, Dave.")
                    .font(Theme.display(30, weight: .medium))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
            Text("D")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.terraDeep)
                .frame(width: 40, height: 40)
                .background(Theme.terraSoft)
                .clipShape(Circle())
        }
        .padding(.top, 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    // MARK: Tonight

    private var tonightCard: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.elev)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay { FoodImage(url: Food.carbonara) }
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
                Text("Pasta Carbonara")
                    .font(Theme.display(24, weight: .medium))
                    .foregroundStyle(Theme.ink)
                tonightMeta
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

    private var tonightMeta: some View {
        HStack(spacing: 14) {
            metaItem("clock", "30 min")
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

    // MARK: This week

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
                    ForEach(Samples.weekStrip) { day in
                        dayCard(day)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }

    private func dayCard(_ day: WeekDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(day.abbrev.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .opacity(0.7)
            Text(day.meal)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .frame(height: 30, alignment: .top)
                .padding(.top, 8)
        }
        .foregroundStyle(day.today ? Theme.bg : Theme.ink)
        .frame(width: 88, alignment: .leading)
        .padding(12)
        .background(day.today ? Theme.ink : Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.hairline2, lineWidth: day.today ? 0 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if day.done {
                SCIcon("check", size: 9, color: .white, weight: .bold)
                    .frame(width: 14, height: 14)
                    .background(Theme.sage)
                    .clipShape(Circle())
                    .padding(10)
            }
        }
    }

    // MARK: Chat shortcut

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

    // MARK: Pantry

    private var pantrySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("In Your Pantry")
                    .font(Theme.display(20, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("14 items")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.bottom, 8)

            FlowLayout(spacing: 8) {
                ForEach(Samples.pantry) { item in
                    HStack(spacing: 7) {
                        CatDot(category: item.category)
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
