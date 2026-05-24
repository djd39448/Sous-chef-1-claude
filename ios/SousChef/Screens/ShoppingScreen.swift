import SwiftUI

/// The Shopping tab — checkable list grouped by category, with a
/// multi-week list picker and manual add/edit/delete per item.
///
/// Wired to:
///   - `GET    /api/kitchen/shopping-lists`          (sidebar listing)
///   - `GET    /api/kitchen/shopping-list`           (most recent on
///     first launch)
///   - `GET    /api/kitchen/shopping-list/{ident}`   (pick a specific
///     list — id or weekStart)
///   - `POST   /api/kitchen/shopping-item`           (manual add)
///   - `PATCH  /api/kitchen/shopping-item/{id}`      (toggle checked)
///   - `PUT    /api/kitchen/shopping-item/{id}`      (edit name/qty/cat)
///   - `DELETE /api/kitchen/shopping-item/{id}`      (single delete)
///   - `DELETE /api/kitchen/shopping-items/checked`  (clear checked)
struct ShoppingScreen: View {
    @Environment(AuthModel.self) private var auth

    @State private var list: ShoppingListWithItems?
    @State private var allLists: [ShoppingList] = []
    @State private var loadState: LoadState = .loading
    @State private var showListPicker = false
    @State private var showItemEditor = false
    /// When set, the item editor opens pre-filled with this item;
    /// otherwise it's "add new."
    @State private var editingItem: ShoppingItem?

    private enum LoadState {
        case loading
        case loaded
        case empty
        case failed(String)
    }

    private let categoryOrder = [
        "produce", "meat", "seafood", "dairy",
        "bakery", "frozen", "pantry", "beverages", "other",
    ]
    private let categoryLabels: [String: String] = [
        "produce": "Produce",
        "meat": "Meat",
        "seafood": "Seafood",
        "dairy": "Dairy & Eggs",
        "bakery": "Bakery",
        "frozen": "Frozen",
        "pantry": "Pantry",
        "beverages": "Beverages",
        "other": "Other",
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                NavBar(
                    largeTitle: "Shopping",
                    leading: AnyView(IconButton(icon: "filter") { showListPicker = true }),
                    trailing: AnyView(IconButton(icon: "plus", color: Theme.terra) {
                        editingItem = nil
                        showItemEditor = true
                    })
                )
                content
            }
        }
        .background(Theme.bg)
        .tabBarClearance()
        .navigationBarHidden(true)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showListPicker) {
            ShoppingListPickerSheet(
                lists: allLists,
                currentID: list?.id,
                onSelect: { identifier in
                    showListPicker = false
                    Task { await loadList(identifier: identifier) }
                }
            )
            .environment(auth)
        }
        .sheet(isPresented: $showItemEditor) {
            ShoppingItemEditorSheet(
                editing: editingItem,
                listID: list?.id,
                onSaved: {
                    Task { await load() }
                }
            )
            .environment(auth)
        }
    }

    // MARK: Loading

    private var client: APIClient {
        APIClient(baseURL: AppConfig.backendBaseURL, auth: auth)
    }

    private func load() async {
        loadState = .loading
        do {
            async let listsTask: [ShoppingList] = client.get("/api/kitchen/shopping-lists")
            async let currentTask: ShoppingListWithItems? = client.get("/api/kitchen/shopping-list")
            allLists = (try? await listsTask) ?? []
            if let fetched = try await currentTask {
                list = fetched
                loadState = .loaded
            } else {
                list = nil
                loadState = .empty
            }
        } catch let e as APIError where e.isBenignCancellation {
            return
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Load a specific list by identifier (id digits or weekStart date).
    /// Used by the list picker when the user switches weeks.
    @MainActor
    private func loadList(identifier: String) async {
        loadState = .loading
        do {
            if let fetched: ShoppingListWithItems = try await client.get(
                "/api/kitchen/shopping-list/\(identifier)"
            ) {
                list = fetched
                loadState = .loaded
            } else {
                list = nil
                loadState = .empty
            }
        } catch let e as APIError where e.isBenignCancellation {
            return
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            ProgressView().tint(Theme.terra).padding(.top, 40)
        case .failed(let message):
            errorCard(message: message)
        case .empty:
            emptyCard
        case .loaded:
            VStack(spacing: 0) {
                progressBlock
                sectionsList
                generatedNote
            }
        }
    }

    // MARK: Progress

    private var progressBlock: some View {
        let total = list?.items.count ?? 0
        let checked = list?.items.filter { $0.checked == 1 }.count ?? 0
        let progress = total == 0 ? 0.0 : Double(checked) / Double(total)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                (Text("\(checked)").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.ink)
                 + Text(" of \(total) checked off").font(.system(size: 13, weight: .medium)).foregroundColor(Theme.ink2))
                Spacer()
                Button { Task { await clearChecked() } } label: {
                    Text("Clear checked")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.terra)
                }
                .buttonStyle(.plain)
                .disabled(checked == 0)
                .opacity(checked == 0 ? 0.45 : 1)
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
            ForEach(groupedItems, id: \.category) { group in
                sectionView(category: group.category, items: group.items)
            }
        }
        .padding(.horizontal, 16)
    }

    private struct CategoryGroup {
        let category: String
        let items: [ShoppingItem]
    }

    private var groupedItems: [CategoryGroup] {
        guard let list = list else { return [] }
        let grouped = Dictionary(grouping: list.items, by: { $0.category.lowercased() })
        let known = categoryOrder.compactMap { cat -> CategoryGroup? in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return CategoryGroup(category: cat, items: items)
        }
        // Any unexpected categories the server emits, appended at the end.
        let knownKeys = Set(categoryOrder)
        let extras = grouped
            .filter { !knownKeys.contains($0.key) && !$0.value.isEmpty }
            .map { CategoryGroup(category: $0.key, items: $0.value) }
            .sorted { $0.category < $1.category }
        return known + extras
    }

    private func sectionView(category: String, items: [ShoppingItem]) -> some View {
        let label = categoryLabels[category] ?? category.capitalized
        let done = items.filter { $0.checked == 1 }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                CatDot(category: category, size: 9)
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.ink2)
                Text("\(done)/\(items.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.ink4)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    itemRow(item)
                    if index < items.count - 1 { Hairline() }
                }
            }
            .cardSurface(18)
        }
    }

    private func itemRow(_ item: ShoppingItem) -> some View {
        Button { Task { await toggle(item) } } label: {
            HStack(spacing: 14) {
                ZStack {
                    if item.checked == 1 {
                        Circle().fill(Theme.sage)
                        SCIcon("check", size: 13, color: .white, weight: .bold)
                    } else {
                        Circle().strokeBorder(Theme.ink4, lineWidth: 1.5)
                    }
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .strikethrough(item.checked == 1)
                    if let q = item.quantity, !q.isEmpty {
                        Text(q)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink3)
                    }
                }
                .opacity(item.checked == 1 ? 0.45 : 1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editingItem = item
                showItemEditor = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                Task { await deleteItem(item) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Permanently remove an item from the list. Optimistic — yanks it
    /// locally before the request returns; restores on failure.
    @MainActor
    private func deleteItem(_ item: ShoppingItem) async {
        guard let listIndex = list?.items.firstIndex(where: { $0.id == item.id }) else { return }
        let removed = list!.items.remove(at: listIndex)
        do {
            try await client.delete("/api/kitchen/shopping-item/\(item.id)")
        } catch {
            // Restore.
            list?.items.insert(removed, at: min(listIndex, list?.items.count ?? 0))
        }
    }

    // MARK: Toggle + clear

    private struct CheckedBody: Encodable { let checked: Bool }

    @MainActor
    private func toggle(_ item: ShoppingItem) async {
        guard let listIndex = list?.items.firstIndex(where: { $0.id == item.id }) else { return }
        let previous = list!.items[listIndex].checked
        let next = previous == 1 ? 0 : 1
        // Optimistic local update.
        list!.items[listIndex].checked = next
        do {
            let _: ShoppingItem = try await client.patch(
                "/api/kitchen/shopping-item/\(item.id)",
                CheckedBody(checked: next == 1)
            )
        } catch {
            // Revert on failure.
            if let i = list?.items.firstIndex(where: { $0.id == item.id }) {
                list!.items[i].checked = previous
            }
        }
    }

    @MainActor
    private func clearChecked() async {
        guard list != nil else { return }
        let beforeItems = list!.items
        list!.items.removeAll { $0.checked == 1 }
        do {
            try await client.delete("/api/kitchen/shopping-items/checked")
        } catch {
            list!.items = beforeItems
        }
    }

    // MARK: Empty / error / footer

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No shopping list yet.")
                .font(Theme.display(20, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text("Ask Sous Chef to build one from your plan.")
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
            Text("Couldn't load your shopping list.")
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

    private var generatedNote: some View {
        Group {
            if let list = list, list.weekStartDate != nil {
                HStack(spacing: 10) {
                    SCIcon("sparkle", size: 14, color: Theme.terraDeep, weight: .bold)
                    Text("Generated from your plan for \(DateUtil.weekRangeString(weekStart: list.weekStartDate!).replacingOccurrences(of: " · This week", with: ""))")
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
    }
}

// MARK: - List picker

/// Sheet listing all of the user's shopping lists. Tap one to switch
/// the Shopping tab to that list. Mirrors the original web app's
/// "Past Lists" picker.
struct ShoppingListPickerSheet: View {
    let lists: [ShoppingList]
    let currentID: Int?
    var onSelect: (_ identifier: String) -> Void = { _ in }

    @Environment(AuthModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if lists.isEmpty {
                    Text("No shopping lists yet.")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.ink3)
                        .padding(.top, 60)
                } else {
                    VStack(spacing: 0) {
                        ForEach(lists) { l in
                            Button {
                                onSelect("\(l.id)")
                            } label: { row(l) }
                            .buttonStyle(.plain)
                            Hairline()
                        }
                    }
                }
            }
            .background(Theme.bg)
            .navigationTitle("Past Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ l: ShoppingList) -> some View {
        let isCurrent = l.id == currentID
        return HStack(alignment: .top, spacing: 10) {
            SCIcon("cart", size: 16, color: isCurrent ? Theme.terra : Theme.sage)
                .frame(width: 28, height: 28)
                .background(isCurrent ? Theme.terraSoft : Theme.elev)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(l.name.isEmpty ? "Shopping List" : l.name)
                    .font(Theme.sans(14, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(Theme.ink)
                if let wk = l.weekStartDate {
                    Text(DateUtil.weekRangeString(weekStart: wk)
                        .replacingOccurrences(of: " · This week", with: " · This week"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ink3)
                } else {
                    Text(relativeCreated(l.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ink3)
                }
            }
            Spacer(minLength: 0)
            if isCurrent {
                SCIcon("check", size: 14, color: Theme.terra)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isCurrent ? Theme.terraSoft.opacity(0.3) : Color.clear)
    }

    private func relativeCreated(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Item editor

/// Sheet for adding a new shopping item or editing an existing one.
/// On save fires either `POST /api/kitchen/shopping-item` (add) or
/// `PUT /api/kitchen/shopping-item/{id}` (edit) and dismisses.
struct ShoppingItemEditorSheet: View {
    let editing: ShoppingItem?
    /// The list to add into when creating new items. Sent as
    /// `shoppingListId` so the server doesn't have to guess.
    let listID: Int?
    var onSaved: () -> Void = {}

    @Environment(AuthModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var quantity: String = ""
    @State private var category: String = "other"
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Same set as the Shopping list — keep in sync.
    private let categories: [(key: String, label: String)] = [
        ("produce", "Produce"),
        ("meat", "Meat"),
        ("seafood", "Seafood"),
        ("dairy", "Dairy & Eggs"),
        ("bakery", "Bakery"),
        ("frozen", "Frozen"),
        ("pantry", "Pantry"),
        ("beverages", "Beverages"),
        ("other", "Other"),
    ]

    private var client: APIClient {
        APIClient(baseURL: AppConfig.backendBaseURL, auth: auth)
    }

    private var isAdd: Bool { editing == nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("NAME", placeholder: "Bell peppers", text: $name)
                    field("QUANTITY (OPTIONAL)", placeholder: "2 lb", text: $quantity)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CATEGORY")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(Theme.ink3)
                        Picker("Category", selection: $category) {
                            ForEach(categories, id: \.key) { c in
                                Text(c.label).tag(c.key)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 8)
                        .frame(height: 40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline2, lineWidth: 1))
                    }
                    if let err = errorMessage {
                        Text(err)
                            .font(Theme.sans(13))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Theme.bg)
            .navigationTitle(isAdd ? "Add Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { seed() }
        .interactiveDismissDisabled(isSaving)
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Theme.ink3)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(Theme.sans(15))
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline2, lineWidth: 1))
        }
    }

    private func seed() {
        if let editing {
            name = editing.name
            quantity = editing.quantity ?? ""
            category = editing.category.lowercased()
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        let nameT = name.trimmingCharacters(in: .whitespaces)
        guard !nameT.isEmpty else { return }
        let qtyT = quantity.trimmingCharacters(in: .whitespaces)
        let qty: String? = qtyT.isEmpty ? nil : qtyT

        do {
            if let editing {
                struct PutBody: Encodable {
                    let name: String
                    let quantity: String?
                    let category: String
                }
                let _: ShoppingItem = try await client.put(
                    "/api/kitchen/shopping-item/\(editing.id)",
                    PutBody(name: nameT, quantity: qty, category: category)
                )
            } else {
                struct PostBody: Encodable {
                    let name: String
                    let quantity: String?
                    let category: String
                    let shoppingListId: Int?
                }
                let _: ShoppingItem = try await client.post(
                    "/api/kitchen/shopping-item",
                    PostBody(name: nameT, quantity: qty, category: category, shoppingListId: listID)
                )
            }
            onSaved()
            dismiss()
        } catch let e as APIError where e.isBenignCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
