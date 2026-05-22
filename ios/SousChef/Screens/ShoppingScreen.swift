import SwiftUI

/// The Shopping tab — checkable list grouped by category.
struct ShoppingScreen: View {
    @State private var sections = Samples.shoppingSections

    private var total: Int { sections.reduce(0) { $0 + $1.items.count } }
    private var checked: Int {
        sections.reduce(0) { $0 + $1.items.filter(\.checked).count }
    }
    private var progress: Double {
        total == 0 ? 0 : Double(checked) / Double(total)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                NavBar(
                    largeTitle: "Shopping",
                    leading: AnyView(IconButton(icon: "filter")),
                    trailing: AnyView(IconButton(icon: "plus", color: Theme.terra))
                )
                progressBlock
                sectionsList
                generatedNote
            }
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
    }

    // MARK: Progress

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                (Text("\(checked)").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.ink)
                 + Text(" of \(total) checked off").font(.system(size: 13, weight: .medium)).foregroundColor(Theme.ink2))
                Spacer()
                Button { clearChecked() } label: {
                    Text("Clear checked")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.terra)
                }
                .buttonStyle(.plain)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.elev)
                    Capsule().fill(Theme.sage)
                        .frame(width: geo.size.width * progress)
                        .animation(.easeInOut(duration: 0.2), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    // MARK: Sections

    private var sectionsList: some View {
        VStack(spacing: 20) {
            ForEach($sections) { $section in
                sectionView(section: $section)
            }
        }
        .padding(.horizontal, 16)
    }

    private func sectionView(section: Binding<ShoppingSection>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                CatDot(category: section.wrappedValue.category, size: 9)
                Text(section.wrappedValue.label.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.ink2)
                let done = section.wrappedValue.items.filter(\.checked).count
                Text("\(done)/\(section.wrappedValue.items.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.ink4)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                let lineItems = section.wrappedValue.items
                ForEach(lineItems.indices, id: \.self) { i in
                    itemRow(item: section.items[i])
                    if i < lineItems.count - 1 { Hairline() }
                }
            }
            .cardSurface(18)
        }
    }

    private func itemRow(item: Binding<ShoppingLine>) -> some View {
        Button {
            item.wrappedValue.checked.toggle()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    if item.wrappedValue.checked {
                        Circle().fill(Theme.sage)
                        SCIcon("check", size: 13, color: .white, weight: .bold)
                    } else {
                        Circle().strokeBorder(Theme.ink4, lineWidth: 1.5)
                    }
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.wrappedValue.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .strikethrough(item.wrappedValue.checked)
                    Text(item.wrappedValue.qty)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink3)
                }
                .opacity(item.wrappedValue.checked ? 0.45 : 1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func clearChecked() {
        for i in sections.indices {
            sections[i].items.removeAll(where: \.checked)
        }
    }

    // MARK: Generated note

    private var generatedNote: some View {
        HStack(spacing: 10) {
            SCIcon("sparkle", size: 14, color: Theme.terraDeep, weight: .bold)
            Text("Generated from your plan for May 25–31. We left out 7 items you already have.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.terraDeep)
                .lineSpacing(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.terraSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline2, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }
}
