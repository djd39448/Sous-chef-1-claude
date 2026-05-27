import SwiftUI

/// The Chat tab — conversational assistant with streaming replies and
/// multi-conversation history.
///
/// Wired to:
///   - `GET  /api/kitchen/conversations` — list past conversations
///     (sidebar).
///   - `GET  /api/kitchen/conversation` — most-recent conversation
///     (default on launch).
///   - `GET  /api/kitchen/conversation/{id}` — load one by id (when the
///     user picks a row in the sidebar).
///   - `POST /api/kitchen/conversation/new` — start a fresh chat.
///   - `POST /api/kitchen/message` — send a message, read the SSE
///     stream (`{content:…}` chunks, terminated by `{done:true}`).
///
/// The header shows the current conversation's title (auto-generated
/// from the first user message — see backend `autoConversationTitle`).
/// A history icon in the top-left opens a sheet listing all past
/// conversations with a "New Chat" button.
struct ChatScreen: View {
    @Environment(AuthModel.self) private var auth

    @State private var conversation: ConversationWithMessages?
    @State private var conversations: [Conversation] = []
    @State private var draft = ""
    @State private var streamingContent = ""
    @State private var isStreaming = false
    @State private var loadState: LoadState = .loading
    @State private var lastError: String?
    @State private var showHistory = false

    private enum LoadState { case loading, loaded, failed(String) }

    var body: some View {
        VStack(spacing: 0) {
            header
            messagesList
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
        .task { await load() }
        .sheet(isPresented: $showHistory) {
            ConversationHistorySheet(
                conversations: conversations,
                currentID: conversation?.id,
                onSelect: { id in
                    showHistory = false
                    Task { await loadConversation(id: id) }
                },
                onNewChat: {
                    showHistory = false
                    Task { await newConversation() }
                }
            )
            .environment(auth)
        }
    }

    private var client: APIClient {
        APIClient(baseURL: AppConfig.backendBaseURL, auth: auth)
    }

    // MARK: Load history

    /// Initial load: fetch the conversation list AND the most-recent
    /// conversation in parallel. The list drives the sidebar; the
    /// most-recent one is what the user sees on open.
    private func load() async {
        loadState = .loading
        do {
            async let listTask: [Conversation] = client.get("/api/kitchen/conversations")
            async let convTask: ConversationWithMessages = client.get("/api/kitchen/conversation")
            conversations = (try? await listTask) ?? []
            let c = try await convTask
            conversation = c
            loadState = .loaded
        } catch let e as APIError where e.isBenignCancellation {
            return
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Load one conversation by id — fires when the user picks a row in
    /// the history sheet. Refreshes the list at the same time so the
    /// chosen conversation can move to the top via updated_at.
    @MainActor
    private func loadConversation(id: Int) async {
        loadState = .loading
        do {
            async let listTask: [Conversation] = client.get("/api/kitchen/conversations")
            async let convTask: ConversationWithMessages = client.get("/api/kitchen/conversation/\(id)")
            conversations = (try? await listTask) ?? conversations
            let c = try await convTask
            conversation = c
            loadState = .loaded
        } catch let e as APIError where e.isBenignCancellation {
            return
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Create a fresh conversation and switch to it. Title starts as
    /// "Kitchen Chat" and is auto-renamed once the user sends a
    /// message.
    @MainActor
    private func newConversation() async {
        do {
            struct Empty: Encodable {}
            let conv: Conversation = try await client.post(
                "/api/kitchen/conversation/new", Empty()
            )
            // Empty message list — fresh conversation.
            conversation = ConversationWithMessages(
                id: conv.id, userId: conv.userId, title: conv.title,
                createdAt: conv.createdAt, updatedAt: conv.updatedAt,
                messages: []
            )
            // Refresh the sidebar so the new chat appears.
            if let list: [Conversation] = try? await client.get("/api/kitchen/conversations") {
                conversations = list
            }
            loadState = .loaded
        } catch let e as APIError where e.isBenignCancellation {
            return
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Header

    private var header: some View {
        // Top-left: history icon → opens the conversations sheet.
        // Center: current conversation title + status. Top-right: new-chat icon.
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Button { showHistory = true } label: {
                    SCIcon("filter", size: 18, color: Theme.ink)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                Spacer()
                VStack(spacing: 1) {
                    HStack(spacing: 6) {
                        SCIcon("sparkle", size: 12, color: Theme.terraDeep, weight: .bold)
                            .frame(width: 22, height: 22)
                            .background(Theme.terraSoft)
                            .clipShape(Circle())
                        Text(currentTitle)
                            .font(Theme.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                    Text(isStreaming ? "● Thinking…" : "● Online")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isStreaming ? Theme.terra : Theme.sage)
                }
                Spacer()
                Button { Task { await newConversation() } } label: {
                    SCIcon("plus", size: 18, color: Theme.terra)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 10)
            Hairline()
        }
        .background(Theme.bg)
    }

    /// Title shown in the header — prefers the loaded conversation's
    /// title; falls back to "Sous Chef" before the first load lands.
    private var currentTitle: String {
        if let t = conversation?.title, !t.isEmpty { return t }
        return "Sous Chef"
    }

    // MARK: Messages

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    switch loadState {
                    case .loading:
                        ProgressView().tint(Theme.terra).padding(.top, 40)
                    case .failed(let msg):
                        loadFailedCard(msg)
                    case .loaded:
                        if let c = conversation {
                            messageColumn(messages: c.messages)
                        }
                        // Anchor at the bottom so scrollTo can target it.
                        Color.clear
                            .frame(height: 1)
                            .id("BOTTOM")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 12)
            }
            .onChange(of: streamingContent) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("BOTTOM", anchor: .bottom)
                }
            }
            .onChange(of: conversation?.messages.count ?? 0) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("BOTTOM", anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func messageColumn(messages: [Message]) -> some View {
        if messages.isEmpty && !isStreaming {
            emptyState
        } else {
            // Real persisted messages.
            ForEach(messages) { m in
                bubble(role: m.role, text: m.content, streaming: false)
            }
            // The in-progress assistant reply (only while a stream is open).
            if isStreaming || !streamingContent.isEmpty {
                bubble(role: "assistant", text: streamingContent, streaming: isStreaming)
            }
            if let err = lastError {
                Text(err)
                    .font(Theme.sans(13))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Say hi to Sous Chef.")
                .font(Theme.display(20, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text("Tell it what you have in the fridge, ask for a quick dinner, or have it plan your week.")
                .font(Theme.sans(14))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
        .padding(.horizontal, 24)
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
            VStack(alignment: .leading, spacing: 4) {
                Text("SOUS CHEF")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.ink3)
                    .padding(.leading, 14)
                HStack(alignment: .top, spacing: 0) {
                    Text(text.isEmpty && streaming ? " " : text)
                        .font(Theme.sans(14.5))
                        .foregroundStyle(Theme.ink)
                    if streaming {
                        BlinkingCursor().padding(.leading, 2)
                    }
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 40)
        }
    }

    private func loadFailedCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn't load the chat.")
                .font(Theme.display(18, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(Theme.sans(13))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
            Button { Task { await load() } } label: {
                Text("Try again")
                    .font(Theme.sans(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 40)
                    .background(Theme.terra)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 40).padding(.horizontal, 24)
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 8) {
                TextField("Message Sous Chef…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.ink)
                    .padding(.leading, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
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
        let conversationId: Int?
        // The user's local Monday. The backend threads this into
        // create_meal_plan / create_shopping_list tool calls so chat-driven
        // plans/lists bucket into the same week the Plan tab is showing.
        // See contract/api-spec.md → "Week anchoring".
        let weekStartDate: String
    }

    private struct StreamChunk: Decodable {
        let content: String?
        let done: Bool?
        let error: String?
    }

    @MainActor
    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Optimistically show the user's bubble — assign a temporary id that
        // won't collide with server ids (negative).
        if var conv = conversation {
            let synthetic = Message(
                id: -Int(Date().timeIntervalSince1970 * 1000),
                conversationId: conv.id,
                role: "user",
                content: text,
                createdAt: Date()
            )
            conv = ConversationWithMessages(
                id: conv.id, userId: conv.userId, title: conv.title,
                createdAt: conv.createdAt, updatedAt: Date(),
                messages: conv.messages + [synthetic]
            )
            conversation = conv
        }
        draft = ""
        lastError = nil
        streamingContent = ""
        isStreaming = true

        let body = SendBody(
            content: text,
            conversationId: conversation?.id,
            weekStartDate: DateUtil.todaysMondayString()
        )
        let decoder = JSONDecoder()
        do {
            for try await event in client.stream(path: "/api/kitchen/message", body: body) {
                // Tolerate occasional non-JSON events (heartbeats, malformed
                // single frames) — skip them rather than abort the stream.
                guard let chunk = try? decoder.decode(
                    StreamChunk.self, from: Data(event.data.utf8)
                ) else { continue }
                if let delta = chunk.content {
                    streamingContent += delta
                } else if let err = chunk.error {
                    lastError = err
                } else if chunk.done == true {
                    break
                }
            }
        } catch let e as APIError where e.isBenignCancellation {
            // Stream torn down because the view went away — drop quietly.
        } catch {
            lastError = error.localizedDescription
        }
        isStreaming = false
        streamingContent = ""

        // The contract says: tool calls run server-side and the client
        // refetches affected resources after the stream ends. Re-loading
        // the conversation picks up the persisted assistant message; other
        // tabs refresh on their own next view.
        await load()
    }
}

private struct BlinkingCursor: View {
    @State private var visible = true
    var body: some View {
        Rectangle()
            .fill(Theme.ink)
            .frame(width: 8, height: 16)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

// MARK: - Conversation history sheet

/// Modal list of past conversations + a "New Chat" CTA. Mirrors the
/// sliding sidebar in the original web app. The current conversation
/// is highlighted; tapping a row swaps to that conversation; "New
/// Chat" creates one and switches.
struct ConversationHistorySheet: View {
    let conversations: [Conversation]
    let currentID: Int?
    var onSelect: (_ id: Int) -> Void = { _ in }
    var onNewChat: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Button(action: onNewChat) {
                        HStack(spacing: 10) {
                            SCIcon("plus", size: 16, color: .white)
                                .frame(width: 28, height: 28)
                                .background(Theme.terra)
                                .clipShape(Circle())
                            Text("New Chat")
                                .font(Theme.sans(15, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    Hairline()
                    if conversations.isEmpty {
                        Text("No conversations yet.")
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.ink3)
                            .padding(.top, 40)
                    } else {
                        ForEach(conversations) { conv in
                            Button { onSelect(conv.id) } label: {
                                row(conv)
                            }
                            .buttonStyle(.plain)
                            Hairline()
                        }
                    }
                }
            }
            .background(Theme.bg)
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ conv: Conversation) -> some View {
        let isCurrent = conv.id == currentID
        return HStack(alignment: .top, spacing: 10) {
            SCIcon("chat", size: 16, color: isCurrent ? Theme.terra : Theme.ink3)
                .frame(width: 28, height: 28)
                .background(isCurrent ? Theme.terraSoft : Theme.elev)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(conv.title.isEmpty ? "Untitled chat" : conv.title)
                    .font(Theme.sans(14, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(relativeUpdated(conv.updatedAt))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink3)
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

    private func relativeUpdated(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}
