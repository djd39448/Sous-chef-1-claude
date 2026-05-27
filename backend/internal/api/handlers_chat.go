package api

import (
	"errors"
	"log"
	"net/http"
	"strings"

	"souschef/internal/auth"
	"souschef/internal/openai"
	"souschef/internal/store"
)

// handleMessage serves POST /api/kitchen/message — the streaming kitchen chat.
// It follows the five-step flow in contract/api-spec.md: resolve conversation,
// persist the user message, build the request, stream the reply, persist the
// assistant message. Tool calls are executed server-side and not streamed.
func (s *Server) handleMessage(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID := auth.UserID(ctx)

	var body struct {
		Content        string `json:"content"`
		ConversationID *int   `json:"conversationId"`
		// Optional local-anchored Monday string (YYYY-MM-DD). Used by the
		// create_meal_plan and create_shopping_list tools when the model
		// calls them. Falls back to currentWeekStart() (UTC) when blank.
		// See contract/api-spec.md → "Week anchoring".
		WeekStartDate string `json:"weekStartDate"`
	}
	if err := decodeJSON(r, &body); err != nil || strings.TrimSpace(body.Content) == "" {
		writeError(w, http.StatusBadRequest, "content is required")
		return
	}

	// 1. Resolve the conversation.
	var conv store.Conversation
	var err error
	if body.ConversationID != nil {
		conv, err = s.store.GetConversationByID(ctx, *body.ConversationID)
		if errors.Is(err, store.ErrNotFound) || (err == nil && conv.UserID != userID) {
			writeError(w, http.StatusNotFound, "conversation not found")
			return
		}
		if err != nil {
			writeError(w, http.StatusInternalServerError, "internal error")
			return
		}
	} else {
		conv, err = s.store.GetMostRecentConversation(ctx, userID)
		if errors.Is(err, store.ErrNotFound) {
			conv, err = s.store.CreateConversation(ctx, userID, "Kitchen Chat")
		}
		if err != nil {
			writeError(w, http.StatusInternalServerError, "internal error")
			return
		}
	}

	// 2. Persist the user message.
	userMsg, err := s.store.InsertMessage(ctx, conv.ID, "user", body.Content)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	_ = s.store.TouchConversation(ctx, conv.ID)

	// 2a. If the conversation still has the generic placeholder title,
	// auto-name it after the user's first message. Mirrors the original
	// web app: first 6 words, truncated to 40 chars with a trailing
	// ellipsis when needed. Quiet on failure — a stale title isn't
	// fatal.
	if isDefaultConversationTitle(conv.Title) {
		if newTitle := autoConversationTitle(body.Content); newTitle != "" {
			_ = s.store.UpdateConversationTitle(ctx, conv.ID, newTitle)
		}
	}

	// 3. Build the request: system prompt, recent history, then the new message.
	ingredients, _ := s.store.GetIngredientMemory(ctx, userID)
	cookbook, _ := s.store.ListCookbook(ctx, userID)
	history, _ := s.store.GetRecentMessages(ctx, conv.ID, userMsg.ID, 10)

	msgs := []openai.Message{{Role: "system", Content: buildChatSystemPrompt(ingredients, cookbook)}}
	for _, m := range history {
		msgs = append(msgs, openai.Message{Role: m.Role, Content: m.Content})
	}
	msgs = append(msgs, openai.Message{Role: "user", Content: body.Content})

	// 4. Stream the completion.
	sse, ok := newSSE(w)
	if !ok {
		return
	}
	maxTokens := 2048
	result, err := s.ai.ChatStream(ctx, openai.ChatParams{
		Model:               "gpt-4.1",
		Messages:            msgs,
		Tools:               openai.ChatTools(),
		MaxCompletionTokens: &maxTokens,
	}, func(delta string) {
		sse.send(map[string]string{"content": delta})
	})
	if err != nil {
		sse.sendError(err.Error())
		return
	}

	// Execute tool calls server-side; they are not surfaced in the stream.
	weekStart := strings.TrimSpace(body.WeekStartDate)
	for _, tc := range result.ToolCalls {
		if err := s.executeChatTool(ctx, userID, tc, weekStart); err != nil {
			log.Printf("chat tool %q: %v", tc.Name, err)
		}
	}

	// 5. Persist the assistant message.
	if _, err := s.store.InsertMessage(ctx, conv.ID, "assistant", result.Content); err != nil {
		log.Printf("persist assistant message: %v", err)
	}
	_ = s.store.TouchConversation(ctx, conv.ID)

	sse.send(map[string]bool{"done": true})
}

// isDefaultConversationTitle returns true for the placeholder titles
// that auto-rename is allowed to overwrite. Keeps user-customized
// titles untouched — once a real title exists, we never auto-rename.
func isDefaultConversationTitle(title string) bool {
	t := strings.TrimSpace(title)
	return t == "" || t == "Kitchen Chat" || t == "New Chat" || t == "Chat"
}

// autoConversationTitle picks a short title from the user's first
// message: first 6 words, truncated to 40 chars with an ellipsis when
// needed. Mirrors the original web app's `updateConversationTitle`
// snippet (server/routes.ts).
func autoConversationTitle(content string) string {
	words := strings.Fields(strings.TrimSpace(content))
	if len(words) > 6 {
		words = words[:6]
	}
	t := strings.Join(words, " ")
	if t == "" {
		return ""
	}
	if len(t) > 40 {
		// Use rune-safe truncation so we don't cut a multibyte char.
		runes := []rune(t)
		if len(runes) > 37 {
			t = string(runes[:37]) + "..."
		} else {
			t = t[:37] + "..."
		}
	}
	return t
}
