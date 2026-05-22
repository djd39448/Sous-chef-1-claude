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
	for _, tc := range result.ToolCalls {
		if err := s.executeChatTool(ctx, userID, tc); err != nil {
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
