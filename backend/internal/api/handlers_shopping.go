package api

import (
	"context"
	"encoding/json"
	"errors"
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
func (s *Server) handleGenerateShoppingList(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID := auth.UserID(ctx)

	mealNames := "general weekly meals"
	var weekStart *string
	var mealPlanID *int
	if plan, err := s.store.GetMostRecentMealPlan(ctx, userID); err == nil {
		if days, err := s.store.GetMealPlanDays(ctx, plan.ID); err == nil {
			names := make([]string, 0, len(days))
			for _, d := range days {
				if strings.TrimSpace(d.MealName) != "" {
					names = append(names, d.MealName)
				}
			}
			if len(names) > 0 {
				mealNames = strings.Join(names, ", ")
			}
		}
		ws := plan.WeekStartDate
		weekStart = &ws
		id := plan.ID
		mealPlanID = &id
	}

	existing := "none"
	ingredients, _ := s.store.GetIngredientMemory(ctx, userID)
	if names := ingredientNames(ingredients); len(names) > 0 {
		existing = strings.Join(names, ", ")
	}

	items := s.generateShoppingItems(ctx, mealNames, existing)
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

// generateShoppingItems asks the model for a shopping list and parses it. It
// returns nil on any failure, leaving the caller to use the fallback list.
func (s *Server) generateShoppingItems(ctx context.Context, mealNames, existing string) []genShoppingItem {
	user := shoppingGenUserPrompt
	user = strings.ReplaceAll(user, "<mealNames>", mealNames)
	user = strings.ReplaceAll(user, "<existingIngredients>", existing)

	maxTokens := 1024
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
