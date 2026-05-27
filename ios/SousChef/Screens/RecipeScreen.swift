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
    /// Image URL set during this view's lifetime — overrides whatever was
    /// stored on the source row. Lets the user see the new image
    /// immediately without a refetch.
    @State private var generatedImageURL: String?
    @State private var isGeneratingImage = false
    @State private var showingChat = false
    /// Only used when `source` is `.cookbook` — opens the
    /// CookbookEditScreen sheet from the pencil button.
    @State private var showingEdit = false
    /// Holds the latest CookbookRecipe after an edit so we can render
    /// the fresh title/content without bouncing through the parent.
    @State private var editedRecipe: CookbookRecipe?

    var body: some View {
        ZStack(alignment: .bottom) {
            scrollContent
            // The floating pill at the bottom — tap to open the per-recipe
            // chat sheet. Only shown for meal-plan recipes because the
            // /recipe-message endpoint requires a dayId.
            if case .mealPlanDay = source {
                floatingPill
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
        .background(Theme.bg)
        .overlay(alignment: .top) { topButtons }
        .task { await load() }
        .sheet(isPresented: $showingChat) {
            if case .mealPlanDay(let day) = source {
                RecipeChatSheet(day: day) { changed in
                    // User edited the meal — refresh the recipe with the
                    // new mealName from the server.
                    if changed {
                        Task {
                            await streamGenerate(dayId: day.id)
                        }
                    }
                }
                .environment(auth)
            }
        }
        .sheet(isPresented: $showingEdit) {
            if case .cookbook(let recipe) = source {
                CookbookEditScreen(recipe: editedRecipe ?? recipe) { updated in
                    // Reflect the freshly-saved row in-place. Title +
                    // content come from the response; thumbnailUrl is
                    // preserved.
                    editedRecipe = updated
                    content = updated.content
                }
                .environment(auth)
            }
        }
    }

    private var floatingPill: some View {
        Button { showingChat = true } label: {
            HStack(spacing: 10) {
                SCIcon("sparkle", size: 16, color: Theme.butter, weight: .bold)
                Text("Ask about this recipe or swap it…")
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 0)
                SCIcon("send", size: 16, color: .white)
                    .frame(width: 36, height: 36)
                    .background(Theme.terra)
                    .clipShape(Circle())
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .frame(height: 56)
            .background(Theme.ink)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.35), radius: 15, y: 12)
        }
        .buttonStyle(.plain)
    }

    private var client: APIClient {
        APIClient(baseURL: AppConfig.backendBaseURL, auth: auth)
    }

    // MARK: Derived

    private var title: String {
        switch source {
        case .mealPlanDay(let day): return day.mealName
        case .cookbook(let recipe):
            // Prefer the locally-edited copy so the title updates the
            // moment Save lands, without waiting for the parent to
            // refetch the cookbook list.
            return editedRecipe?.title ?? recipe.title
        }
    }

    /// The image URL to display on the hero. Prefers an image generated
    /// during this session; falls back to whatever the server has stored
    /// on the row. Nil → render the "Tap to generate" placeholder.
    private var currentImageURL: String? {
        if let local = generatedImageURL { return local }
        switch source {
        case .mealPlanDay(let day): return day.imageUrl
        case .cookbook(let recipe): return recipe.thumbnailUrl
        }
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
        var eventsReceived = 0
        var decodeFailures = 0
        var contentDeltas = 0
        print("🔵 streamGenerate START dayId=\(dayId)")
        do {
            for try await event in client.stream(
                path: "/api/kitchen/generate-recipe/\(dayId)",
                body: [String: String]()
            ) {
                eventsReceived += 1
                // Tolerate occasional non-JSON events (heartbeats, partial
                // frames) — skip them rather than abort the stream.
                guard let chunk = try? decoder.decode(
                    RecipeChunk.self, from: Data(event.data.utf8)
                ) else {
                    decodeFailures += 1
                    print("🔴 decode failed for event #\(eventsReceived): \(event.data.prefix(120))")
                    continue
                }
                if let delta = chunk.content {
                    contentDeltas += 1
                    content += delta
                } else if let prompt = chunk.imagePrompt, chunk.done == true {
                    imagePrompt = prompt
                    print("🟢 done event received — imagePrompt set")
                    break
                } else if let err = chunk.error {
                    errorMessage = err
                    print("🔴 server error event: \(err)")
                }
            }
        } catch let e as APIError where e.isBenignCancellation {
            // View went away — leave content/errorMessage as-is and bail.
            print("🟡 benign cancellation — eventsReceived=\(eventsReceived) contentLen=\(content.count)")
            isStreaming = false
            return
        } catch {
            print("🔴 stream error: \(error.localizedDescription) eventsReceived=\(eventsReceived)")
            errorMessage = error.localizedDescription
        }
        isStreaming = false

        print("🔵 streamGenerate END dayId=\(dayId) events=\(eventsReceived) deltas=\(contentDeltas) decodeFails=\(decodeFailures) contentLen=\(content.count) errorMessage=\(errorMessage ?? "<nil>")")

        // The stream closed cleanly but the model gave us nothing —
        // surface a real "try again" affordance instead of leaving the
        // user staring at "No recipe content yet."
        if content.isEmpty && errorMessage == nil {
            errorMessage = "The recipe didn't come through. Tap retry to try again."
        }

        // Auto-save the freshly-generated recipe to the cookbook. The
        // bookmark icon flips to filled as a confirmation; the user
        // can still delete from the Cookbook tab if they don't want
        // it. Skip when the stream errored or returned no content.
        // Silent on failure — a network blip during auto-save would
        // otherwise paint a red error card over a freshly-rendered
        // recipe, which reads as broken.
        if !content.isEmpty && errorMessage == nil && !saved {
            await saveToCookbook(surfaceErrors: false)
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
                // Bottom clearance — needs to be tall enough that the
                // floating "Ask…" pill doesn't cover the last instruction.
                Color.clear.frame(height: 110)
            }
        }
        // Intentionally NOT .ignoresSafeArea(edges: .top): the hero used to
        // bleed under the Dynamic Island, but on scroll the title text and
        // the "AI GENERATED" pill ended up on top of the system clock. The
        // recipe screen now respects the safe area so nothing collides.
    }

    private var hero: some View {
        Rectangle()
            .fill(Theme.elev)
            .frame(height: 380)
            .overlay {
                // Persisted image (from /regenerate-image) is the only
                // image source now — no more keyword stock photos. If
                // nothing is stored, show a Tap-to-generate placeholder.
                RecipeImage(
                    url: currentImageURL,
                    onGenerate: { Task { await regenerateImage() } },
                    isGenerating: isGeneratingImage
                )
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
                // Gradient sits ABOVE the RecipeImage button — without
                // this, taps on the sparkle placeholder land on the
                // gradient instead of triggering regeneration.
                .allowsHitTesting(false)
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
                    // Same hit-testing fix as the gradient — the badge
                    // must not steal taps from the placeholder.
                    .allowsHitTesting(false)
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

    /// Line-by-line Markdown renderer. `AttributedString` with `.full` parses
    /// block elements but then collapses everything into one paragraph with
    /// no headings or bullets — useless for a recipe. Instead we walk the
    /// content, render each block at a time with the right font/leading, and
    /// stitch them together. Inline markdown (bold/italic/links) still works
    /// because each line passes through `AttributedString(markdown:)`.
    private var renderedContent: AttributedString {
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

        var out = AttributedString()
        let lines = body.components(separatedBy: "\n")
        for (idx, raw) in lines.enumerated() {
            let line = raw
            let isLast = idx == lines.count - 1
            let suffix = isLast ? "" : "\n"

            // ## Heading — bold, larger, with a blank line above (except at start).
            if line.hasPrefix("## ") {
                let title = String(line.dropFirst(3))
                if idx > 0 { out += AttributedString("\n") }
                var attr = AttributedString(title)
                attr.font = Theme.display(18, weight: .medium)
                attr.foregroundColor = Theme.ink
                out += attr
                out += AttributedString(suffix)
                continue
            }

            // - Bullet list item — replace dash with a real bullet.
            if line.hasPrefix("- ") {
                let rest = String(line.dropFirst(2))
                out += AttributedString("•  ")
                out += inlineMarkdown(rest)
                out += AttributedString(suffix)
                continue
            }

            // 1. / 2. / ... Numbered list item — keep the number, render rest.
            if let dotIdx = line.firstIndex(of: "."),
               line.distance(from: line.startIndex, to: dotIdx) <= 3,
               Int(line[line.startIndex..<dotIdx]) != nil,
               line.distance(from: dotIdx, to: line.endIndex) > 2,
               line[line.index(after: dotIdx)] == " " {
                let number = String(line[line.startIndex...dotIdx])
                let rest = String(line[line.index(dotIdx, offsetBy: 2)...])
                var prefix = AttributedString("\(number)  ")
                prefix.font = Theme.sans(15, weight: .semibold)
                prefix.foregroundColor = Theme.ink
                out += prefix
                out += inlineMarkdown(rest)
                out += AttributedString(suffix)
                continue
            }

            // Plain paragraph (or the Prep/Cook/Serves line with **bold**).
            out += inlineMarkdown(line)
            out += AttributedString(suffix)
        }
        return out
    }

    /// Parse one line as inline-only markdown (bold, italic, links). Falls
    /// back to a plain string if parsing fails.
    private func inlineMarkdown(_ s: String) -> AttributedString {
        if let attr = try? AttributedString(
            markdown: s,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return attr
        }
        return AttributedString(s)
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
        // The "regenerate photo" button (swap icon) sits next to the
        // bookmark and is the manual retry for an image the user
        // doesn't like. Backend now generates photos in the background
        // on plan-create / regen-days / single-day swap (see
        // backend/internal/api/images.go), so the hero almost always
        // has an image by the time the user gets here — this button is
        // for "I want a different photo," not "fill the blank."
        // For .cookbook source we also show an edit pencil that opens
        // the CookbookEditScreen.
        HStack {
            heroButton("chevL", action: onClose)
            Spacer()
            HStack(spacing: 8) {
                if case .cookbook = source {
                    heroButton("edit", color: Theme.ink) {
                        showingEdit = true
                    }
                }
                heroButton("swap", color: Theme.ink) {
                    Task { await regenerateImage() }
                }
                .disabled(isGeneratingImage || promptForImage.isEmpty)
                .opacity(isGeneratingImage ? 0.6 : 1)
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

    /// The prompt we send to `/api/kitchen/regenerate-image`. Prefer the
    /// model-emitted `imagePrompt` (set when the recipe stream finishes),
    /// fall back to the cookbook recipe's stored prompt, and finally to the
    /// recipe title — better than nothing for casual taps.
    private var promptForImage: String {
        if let p = imagePrompt, !p.isEmpty { return p }
        if case .cookbook(let recipe) = source,
           let p = recipe.imagePrompt, !p.isEmpty {
            return p
        }
        return title
    }

    @MainActor
    private func regenerateImage() async {
        guard !isGeneratingImage, !promptForImage.isEmpty else { return }
        isGeneratingImage = true
        defer { isGeneratingImage = false }

        // Tell the backend WHICH row to persist on so the image survives
        // app restarts. The view's source decides which id to send.
        struct Body: Encodable {
            let prompt: String
            let dayId: Int?
            let recipeId: Int?
        }
        struct Response: Decodable { let imageUrl: String }

        let body: Body = {
            switch source {
            case .mealPlanDay(let day):
                return Body(prompt: promptForImage, dayId: day.id, recipeId: nil)
            case .cookbook(let recipe):
                return Body(prompt: promptForImage, dayId: nil, recipeId: recipe.id)
            }
        }()

        do {
            let resp: Response = try await client.post(
                "/api/kitchen/regenerate-image", body
            )
            withAnimation(.easeInOut(duration: 0.25)) {
                generatedImageURL = resp.imageUrl
            }
        } catch let e as APIError where e.isBenignCancellation {
            // Quietly ignore — view went away.
        } catch {
            errorMessage = "Image: \(error.localizedDescription)"
        }
    }

    /// Persist the current recipe to the cookbook via
    /// `POST /api/kitchen/cookbook`. Called automatically when
    /// `streamGenerate` finishes with content, and manually when the
    /// user taps the bookmark icon. `surfaceErrors` is true for the
    /// manual path (errors land in the recipe error card) and false
    /// for auto-save (we don't want a network blip on first view to
    /// scare the user with a red banner over their recipe).
    @MainActor
    private func saveToCookbook(surfaceErrors: Bool = true) async {
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
            if surfaceErrors {
                errorMessage = "Couldn't save: \(error.localizedDescription)"
            }
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

}

// MARK: - Recipe chat sheet

/// Per-recipe chat — the modal panel that the floating "Ask…" pill opens.
/// Talks to `POST /api/kitchen/recipe-message` (SSE). If the model calls
/// the `update_meal` tool, the response includes `updatedMeal` and the
/// sheet calls `onDismiss(true)` so the parent can refresh the recipe.
struct RecipeChatSheet: View {
    let day: MealPlanDay
    var onDismiss: (_ mealChanged: Bool) -> Void = { _ in }

    @Environment(AuthModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [Msg] = []
    @State private var draft: String = ""
    @State private var streamingContent: String = ""
    @State private var isStreaming = false
    @State private var lastError: String?
    @State private var mealChanged = false

    private struct Msg: Identifiable {
        let id = UUID()
        let role: String   // "user" | "assistant"
        var text: String
    }

    private var client: APIClient {
        APIClient(baseURL: AppConfig.backendBaseURL, auth: auth)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            messageList
            composer
        }
        .background(Theme.bg)
        .interactiveDismissDisabled(isStreaming)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Text(day.mealName)
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer()
                Button {
                    onDismiss(mealChanged)
                    dismiss()
                } label: {
                    SCIcon("close", size: 18, color: Theme.ink)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Hairline()
        }
    }

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if messages.isEmpty && !isStreaming {
                        emptyHint
                    }
                    ForEach(messages) { m in
                        bubble(role: m.role, text: m.text, streaming: false)
                    }
                    if isStreaming || !streamingContent.isEmpty {
                        bubble(role: "assistant", text: streamingContent, streaming: isStreaming)
                    }
                    if let err = lastError {
                        Text(err)
                            .font(Theme.sans(13))
                            .foregroundStyle(.red)
                    }
                    Color.clear.frame(height: 1).id("BOTTOM")
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .onChange(of: streamingContent) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("BOTTOM", anchor: .bottom)
                }
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("BOTTOM", anchor: .bottom)
                }
            }
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Edit or swap this meal.")
                .font(Theme.display(18, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text("Try: \"swap with sheet-pan chicken\", \"make it vegetarian\", or ask a question about an ingredient.")
                .font(Theme.sans(13))
                .foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func bubble(role: String, text: String, streaming: Bool) -> some View {
        if role == "user" {
            HStack {
                Spacer(minLength: 40)
                Text(text)
                    .font(Theme.sans(14.5))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Theme.ink)
                    .clipShape(UnevenRoundedRectangle(cornerRadii: .init(
                        topLeading: 18, bottomLeading: 18, bottomTrailing: 6, topTrailing: 18)))
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                Text(text.isEmpty && streaming ? " " : text)
                    .font(Theme.sans(14.5))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Theme.card)
            .clipShape(UnevenRoundedRectangle(cornerRadii: .init(
                topLeading: 18, bottomLeading: 6, bottomTrailing: 18, topTrailing: 18)))
            .overlay(
                UnevenRoundedRectangle(cornerRadii: .init(
                    topLeading: 18, bottomLeading: 6, bottomTrailing: 18, topTrailing: 18))
                    .strokeBorder(Theme.hairline2, lineWidth: 1)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 40)
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 8) {
                TextField("Edit or ask about \(day.mealName)…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.ink)
                    .padding(.leading, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .textInputAutocapitalization(.sentences)
                    .onSubmit { if canSend { Task { await send() } } }
                    .disabled(isStreaming)
                Button { Task { await send() } } label: {
                    SCIcon("send", size: 16, color: .white)
                        .frame(width: 36, height: 36)
                        .background(canSend ? Theme.terra : Theme.ink4)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .padding(.trailing, 6)
            }
            .frame(minHeight: 56)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Theme.hairline2, lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .background(Theme.bg)
    }

    private var canSend: Bool {
        !isStreaming && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Send + stream

    private struct SendBody: Encodable {
        let content: String
        let dayId: Int
        let mealName: String
        let dayName: String
    }

    private struct ChatChunk: Decodable {
        let content: String?
        let done: Bool?
        let error: String?
        let updatedMeal: UpdatedMeal?
        struct UpdatedMeal: Decodable {
            let mealName: String
            let notes: String?
        }
    }

    @MainActor
    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(Msg(role: "user", text: text))
        draft = ""
        lastError = nil
        streamingContent = ""
        isStreaming = true

        let body = SendBody(
            content: text,
            dayId: day.id,
            mealName: day.mealName,
            dayName: DateUtil.dayName(day.dayOfWeek)
        )
        let decoder = JSONDecoder()
        do {
            for try await event in client.stream(path: "/api/kitchen/recipe-message", body: body) {
                guard let chunk = try? decoder.decode(
                    ChatChunk.self, from: Data(event.data.utf8)
                ) else { continue }
                if let delta = chunk.content {
                    streamingContent += delta
                } else if let err = chunk.error {
                    lastError = err
                } else if chunk.done == true {
                    if chunk.updatedMeal != nil {
                        mealChanged = true
                    }
                    break
                }
            }
        } catch let e as APIError where e.isBenignCancellation {
            // No-op
        } catch {
            lastError = error.localizedDescription
        }

        if !streamingContent.isEmpty {
            messages.append(Msg(role: "assistant", text: streamingContent))
        }
        streamingContent = ""
        isStreaming = false

        // If the meal was changed, close the sheet immediately so the
        // parent can re-stream the recipe with the new mealName.
        if mealChanged {
            onDismiss(true)
            dismiss()
        }
    }
}
