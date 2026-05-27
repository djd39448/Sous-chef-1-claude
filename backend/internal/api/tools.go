package api

import (
	"context"
	"encoding/json"
	"strings"
	"time"

	"souschef/internal/openai"
	"souschef/internal/store"
)

// executeChatTool dispatches a tool call the model made during the main chat.
// Per contract/ai-behavior.md these run silently — their effects are picked up
// when the client refetches resources after the stream ends.
//
// `weekStart` is the user's local Monday from the chat request body
// (empty when the client didn't send one). The create_meal_plan and
// create_shopping_list tools use it so plans/lists bucket into the same
// week the user sees on the Plan tab; fallback is the server's UTC Monday.
func (s *Server) executeChatTool(ctx context.Context, userID string, tc openai.ToolCall, weekStart string) error {
	switch tc.Name {
	case "update_ingredients":
		return s.toolUpdateIngredients(ctx, userID, tc.Arguments)
	case "create_meal_plan":
		return s.toolCreateMealPlan(ctx, userID, tc.Arguments, weekStart)
	case "create_shopping_list":
		return s.toolCreateShoppingList(ctx, userID, tc.Arguments, weekStart)
	case "save_recipe":
		return s.toolSaveRecipe(ctx, userID, tc.Arguments)
	default:
		return nil
	}
}

// toolQuantity is the { amount, unit } object the model passes in CFO tools.
type toolQuantity struct {
	Amount float64 `json:"amount"`
	Unit   string  `json:"unit"`
}

// quantityString renders a CFO quantity as free text ("2 lb"), or nil.
func quantityString(q *toolQuantity) *string {
	if q == nil {
		return nil
	}
	s := strings.TrimSpace(trimNum(q.Amount) + " " + q.Unit)
	if s == "" {
		return nil
	}
	return &s
}

// toolUpdateIngredients handles the update_ingredients tool: for each item it
// upserts an inventory-role CFO and the legacy ingredient_memory row, or marks
// both "out" / removed when the action is "remove".
func (s *Server) toolUpdateIngredients(ctx context.Context, userID, args string) error {
	var p struct {
		Ingredients []struct {
			CanonicalName string        `json:"canonical_name"`
			DisplayName   string        `json:"display_name"`
			Quantity      *toolQuantity `json:"quantity"`
			Category      string        `json:"category"`
			Status        string        `json:"status"`
			Action        string        `json:"action"`
		} `json:"ingredients"`
	}
	if err := json.Unmarshal([]byte(args), &p); err != nil {
		return err
	}

	for _, ing := range p.Ingredients {
		name := strings.ToLower(strings.TrimSpace(ing.CanonicalName))
		if name == "" {
			continue
		}

		if ing.Action == "remove" {
			if err := s.store.MarkFoodItemOut(ctx, userID, name); err != nil {
				return err
			}
			if err := s.store.DeleteIngredientMemory(ctx, userID, name); err != nil {
				return err
			}
			continue
		}

		// "add" — the default for anything that is not an explicit "remove".
		status := ing.Status
		if status == "" {
			status = "confirmed"
		}
		confidence := 0.8
		if status == "confirmed" {
			confidence = 1.0
		}
		display := strings.TrimSpace(ing.DisplayName)
		if display == "" {
			display = ing.CanonicalName
		}
		category := ing.Category
		if category == "" {
			category = "other"
		}

		var cfoQty *store.CFOQuantity
		var onHand *float64
		if ing.Quantity != nil {
			cfoQty = &store.CFOQuantity{Amount: ing.Quantity.Amount, Unit: ing.Quantity.Unit}
			amount := ing.Quantity.Amount
			onHand = &amount
		}
		now := time.Now().UTC().Format(time.RFC3339)

		if err := s.store.UpsertFoodItem(ctx, store.FoodItemUpsert{
			UserID:        userID,
			CanonicalName: name,
			DisplayName:   display,
			Quantity:      cfoQty,
			Category:      store.CFOCategory{Primary: category},
			Flexibility:   store.CFOFlexibility{SubstitutionAllowed: true},
			UsageContext:  store.CFOUsageContext{Role: "inventory"},
			InventoryState: store.CFOInventoryState{
				Status:        status,
				OnHandAmount:  onHand,
				LastConfirmed: &now,
			},
			Sourcing: store.CFOSourcing{BulkAllowed: true, GenericOK: true},
			Metadata: store.CFOMetadata{CreatedBy: "ai", Confidence: confidence},
		}); err != nil {
			return err
		}
		if err := s.store.UpsertIngredientMemory(ctx, userID, name,
			quantityString(ing.Quantity), confidence); err != nil {
			return err
		}
	}
	return nil
}

// toolCreateMealPlan handles the create_meal_plan tool: it replaces the
// caller's week with the meals the model chose. `weekStart` is the
// client-supplied local Monday (YYYY-MM-DD); empty means fall back to
// the server's UTC Monday.
func (s *Server) toolCreateMealPlan(ctx context.Context, userID, args, weekStart string) error {
	var p struct {
		Meals []struct {
			DayOfWeek int    `json:"dayOfWeek"`
			MealName  string `json:"mealName"`
			Notes     string `json:"notes"`
		} `json:"meals"`
	}
	if err := json.Unmarshal([]byte(args), &p); err != nil {
		return err
	}

	meals := make([]store.MealInput, 0, len(p.Meals))
	for _, m := range p.Meals {
		if strings.TrimSpace(m.MealName) == "" {
			continue
		}
		var notes *string
		if strings.TrimSpace(m.Notes) != "" {
			n := m.Notes
			notes = &n
		}
		meals = append(meals, store.MealInput{DayOfWeek: m.DayOfWeek, MealName: m.MealName, Notes: notes})
	}
	if len(meals) == 0 {
		return nil
	}
	week := strings.TrimSpace(weekStart)
	if week == "" {
		week = currentWeekStart()
	}
	full, err := s.store.ReplaceMealPlan(ctx, userID, week, meals)
	if err != nil {
		return err
	}
	// Background image generation for every newly-created day so the
	// chat-driven plan lands with photos already populated. See images.go.
	s.kickoffMealDayImages(userID, full.Days)
	return nil
}

// toolCreateShoppingList handles the create_shopping_list tool: it creates a
// "Shopping List" for the caller's week and, per item, upserts a shopping-role
// CFO and inserts a shopping_list_items row. `weekStart` is the
// client-supplied local Monday (YYYY-MM-DD); empty means fall back to the
// server's UTC Monday.
func (s *Server) toolCreateShoppingList(ctx context.Context, userID, args, weekStart string) error {
	var p struct {
		Items []struct {
			CanonicalName       string        `json:"canonical_name"`
			DisplayName         string        `json:"display_name"`
			Quantity            *toolQuantity `json:"quantity"`
			Category            string        `json:"category"`
			SubstitutionAllowed *bool         `json:"substitution_allowed"`
			GenericOK           *bool         `json:"generic_ok"`
		} `json:"items"`
	}
	if err := json.Unmarshal([]byte(args), &p); err != nil {
		return err
	}

	week := strings.TrimSpace(weekStart)
	if week == "" {
		week = currentWeekStart()
	}
	var mealPlanID *int
	if plan, err := s.store.GetMealPlanByWeek(ctx, userID, week); err == nil {
		id := plan.ID
		mealPlanID = &id
	}

	list, err := s.store.CreateShoppingList(ctx, userID, "Shopping List", &week, mealPlanID)
	if err != nil {
		return err
	}

	for _, it := range p.Items {
		name := strings.ToLower(strings.TrimSpace(it.CanonicalName))
		if name == "" {
			continue
		}
		display := strings.TrimSpace(it.DisplayName)
		if display == "" {
			display = it.CanonicalName
		}
		category := it.Category
		if category == "" {
			category = "other"
		}
		substitutionAllowed := it.SubstitutionAllowed == nil || *it.SubstitutionAllowed
		genericOK := it.GenericOK == nil || *it.GenericOK

		var cfoQty *store.CFOQuantity
		if it.Quantity != nil {
			cfoQty = &store.CFOQuantity{Amount: it.Quantity.Amount, Unit: it.Quantity.Unit}
		}
		listID := list.ID

		if err := s.store.UpsertFoodItem(ctx, store.FoodItemUpsert{
			UserID:        userID,
			CanonicalName: name,
			DisplayName:   display,
			Quantity:      cfoQty,
			Category:      store.CFOCategory{Primary: category},
			Flexibility:   store.CFOFlexibility{SubstitutionAllowed: substitutionAllowed},
			UsageContext:  store.CFOUsageContext{Role: "shopping", ShoppingListID: &listID},
			Sourcing:      store.CFOSourcing{BulkAllowed: true, GenericOK: genericOK},
			Metadata:      store.CFOMetadata{CreatedBy: "ai", Confidence: 1.0},
		}); err != nil {
			return err
		}
		// shopping_list_items name = display_name || canonical_name.
		if _, err := s.store.InsertShoppingItem(ctx, list.ID, display,
			quantityString(it.Quantity), category); err != nil {
			return err
		}
	}
	return nil
}

// toolSaveRecipe handles the save_recipe tool: it inserts a cookbook_recipes
// row so the recipe lands on the Cookbook tab. Per the contract we silently
// no-op when title or content is blank — the model occasionally tries to call
// the tool without an in-progress recipe, and we'd rather drop those than
// abort the whole assistant turn.
func (s *Server) toolSaveRecipe(ctx context.Context, userID, args string) error {
	var p struct {
		Title       string `json:"title"`
		Content     string `json:"content"`
		ImagePrompt string `json:"imagePrompt"`
	}
	if err := json.Unmarshal([]byte(args), &p); err != nil {
		return err
	}
	title := strings.TrimSpace(p.Title)
	content := strings.TrimSpace(p.Content)
	if title == "" || content == "" {
		return nil
	}
	var imagePrompt *string
	if ip := strings.TrimSpace(p.ImagePrompt); ip != "" {
		imagePrompt = &ip
	}
	recipe, err := s.store.CreateCookbookRecipe(ctx, userID, title, content, imagePrompt)
	if err != nil {
		return err
	}
	// Background image generation so the cookbook tile lands with a
	// photo. Falls back to the title-templated prompt if the model
	// didn't supply one. See images.go.
	prompt := strings.TrimSpace(p.ImagePrompt)
	if prompt == "" {
		prompt = strings.ReplaceAll(recipeImagePromptTemplate, "<mealName>", title)
	}
	s.kickoffCookbookImage(userID, recipe.ID, prompt)
	return nil
}
