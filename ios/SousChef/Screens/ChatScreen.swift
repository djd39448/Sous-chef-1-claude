import SwiftUI

/// The Chat tab — conversational assistant with a composer.
struct ChatScreen: View {
    @State private var messages = Samples.chat
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            messagesList
            composer
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
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
                    Text("● Online")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.sage)
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
        ScrollView {
            VStack(spacing: 12) {
                Text("Today · 6:42 PM")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.3)
                    .foregroundStyle(Theme.ink3)
                    .padding(.bottom, 4)

                ForEach(messages) { message in
                    bubble(for: message)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func bubble(for message: ChatMessage) -> some View {
        switch message.role {
        case .tool:
            HStack(spacing: 6) {
                SCIcon("check", size: 12, color: Theme.sage, weight: .bold)
                Text(message.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.sageSoft)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline2, lineWidth: 1))
            .frame(maxWidth: .infinity)
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(Theme.sans(14.5))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Theme.ink)
                    .clipShape(UnevenRoundedRectangle(cornerRadii: .init(
                        topLeading: 18, bottomLeading: 18, bottomTrailing: 6, topTrailing: 18)))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 4) {
                Text("SOUS CHEF")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.ink3)
                    .padding(.leading, 14)
                HStack(alignment: .top, spacing: 0) {
                    Text(message.text)
                        .font(Theme.sans(14.5))
                        .foregroundStyle(Theme.ink)
                    if message.streaming { BlinkingCursor().padding(.leading, 2) }
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

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 0) {
            Hairline()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Chip(label: "Plan my week", icon: "sparkle")
                    Chip(label: "Make a shopping list")
                    Chip(label: "What can I make tonight?")
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 10)
            .padding(.bottom, 10)

            HStack(spacing: 8) {
                TextField("", text: $draft,
                          prompt: Text("Message Sous Chef…").foregroundColor(Theme.ink3))
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.ink)
                    .padding(.leading, 16)
                    .padding(.vertical, 6)
                Button {
                    if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                        messages.append(ChatMessage(role: .user, text: draft))
                        draft = ""
                    }
                } label: {
                    SCIcon("send", size: 16, color: .white)
                        .frame(width: 36, height: 36)
                        .background(Theme.terra)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
            }
            .frame(minHeight: 44)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.hairline2, lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Theme.bg)
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
