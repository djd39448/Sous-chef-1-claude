package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"souschef/internal/auth"
	"souschef/internal/openai"
	"souschef/internal/store"
)

// handleGetShoppingList serves GET /api/kitchen/shopping-list — the most
// recent list with its items, or null.
func (s *Server) handleGetShoppingList(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	list, err := s.store.GetMostRecentShoppingList(ctx, auth.UserID(ctx))
	if errors.Is(err, store.ErrNotFound) {
		writeJSON(w, http.StatusOK, nil)
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	s.writeShoppingListWithItems(ctx, w, list)
}

// handleListShoppingLists serves GET /api/kitchen/shopping-lists.
func (s *Server) handleListShoppingLists(w http.ResponseWriter, r *http.Request) {
	lists, err := s.store.ListShoppingLists(r.Context(), auth.UserID(r.Context()))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, lists)
}

// handleGetShoppingListByIdentifier serves
// GET /api/kitchen/shopping-list/{identifier}: an all-digit identifier is a
// list id, anything else is a week-start date.
func (s *Server) handleGetShoppingListByIdentifier(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID := auth.UserID(ctx)
	identifier := r.PathValue("identifier")

	var list store.ShoppingList
	var err error
	if isAllDigits(identifier) {
		id, _ := strconv.Atoi(identifier)
		list, err = s.store.GetShoppingListByID(ctx, userID, id)
	} else {
		list, err = s.store.GetShoppingListByWeek(ctx, userID, identifier)
	}
	if errors.Is(err, store.ErrNotFound) {
		writeJSON(w, http.StatusOK, nil)
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	s.writeShoppingListWithItems(ctx, w, list)
}

// handleCreateShoppingItem serves POST /api/kitchen/shopping-item —
// add a single manually-entered item. If `shoppingListId` is omitted
// the item lands on the user's most-recent list; if no list exists
// yet a 400 is returned.
func (s *Server) handleCreateShoppingItem(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID := auth.UserID(ctx)

	var body struct {
		ShoppingListID *int    `json:"shoppingListId"`
		Name           string  `json:"name"`
		Quantity       *string `json:"quantity"`
		Category       string  `json:"category"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	name := strings.TrimSpace(body.Name)
	if name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	category := strings.TrimSpace(body.Category)
	if category == "" {
		category = "other"
	}

	// Resolve the target list. Either the caller specified one (auth-checked)
	// or we use the user's most-recent.
	var listID int
	if body.ShoppingListID != nil {
		list, err := s.store.GetShoppingListByID(ctx, userID, *body.ShoppingListID)
		if writeStoreErr(w, err, "shopping list not found") {
			return
		}
		listID = list.ID
	} else {
		list, err := s.store.GetMostRecentShoppingList(ctx, userID)
		if errors.Is(err, store.ErrNotFound) {
			writeError(w, http.StatusBadRequest, "no shopping list yet — generate one first")
			return
		}
		if err != nil {
			writeError(w, http.StatusInternalServerError, "internal error")
			return
		}
		listID = list.ID
	}

	// Normalize quantity — empty string → nil to keep the column clean.
	var qty *string
	if body.Quantity != nil {
		trimmed := strings.TrimSpace(*body.Quantity)
		if trimmed != "" {
			qty = &trimmed
		}
	}

	item, err := s.store.InsertShoppingItem(ctx, listID, name, qty, category)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, item)
}

// handleUpdateShoppingItem serves PUT /api/kitchen/shopping-item/{id} —
// partial edit of name / quantity / category. (Toggling `checked`
// stays on the PATCH endpoint to preserve existing iOS callers.)
func (s *Server) handleUpdateShoppingItem(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	id, ok := pathInt(r, "id")
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid item id")
		return
	}
	_, owner, err := s.store.GetShoppingItem(ctx, id)
	if writeStoreErr(w, err, "shopping item not found") {
		return
	}
	if owner != auth.UserID(ctx) {
		writeError(w, http.StatusForbidden, "forbidden")
		return
	}

	var body struct {
		Name     *string `json:"name"`
		Quantity *string `json:"quantity"`
		Category *string `json:"category"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if body.Name != nil {
		trimmed := strings.TrimSpace(*body.Name)
		if trimmed == "" {
			writeError(w, http.StatusBadRequest, "name cannot be empty")
			return
		}
		body.Name = &trimmed
	}
	if body.Category != nil {
		trimmed := strings.TrimSpace(*body.Category)
		if trimmed == "" {
			body.Category = nil
		} else {
			body.Category = &trimmed
		}
	}

	updated, err := s.store.UpdateShoppingItem(ctx, id, store.ShoppingItemUpdate{
		Name:     body.Name,
		Quantity: body.Quantity,
		Category: body.Category,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, updated)
}

// handleDeleteShoppingItem serves DELETE /api/kitchen/shopping-item/{id}.
func (s *Server) handleDeleteShoppingItem(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	id, ok := pathInt(r, "id")
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid item id")
		return
	}
	_, owner, err := s.store.GetShoppingItem(ctx, id)
	if writeStoreErr(w, err, "shopping item not found") {
		return
	}
	if owner != auth.UserID(ctx) {
		writeError(w, http.StatusForbidden, "forbidden")
		return
	}
	if err := s.store.DeleteShoppingItem(ctx, id); err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// handlePatchShoppingItem serves PATCH /api/kitchen/shopping-item/{id}.
func (s *Server) handlePatchShoppingItem(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	id, ok := pathInt(r, "id")
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid item id")
		return
	}
	_, owner, err := s.store.GetShoppingItem(ctx, id)
	if writeStoreErr(w, err, "shopping item not found") {
		return
	}
	if owner != auth.UserID(ctx) {
		writeError(w, http.StatusForbidden, "forbidden")
		return
	}

	var body struct {
		Checked bool `json:"checked"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "checked is required")
		return
	}
	checked := 0
	if body.Checked {
		checked = 1
	}
	updated, err := s.store.SetShoppingItemChecked(ctx, id, checked)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, updated)
}

// handleClearCheckedItems serves DELETE /api/kitchen/shopping-items/checked.
func (s *Server) handleClearCheckedItems(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	list, err := s.store.GetMostRecentShoppingList(ctx, auth.UserID(ctx))
	if errors.Is(err, store.ErrNotFound) {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	if err := s.store.DeleteCheckedItems(ctx, list.ID); err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// handleGenerateShoppingList serves POST /api/kitchen/generate-shopping-list.
//
// Optional body: `{ "weekStartDate": "YYYY-MM-DD" }`. When present, the
// generated list buckets into that week (the user's local Monday, sent by
// the iOS client). When absent, falls back to the most-recent plan's
// week — preserves the original no-body behavior.
func (s *Server) handleGenerateShoppingList(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID := auth.UserID(ctx)

	var body struct {
		WeekStartDate string `json:"weekStartDate"`
	}
	// Empty body is fine — preserve the original no-body call shape.
	_ = decodeJSON(r, &body)
	clientWeek := strings.TrimSpace(body.WeekStartDate)

	var days []store.MealPlanDay
	var weekStart *string
	var mealPlanID *int
	if plan, err := s.store.GetMostRecentMealPlan(ctx, userID); err == nil {
		days, _ = s.store.GetMealPlanDays(ctx, plan.ID)
		ws := plan.WeekStartDate
		weekStart = &ws
		id := plan.ID
		mealPlanID = &id
	}
	// Client-supplied week wins — it's the user's local Monday, the one
	// the Plan tab is currently showing.
	if clientWeek != "" {
		weekStart = &clientWeek
	}

	existing := "none"
	ingredients, _ := s.store.GetIngredientMemory(ctx, userID)
	if names := ingredientNames(ingredients); len(names) > 0 {
		existing = strings.Join(names, ", ")
	}

	items := s.generateShoppingItems(ctx, days, existing)
	if len(items) == 0 {
		items = fallbackShoppingItems()
	}

	list, err := s.store.CreateShoppingList(ctx, userID, "Weekly Shopping", weekStart, mealPlanID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	created := make([]store.ShoppingItem, 0, len(items))
	for _, it := range items {
		item, err := s.store.InsertShoppingItem(ctx, list.ID, it.Name, it.Quantity, it.Category)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "internal error")
			return
		}
		created = append(created, item)
	}
	writeJSON(w, http.StatusOK, store.ShoppingListWithItems{ShoppingList: list, Items: created})
}

// writeShoppingListWithItems loads a list's items and writes the bundle.
func (s *Server) writeShoppingListWithItems(ctx context.Context, w http.ResponseWriter, list store.ShoppingList) {
	items, err := s.store.GetShoppingItems(ctx, list.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, store.ShoppingListWithItems{ShoppingList: list, Items: items})
}

// genShoppingItem is a plain shopping-list item, before it is persisted.
type genShoppingItem struct {
	Name     string
	Quantity *string
	Category string
}

// generateShoppingItems asks the model for a shopping list and parses it.
//
// Each day is rendered as a block: meal name + the full recipe Markdown
// when available, or a "(recipe not yet generated)" hint when the user
// hasn't opened that day's recipe screen yet. This lets the model
// enumerate real ingredients per recipe instead of inventing them from
// the meal name alone — Dave reported the old "names only" prompt
// produced lists with missing AND fabricated items.
//
// Returns nil on any failure, leaving the caller to use the fallback list.
func (s *Server) generateShoppingItems(ctx context.Context, days []store.MealPlanDay, existing string) []genShoppingItem {
	recipesBlock := buildShoppingRecipesBlock(days)

	user := shoppingGenUserPrompt
	user = strings.ReplaceAll(user, "<recipesBlock>", recipesBlock)
	user = strings.ReplaceAll(user, "<existingIngredients>", existing)

	// 3500 ≈ a generous ceiling for a 7-day deduped list with
	// quantities. The old 1024 cap routinely truncated the response.
	maxTokens := 3500
	content, err := s.ai.ChatJSON(ctx, openai.ChatParams{
		Model: "gpt-4.1",
		Messages: []openai.Message{
			{Role: "system", Content: shoppingGenSystemPrompt},
			{Role: "user", Content: user},
		},
		MaxCompletionTokens: &maxTokens,
	})
	if err != nil {
		return nil
	}
	return parseShoppingItemsJSON(content)
}

// buildShoppingRecipesBlock renders one block per meal-plan day for the
// shopping-list user prompt. Days with recipe_content get the full
// recipe Markdown so the model can enumerate real ingredients; days
// without get a "(recipe not yet generated)" marker so the model knows
// to be conservative for those.
func buildShoppingRecipesBlock(days []store.MealPlanDay) string {
	dayNames := []string{"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}
	if len(days) == 0 {
		return "(no meals planned — generate a general weekly shopping list)"
	}
	var b strings.Builder
	for i, d := range days {
		name := strings.TrimSpace(d.MealName)
		if name == "" {
			continue
		}
		dayLabel := ""
		if d.DayOfWeek >= 0 && d.DayOfWeek < len(dayNames) {
			dayLabel = " (" + dayNames[d.DayOfWeek] + ")"
		}
		fmt.Fprintf(&b, "--- Meal %d: %s%s ---\n", i+1, name, dayLabel)
		if d.RecipeContent != nil && strings.TrimSpace(*d.RecipeContent) != "" {
			b.WriteString(strings.TrimSpace(*d.RecipeContent))
			b.WriteString("\n\n")
		} else {
			b.WriteString("(recipe not yet generated — infer the most common standard ingredients for this dish, but be conservative)\n\n")
		}
	}
	return b.String()
}

// parseShoppingItemsJSON parses a model shopping-list response of the form
// {"items":[{"name","quantity","category"}]}.
func parseShoppingItemsJSON(raw string) []genShoppingItem {
	var obj struct {
		Items []struct {
			Name     string  `json:"name"`
			Quantity *string `json:"quantity"`
			Category string  `json:"category"`
		} `json:"items"`
	}
	if json.Unmarshal([]byte(raw), &obj) != nil {
		return nil
	}
	out := make([]genShoppingItem, 0, len(obj.Items))
	for _, it := range obj.Items {
		if strings.TrimSpace(it.Name) == "" {
			continue
		}
		category := it.Category
		if category == "" {
			category = "other"
		}
		quantity := it.Quantity
		if quantity != nil && strings.TrimSpace(*quantity) == "" {
			quantity = nil
		}
		out = append(out, genShoppingItem{Name: it.Name, Quantity: quantity, Category: category})
	}
	return out
}

// fallbackShoppingItems is the fixed list used when AI generation yields no
// items (contract/ai-behavior.md → "Shopping-list generation" fallback).
func fallbackShoppingItems() []genShoppingItem {
	raw := []struct{ name, quantity, category string }{
		{"Chicken breasts", "2 lbs", "meat"},
		{"Ground beef", "1 lb", "meat"},
		{"Onions", "3", "produce"},
		{"Garlic", "1 head", "produce"},
		{"Tomatoes", "4", "produce"},
		{"Pasta", "1 box", "pantry"},
		{"Rice", "2 lbs", "pantry"},
		{"Olive oil", "1 bottle", "pantry"},
	}
	out := make([]genShoppingItem, 0, len(raw))
	for _, it := range raw {
		quantity := it.quantity
		out = append(out, genShoppingItem{Name: it.name, Quantity: &quantity, Category: it.category})
	}
	return out
}
