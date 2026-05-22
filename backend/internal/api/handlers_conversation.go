package api

import (
	"errors"
	"net/http"

	"souschef/internal/auth"
	"souschef/internal/store"
)

// handleGetConversation serves GET /api/kitchen/conversation — the user's most
// recent conversation with its messages, creating one if they have none.
func (s *Server) handleGetConversation(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID := auth.UserID(ctx)

	conv, err := s.store.GetMostRecentConversation(ctx, userID)
	if errors.Is(err, store.ErrNotFound) {
		conv, err = s.store.CreateConversation(ctx, userID, "Kitchen Chat")
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	msgs, err := s.store.GetMessages(ctx, conv.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, store.ConversationWithMessages{Conversation: conv, Messages: msgs})
}

// handleListConversations serves GET /api/kitchen/conversations.
func (s *Server) handleListConversations(w http.ResponseWriter, r *http.Request) {
	list, err := s.store.ListConversations(r.Context(), auth.UserID(r.Context()))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, list)
}

// handleNewConversation serves POST /api/kitchen/conversation/new.
func (s *Server) handleNewConversation(w http.ResponseWriter, r *http.Request) {
	conv, err := s.store.CreateConversation(r.Context(), auth.UserID(r.Context()), "Kitchen Chat")
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, conv)
}

// handleGetConversationByID serves GET /api/kitchen/conversation/{id}.
func (s *Server) handleGetConversationByID(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	id, ok := pathInt(r, "id")
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid conversation id")
		return
	}

	conv, err := s.store.GetConversationByID(ctx, id)
	if writeStoreErr(w, err, "conversation not found") {
		return
	}
	if conv.UserID != auth.UserID(ctx) {
		writeError(w, http.StatusForbidden, "forbidden")
		return
	}

	msgs, err := s.store.GetMessages(ctx, conv.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, store.ConversationWithMessages{Conversation: conv, Messages: msgs})
}
