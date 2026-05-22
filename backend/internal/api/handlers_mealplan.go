package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"math/rand/v2"
	"net/http"
	"strings"
	"time"

	"souschef/internal/auth"
	"souschef/internal/openai"
	"souschef/internal/store"
)

// handleGetMealPlan serves GET /api/kitchen/meal-plan — the most recent plan
// with its days, or null.
func (s *Server) handleGetMealPlan(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	plan, err := s.store.GetMostRecentMealPlan(ctx, auth.UserID(ctx))
	if errors.Is(err, store.ErrNotFound) {
		writeJSON(w, http.StatusOK, nil)
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	full, err := s.store.GetMealPlanWithDays(ctx, plan)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, full)
}

// handleCalendar serves GET /api/kitchen/calendar — all plans and lists, no
// child rows.
func (s *Server) handleCalendar(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID := auth.UserID(ctx)

	plans, err := s.store.ListMealPlans(ctx, userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	lists, err := s.store.ListShoppingLists(ctx, userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"mealPlans":     plans,
		"shoppingLists": lists,
	})
}

// handleGetWeek serves GET /api/kitchen/week/{weekStartDate}.
func (s *Server) handleGetWeek(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID := auth.UserID(ctx)
	week := r.PathValue("weekStartDate")

	var mealPlan any
	if plan, err := s.store.GetMealPlanByWeek(ctx, userID, week); err == nil {
		full, err := s.store.GetMealPlanWithDays(ctx, plan)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "internal error")
			return
		}
		mealPlan = full
	}

	var shoppingList any
	if list, err := s.store.GetShoppingListByWeek(ctx, userID, week); err == nil {
		items, err := s.store.GetShoppingItems(ctx, list.ID)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "internal error")
			return
		}
		shoppingList = store.ShoppingListWithItems{ShoppingList: list, Items: items}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"mealPlan":     mealPlan,
		"shoppingList": shoppingList,
	})
}

// handleGetMealPlanDay serves GET /api/kitchen/meal-plan-day/{id}.
func (s *Server) handleGetMealPlanDay(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	id, ok := pathInt(r, "id")
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid day id")
		return
	}
	day, owner, err := s.store.GetMealPlanDay(ctx, id)
	if writeStoreErr(w, err, "meal-plan day not found") {
		return
	}
	if owner != auth.UserID(ctx) {
		writeError(w, http.StatusForbidden, "forbidden")
		return
	}
	writeJSON(w, http.StatusOK, store.MealPlanDayWithUser{MealPlanDay: day, UserID: owner})
}

// handleGenerateMealPlan serves POST /api/kitchen/generate-meal-plan.
func (s *Server) handleGenerateMealPlan(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID := auth.UserID(ctx)

	var body struct {
		WeekStartDate string `json:"weekStartDate"`
	}
	if err := decodeJSON(r, &body); err != nil && !errors.Is(err, io.EOF) {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	week := strings.TrimSpace(body.WeekStartDate)
	if week == "" {
		week = currentWeekStart()
	} else if _, err := time.Parse("2006-01-02", week); err != nil {
		writeError(w, http.StatusBadRequest, "weekStartDate must be YYYY-MM-DD")
		return
	}

	ingredients, _ := s.store.GetIngredientMemory(ctx, userID)
	cookbook, _ := s.store.ListCookbook(ctx, userID)

	meals := s.generateMealPlanMeals(ctx, ingredients, cookbook)
	if len(meals) == 0 {
		meals = fallbackMealPlan()
	}

	full, err := s.store.ReplaceMealPlan(ctx, userID, week, meals)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, full)
}

var mealPlanCuisines = []string{
	"Italian", "Mexican", "Asian", "American comfort", "Mediterranean",
	"Southern", "Tex-Mex", "Greek", "Indian-inspired", "French bistro",
}

// seasonalFocus returns the seasonal lean for the given month.
func seasonalFocus(now time.Time) string {
	switch now.Month() {
	case time.October, time.November, time.December, time.January, time.February:
		return "hearty, warming"
	default:
		return "fresh, lighter"
	}
}

// generateMealPlanMeals asks the model for a weekly plan and parses it. It
// returns nil on any failure, leaving the caller to use the fallback plan.
func (s *Server) generateMealPlanMeals(ctx context.Context, ingredients []store.Ingredient, cookbook []store.CookbookRecipe) []store.MealInput {
	ingredientList := "common pantry items"
	if names := ingredientNames(ingredients); len(names) > 0 {
		ingredientList = strings.Join(names, ", ")
	}

	system := strings.ReplaceAll(mealPlanGenSystemPrompt, "<cookbookContext>",
		buildMealPlanCookbookContext(cookbook))
	user := mealPlanGenUserPrompt
	user = strings.ReplaceAll(user, "<randomCuisine>", mealPlanCuisines[rand.IntN(len(mealPlanCuisines))])
	user = strings.ReplaceAll(user, "<seasonalFocus>", seasonalFocus(time.Now().UTC()))
	user = strings.ReplaceAll(user, "<ingredientList>", ingredientList)

	temperature := 0.9
	maxTokens := 1024
	content, err := s.ai.ChatJSON(ctx, openai.ChatParams{
		Model: "gpt-4.1",
		Messages: []openai.Message{
			{Role: "system", Content: system},
			{Role: "user", Content: user},
		},
		Temperature:         &temperature,
		MaxCompletionTokens: &maxTokens,
	})
	if err != nil {
		return nil
	}
	return parseMealPlanJSON(content)
}

// ingredientNames extracts the non-empty names from ingredient-memory rows.
func ingredientNames(ingredients []store.Ingredient) []string {
	names := make([]string, 0, len(ingredients))
	for _, ing := range ingredients {
		if n := strings.TrimSpace(ing.Name); n != "" {
			names = append(names, n)
		}
	}
	return names
}

// parseMealPlanJSON leniently parses a model meal-plan response: it accepts a
// bare array, or an object with a meals / mealPlan / plan array, keeping only
// entries with a numeric dayOfWeek and a non-empty mealName.
func parseMealPlanJSON(raw string) []store.MealInput {
	type rawMeal struct {
		DayOfWeek *float64 `json:"dayOfWeek"`
		MealName  *string  `json:"mealName"`
		Notes     *string  `json:"notes"`
	}
	convert := func(meals []rawMeal) []store.MealInput {
		out := make([]store.MealInput, 0, len(meals))
		for _, m := range meals {
			if m.DayOfWeek == nil || m.MealName == nil || strings.TrimSpace(*m.MealName) == "" {
				continue
			}
			var notes *string
			if m.Notes != nil && strings.TrimSpace(*m.Notes) != "" {
				notes = m.Notes
			}
			out = append(out, store.MealInput{
				DayOfWeek: int(*m.DayOfWeek),
				MealName:  *m.MealName,
				Notes:     notes,
			})
		}
		return out
	}

	var arr []rawMeal
	if json.Unmarshal([]byte(raw), &arr) == nil {
		if out := convert(arr); len(out) > 0 {
			return out
		}
	}
	var obj struct {
		Meals    []rawMeal `json:"meals"`
		MealPlan []rawMeal `json:"mealPlan"`
		Plan     []rawMeal `json:"plan"`
	}
	if json.Unmarshal([]byte(raw), &obj) == nil {
		for _, candidate := range [][]rawMeal{obj.Meals, obj.MealPlan, obj.Plan} {
			if out := convert(candidate); len(out) > 0 {
				return out
			}
		}
	}
	return nil
}

var fallbackMealGroups = [7][]string{
	{"Grilled Chicken Salad", "Honey Garlic Chicken", "Lemon Herb Roasted Chicken", "Chicken Stir-Fry"},
	{"Spaghetti Carbonara", "Pasta Primavera", "Creamy Mushroom Pasta", "Penne Arrabiata"},
	{"Beef Tacos", "Beef Stir-Fry with Broccoli", "Shepherd's Pie", "Beef and Vegetable Soup"},
	{"Grilled Salmon", "Fish Tacos", "Baked Cod with Lemon", "Shrimp Scampi"},
	{"Homemade Pizza", "Veggie Burgers", "Loaded Nachos", "Quesadillas"},
	{"BBQ Ribs", "Pulled Pork Sandwiches", "Slow Cooker Pot Roast", "Grilled Steak"},
	{"Sunday Roast Chicken", "Lasagna", "Baked Ham", "Roast Beef with Vegetables"},
}

var fallbackDays = [7]int{1, 2, 3, 4, 5, 6, 0}
var fallbackNotes = [7]string{"25 min", "30 min", "35 min", "40 min", "45 min", "1 hour", "Slow cooker"}

// fallbackMealPlan builds a plan by picking one random meal from each of the
// seven fallback groups; used when AI generation yields no usable meals.
func fallbackMealPlan() []store.MealInput {
	meals := make([]store.MealInput, 0, 7)
	for i := range 7 {
		name := fallbackMealGroups[i][rand.IntN(len(fallbackMealGroups[i]))]
		notes := fallbackNotes[i]
		meals = append(meals, store.MealInput{
			DayOfWeek: fallbackDays[i],
			MealName:  name,
			Notes:     &notes,
		})
	}
	return meals
}
