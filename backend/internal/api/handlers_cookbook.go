package api

import (
	"net/http"
	"strings"

	"souschef/internal/auth"
)

// handleGetIngredients serves GET /api/kitchen/ingredients.
func (s *Server) handleGetIngredients(w http.ResponseWriter, r *http.Request) {
	list, err := s.store.GetIngredientMemory(r.Context(), auth.UserID(r.Context()))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, list)
}

// handleListCookbook serves GET /api/kitchen/cookbook.
func (s *Server) handleListCookbook(w http.ResponseWriter, r *http.Request) {
	list, err := s.store.ListCookbook(r.Context(), auth.UserID(r.Context()))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, list)
}

// handleGetCookbookRecipe serves GET /api/kitchen/cookbook/{id}.
func (s *Server) handleGetCookbookRecipe(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	id, ok := pathInt(r, "id")
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid recipe id")
		return
	}
	recipe, err := s.store.GetCookbookRecipe(ctx, id)
	if writeStoreErr(w, err, "recipe not found") {
		return
	}
	if recipe.UserID != auth.UserID(ctx) {
		writeError(w, http.StatusForbidden, "forbidden")
		return
	}
	writeJSON(w, http.StatusOK, recipe)
}

// handleCreateCookbookRecipe serves POST /api/kitchen/cookbook.
func (s *Server) handleCreateCookbookRecipe(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Title       string  `json:"title"`
		Content     string  `json:"content"`
		ImagePrompt *string `json:"imagePrompt"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if strings.TrimSpace(body.Title) == "" || strings.TrimSpace(body.Content) == "" {
		writeError(w, http.StatusBadRequest, "title and content are required")
		return
	}
	recipe, err := s.store.CreateCookbookRecipe(r.Context(), auth.UserID(r.Context()),
		body.Title, body.Content, body.ImagePrompt)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, recipe)
}

// handleDeleteCookbookRecipe serves DELETE /api/kitchen/cookbook/{id}.
func (s *Server) handleDeleteCookbookRecipe(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	id, ok := pathInt(r, "id")
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid recipe id")
		return
	}
	recipe, err := s.store.GetCookbookRecipe(ctx, id)
	if writeStoreErr(w, err, "recipe not found") {
		return
	}
	if recipe.UserID != auth.UserID(ctx) {
		writeError(w, http.StatusForbidden, "forbidden")
		return
	}
	if err := s.store.DeleteCookbookRecipe(ctx, id); err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// handleRegenerateImage serves POST /api/kitchen/regenerate-image.
func (s *Server) handleRegenerateImage(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Prompt string `json:"prompt"`
	}
	if err := decodeJSON(r, &body); err != nil || strings.TrimSpace(body.Prompt) == "" {
		writeError(w, http.StatusBadRequest, "prompt is required")
		return
	}
	b64, err := s.ai.GenerateImage(r.Context(), body.Prompt)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "image generation failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"imageUrl": "data:image/png;base64," + b64,
	})
}
