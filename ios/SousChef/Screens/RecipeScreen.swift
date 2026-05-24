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
    @State private var generatedImage: UIImage?
    @State private var isGeneratingImage = false
    @State private var showingChat = false

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
                // Generated image (from regenerate-image) takes precedence
                // over the stock-photo lookup — the lookup is only a
                // fallback while the user hasn't asked for a real photo yet.
                if let generatedImage {
                    Image(uiImage: generatedImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    FoodImage(url: heroImage)
                }
                if isGeneratingImage {
                    Color.black.opacity(0.45)
                    VStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Generating photo…")
                            .font(Theme.sans(13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
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
                heroButton("photo") {
                    Task { await regenerateImage() }
                }
                .disabled(isGeneratingImage || isStreaming || promptForImage.isEmpty)
                .opacity(promptForImage.isEmpty ? 0.6 : 1)
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
        struct Body: Encodable { let prompt: String }
        struct Response: Decodable { let imageUrl: String }
        do {
            let resp: Response = try await client.post(
                "/api/kitchen/regenerate-image",
                Body(prompt: promptForImage)
            )
            // The server emits a "data:image/png;base64,<b64>" URL.
            // Decode it into a UIImage and replace the hero.
            if let img = decodeDataURL(resp.imageUrl) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    generatedImage = img
                }
            } else {
                errorMessage = "Got an image but couldn't read it."
            }
        } catch let e as APIError where e.isBenignCancellation {
            // Quietly ignore — view went away.
        } catch {
            errorMessage = "Image: \(error.localizedDescription)"
        }
    }

    private func decodeDataURL(_ s: String) -> UIImage? {
        guard let comma = s.firstIndex(of: ","),
              let data = Data(base64Encoded: String(s[s.index(after: comma)...])) else {
            return nil
        }
        return UIImage(data: data)
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
