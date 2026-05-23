import SwiftUI

// Recipe screens come from two sources: a meal-plan day (may need
// AI-generation streamed in) or a saved cookbook recipe (always has full
// content). `RecipeSource` keeps both paths inside one presentation.
enum RecipeSource: Identifiable {
    case mealPlanDay(MealPlanDay)
    case cookbook(CookbookRecipe)

    var id: String {
        switch self {
        case .mealPlanDay(let day): return "mpd-\(day.id)"
        case .cookbook(let recipe): return "cb-\(recipe.id)"
        }
    }
}

/// The full-screen recipe detail.
///
/// For a `.mealPlanDay`: if the day already has `recipeContent`, render
/// it; otherwise open `POST /api/kitchen/generate-recipe/{dayId}` and
/// stream the Markdown in live. On `done` the server also persists the
/// content + the image prompt on the day row.
///
/// For a `.cookbook` recipe: render the saved Markdown content — no
/// streaming needed.
struct RecipeScreen: View {
    let source: RecipeSource
    var onClose: () -> Void = {}

    @Environment(AuthModel.self) private var auth

    @State private var content: String = ""
    @State private var imagePrompt: String?
    @State private var isStreaming = false
    @State private var errorMessage: String?
    @State private var saved = false
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            scrollContent
            floatingPill
        }
        .background(Theme.bg)
        .overlay(alignment: .top) { topButtons }
        .task { await load() }
    }

    private var client: APIClient {
        APIClient(baseURL: AppConfig.backendBaseURL, auth: auth)
    }

    // MARK: Derived

    private var title: String {
        switch source {
        case .mealPlanDay(let day): return day.mealName
        case .cookbook(let recipe): return recipe.title
        }
    }

    private var heroImage: String {
        ImageLookup.url(for: title)
    }

    // MARK: Load

    private func load() async {
        switch source {
        case .cookbook(let recipe):
            // The recipe is already in the cookbook — start in the "saved"
            // state so the bookmark button reflects reality.
            content = recipe.content
            errorMessage = nil
            saved = true
            return
        case .mealPlanDay(let day):
            if let existing = day.recipeContent, !existing.isEmpty {
                content = existing
                return
            }
            await streamGenerate(dayId: day.id)
        }
    }

    private struct RecipeChunk: Decodable {
        let content: String?
        let imagePrompt: String?
        let done: Bool?
        let error: String?
    }

    @MainActor
    private func streamGenerate(dayId: Int) async {
        isStreaming = true
        content = ""
        errorMessage = nil
        let decoder = JSONDecoder()
        do {
            for try await event in client.stream(
                path: "/api/kitchen/generate-recipe/\(dayId)",
                body: [String: String]()
            ) {
                // Tolerate occasional non-JSON events (heartbeats, partial
                // frames) — skip them rather than abort the stream.
                guard let chunk = try? decoder.decode(
                    RecipeChunk.self, from: Data(event.data.utf8)
                ) else { continue }
                if let delta = chunk.content {
                    content += delta
                } else if let prompt = chunk.imagePrompt, chunk.done == true {
                    imagePrompt = prompt
                    break
                } else if let err = chunk.error {
                    errorMessage = err
                }
            }
        } catch let e as APIError where e.isBenignCancellation {
            // View went away — leave content/errorMessage as-is and bail.
            isStreaming = false
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isStreaming = false

        // The stream closed cleanly but the model gave us nothing — surface
        // a real "try again" affordance instead of leaving the user staring
        // at "No recipe content yet."
        if content.isEmpty && errorMessage == nil {
            errorMessage = "The recipe didn't come through. Tap retry to try again."
        }
    }

    // MARK: Scroll content

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                titleBlock
                if let errorMessage {
                    errorCard(errorMessage)
                }
                recipeBody
                Color.clear.frame(height: 130)   // clearance for the floating pill
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private var hero: some View {
        Rectangle()
            .fill(Theme.elev)
            .frame(height: 380)
            .overlay { FoodImage(url: heroImage) }
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
            .overlay(alignment: .bottomLeading) {
                if case .mealPlanDay = source {
                    HStack(spacing: 6) {
                        SCIcon("sparkle", size: 11, color: Theme.terraDeep, weight: .bold)
                        Text(isStreaming ? "GENERATING…" : "AI GENERATED")
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
            }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Theme.display(32, weight: .medium))
                .foregroundStyle(Theme.ink)
                .tracking(-1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, -8)
        .padding(.bottom, 12)
    }

    private var recipeBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            if content.isEmpty && isStreaming {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.terra)
                    Text("Cooking up your recipe…")
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.ink3)
                }
            } else if content.isEmpty {
                Text("No recipe content yet.")
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.ink3)
            } else {
                Text(renderedContent)
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 20)
    }

    /// Inline Markdown — bold / italic / links render; block elements like
    /// headings and lists pass through as plain (still readable) text. A
    /// proper structured renderer (Ingredients + Instructions cards from
    /// the design) is a follow-up.
    private var renderedContent: AttributedString {
        // Drop the leading "# Title" line since we render the title above.
        let body: String = {
            var s = content
            if s.hasPrefix("# ") {
                if let nl = s.firstIndex(of: "\n") {
                    s = String(s[s.index(after: nl)...])
                    while s.hasPrefix("\n") { s.removeFirst() }
                }
            }
            return s
        }()
        if let attr = try? AttributedString(
            markdown: body,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return attr
        }
        return AttributedString(body)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SCIcon("close", size: 14, color: .white)
                    .frame(width: 28, height: 28)
                    .background(.red)
                    .clipShape(Circle())
                Text(message)
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
            // Retry only applies to streaming meal-plan recipes — cookbook
            // recipes are already fully resolved on the server.
            if case .mealPlanDay(let day) = source {
                Button {
                    Task { await streamGenerate(dayId: day.id) }
                } label: {
                    HStack(spacing: 6) {
                        SCIcon("sparkle", size: 14, color: .white)
                        Text("Try again").font(Theme.sans(13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Theme.terra)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isStreaming)
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline2, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: Top buttons

    private var topButtons: some View {
        HStack {
            heroButton("chevL", action: onClose)
            Spacer()
            HStack(spacing: 8) {
                heroButton(saved ? "bookmarkF" : "bookmark",
                           color: saved ? Theme.terra : Theme.ink) {
                    Task { await saveToCookbook() }
                }
                .disabled(isSaving || saved || content.isEmpty || isStreaming)
                .opacity(content.isEmpty || isStreaming ? 0.6 : 1)
            }
        }
        .padding(.horizontal, 14)
    }

    /// Persist the current recipe to the cookbook via
    /// `POST /api/kitchen/cookbook`. Only the meal-plan-day source path can
    /// actually trigger this — cookbook recipes start `saved == true` so the
    /// button is disabled, and the `.disabled` modifier above also blocks
    /// re-saves while one is in flight or while a stream is still running.
    @MainActor
    private func saveToCookbook() async {
        guard !saved, !content.isEmpty, !isSaving else { return }
        isSaving = true
        saveError = nil
        struct Body: Encodable {
            let title: String
            let content: String
            let imagePrompt: String?
        }
        let body = Body(title: title, content: content, imagePrompt: imagePrompt)
        do {
            let _: CookbookRecipe = try await client.post("/api/kitchen/cookbook", body)
            withAnimation { saved = true }
        } catch let e as APIError where e.isBenignCancellation {
            // No-op — the view went away mid-save.
        } catch {
            saveError = error.localizedDescription
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
        isSaving = false
    }

    private func heroButton(_ icon: String,
                            color: Color = Theme.ink,
                            action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            SCIcon(icon, size: 18, color: color)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.92))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Floating pill (placeholder — /recipe-message wires in a later pass)

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
