import SwiftUI

// CookbookEditScreen — full-screen sheet for editing a saved recipe.
//
// Depends on:     APIClient, AuthModel, CookbookRecipe DTO,
//                 IngredientSuggestion DTO.
// Depended on by: RecipeScreen (when source is .cookbook — the user
//                 taps the edit pencil to open this).
// Why it exists:  port of /pages/cookbook-recipe.tsx in the original
//                 web app. The user edits the title and the markdown
//                 body; the ingredient helper adds well-formatted lines
//                 to save them retyping quantities + units. Talks to
//                 PUT /api/kitchen/cookbook/{id} on save and
//                 GET /api/kitchen/ingredient-suggestions for the
//                 helper's quick-add pills.
struct CookbookEditScreen: View {
    let recipe: CookbookRecipe
    /// Callback after a successful save — the parent uses this to
    /// refresh its local copy without a round-trip.
    var onSaved: (CookbookRecipe) -> Void = { _ in }

    @Environment(AuthModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var content: String = ""
    @State private var suggestions: [IngredientSuggestion] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var client: APIClient {
        APIClient(baseURL: AppConfig.backendBaseURL, auth: auth)
    }

    private var hasChanges: Bool {
        title.trimmingCharacters(in: .whitespaces) != recipe.title
            || content.trimmingCharacters(in: .whitespaces) != recipe.content
    }

    private var canSave: Bool {
        !isSaving && hasChanges
            && !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !content.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    titleField
                    IngredientHelper(suggestions: suggestions) { line in
                        insertIngredient(line)
                    }
                    contentField
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
            .navigationTitle("Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .onAppear {
            title = recipe.title
            content = recipe.content
            Task { await loadSuggestions() }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TITLE")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Theme.ink3)
            TextField("Recipe title", text: $title)
                .textFieldStyle(.plain)
                .font(Theme.sans(17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline2, lineWidth: 1))
        }
    }

    private var contentField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECIPE")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Theme.ink3)
            TextEditor(text: $content)
                .font(Theme.sans(14))
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 320)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline2, lineWidth: 1))
        }
    }

    private func insertIngredient(_ line: String) {
        // Append on its own line under the existing body, with a leading
        // bullet so it slots into the Ingredients section naturally.
        let prefix = content.hasSuffix("\n") || content.isEmpty ? "" : "\n"
        content = content + prefix + "- " + line
    }

    // MARK: API

    @MainActor
    private func loadSuggestions() async {
        do {
            let list: [IngredientSuggestion] = try await client.get("/api/kitchen/ingredient-suggestions")
            suggestions = list
        } catch {
            // Quiet — the helper degrades gracefully when there are no
            // suggestions. The quick-add row just hides.
            suggestions = []
        }
    }

    @MainActor
    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        struct Body: Encodable {
            let title: String
            let content: String
        }
        do {
            let updated: CookbookRecipe = try await client.put(
                "/api/kitchen/cookbook/\(recipe.id)",
                Body(
                    title: title.trimmingCharacters(in: .whitespaces),
                    content: content.trimmingCharacters(in: .whitespaces)
                )
            )
            onSaved(updated)
            dismiss()
        } catch let e as APIError where e.isBenignCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Ingredient helper

/// "Quick Add Ingredient" widget — mirrors the original web app's
/// `IngredientHelper`. Quantity dropdown + unit dropdown + name field +
/// "+" button assemble a formatted line and call `onInsert`. A row of
/// pills below offers quick-add suggestions from
/// `/api/kitchen/ingredient-suggestions`.
private struct IngredientHelper: View {
    let suggestions: [IngredientSuggestion]
    let onInsert: (String) -> Void

    @State private var quantity: String = "1"
    @State private var unit: String = "cup"
    @State private var name: String = ""

    /// Verbatim from the original
    /// (`COMMON_QUANTITIES` in cookbook-recipe.tsx).
    private let quantities = ["1/4", "1/3", "1/2", "2/3", "3/4", "1", "1.5", "2", "3", "4"]
    /// Same — `COMMON_UNITS`. (label, value pairs collapsed to one
    /// string since iOS Picker uses one item.)
    private let units = ["cup", "tbsp", "tsp", "oz", "lb", "each", "clove", "slice", "can", "pkg"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Add Ingredient")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Theme.ink3)
            HStack(spacing: 8) {
                Picker("", selection: $quantity) {
                    ForEach(quantities, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(width: 64)
                .padding(.horizontal, 4)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline2, lineWidth: 1))

                Picker("", selection: $unit) {
                    ForEach(units, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(width: 80)
                .padding(.horizontal, 4)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline2, lineWidth: 1))

                TextField("ingredient name", text: $name)
                    .textFieldStyle(.plain)
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline2, lineWidth: 1))
                    .submitLabel(.done)
                    .onSubmit { insert() }

                Button { insert() } label: {
                    SCIcon("plus", size: 14, color: .white)
                        .frame(width: 36, height: 36)
                        .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.ink4 : Theme.terra)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("Quick:")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.ink3)
                        ForEach(suggestions.prefix(8), id: \.canonicalName) { s in
                            Button {
                                onInsert("\(quantity) \(unit) \(s.displayName.isEmpty ? s.canonicalName : s.displayName)")
                            } label: {
                                Text(s.displayName.isEmpty ? s.canonicalName : s.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 10)
                                    .frame(height: 26)
                                    .background(Theme.card)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(Theme.hairline2, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Theme.elev.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func insert() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onInsert("\(quantity) \(unit) \(trimmed)")
        name = ""
    }
}
