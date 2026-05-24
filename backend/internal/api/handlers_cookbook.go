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
//
// Body: `{ prompt, dayId?, recipeId? }`. When `dayId` is set, the
// resulting `data:image/png;base64,…` URL is persisted on the
// `meal_plan_days` row; when `recipeId` is set, it's persisted on the
// `cookbook_recipes` row. With neither, the URL is returned but not
// stored — kept for backward compatibility, though the iOS client now
// always supplies a target so the image sticks with the recipe.
func (s *Server) handleRegenerateImage(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID := auth.UserID(ctx)

	var body struct {
		Prompt   string `json:"prompt"`
		DayID    *int   `json:"dayId"`
		RecipeID *int   `json:"recipeId"`
	}
	if err := decodeJSON(r, &body); err != nil || strings.TrimSpace(body.Prompt) == "" {
		writeError(w, http.StatusBadRequest, "prompt is required")
		return
	}

	// Authorize the target row before burning an image-API call.
	if body.DayID != nil {
		_, owner, err := s.store.GetMealPlanDay(ctx, *body.DayID)
		if writeStoreErr(w, err, "meal-plan day not found") {
			return
		}
		if owner != userID {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
	}
	if body.RecipeID != nil {
		recipe, err := s.store.GetCookbookRecipe(ctx, *body.RecipeID)
		if writeStoreErr(w, err, "recipe not found") {
			return
		}
		if recipe.UserID != userID {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
	}

	b64, err := s.ai.GenerateImage(ctx, body.Prompt)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "image generation failed")
		return
	}
	imageURL := "data:image/png;base64," + b64

	// Persist on whichever target the caller specified.
	if body.DayID != nil {
		if err := s.store.SetMealPlanDayImage(ctx, *body.DayID, imageURL); err != nil {
			writeError(w, http.StatusInternalServerError, "save image failed")
			return
		}
	}
	if body.RecipeID != nil {
		if err := s.store.SetCookbookImage(ctx, *body.RecipeID, imageURL); err != nil {
			writeError(w, http.StatusInternalServerError, "save image failed")
			return
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"imageUrl": imageURL,
	})
}
