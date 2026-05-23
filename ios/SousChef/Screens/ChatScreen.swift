import SwiftUI

/// The Chat tab — conversational assistant with streaming replies.
///
/// Wired to:
///   - `GET  /api/kitchen/conversation` — load the user's default
///     conversation with its history.
///   - `POST /api/kitchen/message` — send a message and read the SSE
///     stream (`{content:…}` chunks, terminated by `{done:true}`).
///
/// While the assistant reply streams, the in-progress text is rendered
/// in a live bubble with a blinking cursor; on `done` the conversation
/// is refetched so the persisted assistant message (and any
/// tool-call side effects) become visible. On `error` the in-progress
/// content is dropped and an inline error appears.
struct ChatScreen: View {
    @Environment(AuthModel.self) private var auth

    @State private var conversation: ConversationWithMessages?
    @State private var draft = ""
    @State private var streamingContent = ""
    @State private var isStreaming = false
    @State private var loadState: LoadState = .loading
    @State private var lastError: String?

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
    }

    private var client: APIClient {
        APIClient(baseURL: AppConfig.backendBaseURL, auth: auth)
    }

    // MARK: Load history

    private func load() async {
        loadState = .loading
        do {
            let c: ConversationWithMessages = try await client.get("/api/kitchen/conversation")
            conversation = c
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                IconButton(icon: "chevL")
                Spacer()
                VStack(spacing: 1) {
                    HStack(spacing: 6) {
                        SCIcon("sparkle", size: 12, color: Theme.terraDeep, weight: .bold)
                            .frame(width: 22, height: 22)
                            .background(Theme.terraSoft)
                            .clipShape(Circle())
                        Text("Sous Chef")
                            .font(Theme.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    Text(isStreaming ? "● Thinking…" : "● Online")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isStreaming ? Theme.terra : Theme.sage)
                }
                Spacer()
                IconButton(icon: "settings")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            Hairline()
        }
        .background(Theme.bg)
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
                TextField("Message Sous Chef…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.ink)
                    .padding(.leading, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            .frame(height: 56)
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

        let body = SendBody(content: text, conversationId: conversation?.id)
        let decoder = JSONDecoder()
        do {
            for try await event in client.stream(path: "/api/kitchen/message", body: body) {
                let chunk = try decoder.decode(StreamChunk.self, from: Data(event.data.utf8))
                if let delta = chunk.content {
                    streamingContent += delta
                } else if let err = chunk.error {
                    lastError = err
                } else if chunk.done == true {
                    break
                }
            }
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
