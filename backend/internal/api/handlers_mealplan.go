package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
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

// handlePatchMealPlanDay serves PATCH /api/kitchen/meal-plan-day/{id} —
// direct edits of `mealName` and `notes` from the Plan tab's edit sheet
// (no AI involvement). The store call clears `recipe_content`,
// `recipe_image_prompt`, and `image_url` because all of those described
// the OLD dish and would mislead users if left.
func (s *Server) handlePatchMealPlanDay(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	id, ok := pathInt(r, "id")
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid day id")
		return
	}

	// Ownership check before mutation.
	_, owner, err := s.store.GetMealPlanDay(ctx, id)
	if writeStoreErr(w, err, "meal-plan day not found") {
		return
	}
	if owner != auth.UserID(ctx) {
		writeError(w, http.StatusForbidden, "forbidden")
		return
	}

	var body struct {
		MealName string  `json:"mealName"`
		Notes    *string `json:"notes"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	mealName := strings.TrimSpace(body.MealName)
	if mealName == "" {
		writeError(w, http.StatusBadRequest, "mealName is required")
		return
	}
	if body.Notes != nil {
		trimmed := strings.TrimSpace(*body.Notes)
		if trimmed == "" {
			body.Notes = nil
		} else {
			body.Notes = &trimmed
		}
	}

	if err := s.store.UpdateMealPlanDayMeal(ctx, id, mealName, body.Notes); err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	// Return the fresh row so the iOS client doesn't need a second fetch.
	day, _, err := s.store.GetMealPlanDay(ctx, id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	// The store call cleared image_url; fire background image gen so the
	// new meal lands with a photo. See images.go.
	s.kickoffMealDayImages(auth.UserID(ctx), []store.MealPlanDay{day})
	writeJSON(w, http.StatusOK, day)
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
	// Background image generation for every newly-created day so the
	// Home/Plan/Calendar screens don't render placeholders. See
	// images.go.
	s.kickoffMealDayImages(userID, full.Days)
	writeJSON(w, http.StatusOK, full)
}

// handleRegenerateDays serves POST /api/kitchen/regenerate-days.
//
// Body: `{ weekStartDate, daysToRegenerate: [int] }`. `daysToRegenerate`
// is the list of `dayOfWeek` values (0=Sun…6=Sat) the user wants the AI
// to replace; days NOT in the list are kept as-is. The AI is told
// which existing meals to avoid (so it doesn't repeat them) and which
// days to fill. Each replaced day's meal name + notes get the new
// values, and `recipe_content` + `recipe_image_prompt` + `image_url`
// are cleared because they described the OLD dish.
//
// Returns the updated `MealPlanWithDays`.
func (s *Server) handleRegenerateDays(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID := auth.UserID(ctx)

	var body struct {
		WeekStartDate     string `json:"weekStartDate"`
		DaysToRegenerate  []int  `json:"daysToRegenerate"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	week := strings.TrimSpace(body.WeekStartDate)
	if week == "" || len(body.DaysToRegenerate) == 0 {
		writeError(w, http.StatusBadRequest,
			"weekStartDate and daysToRegenerate are required")
		return
	}
	if _, err := time.Parse("2006-01-02", week); err != nil {
		writeError(w, http.StatusBadRequest, "weekStartDate must be YYYY-MM-DD")
		return
	}

	// Build a quick lookup of which days to replace + sanity-clamp values.
	target := map[int]bool{}
	for _, d := range body.DaysToRegenerate {
		if d >= 0 && d <= 6 {
			target[d] = true
		}
	}
	if len(target) == 0 {
		writeError(w, http.StatusBadRequest,
			"daysToRegenerate must contain at least one valid dayOfWeek (0..6)")
		return
	}

	// Load the existing plan so we can (a) preserve untouched days and
	// (b) tell the model which meals to avoid duplicating.
	plan, err := s.store.GetMealPlanByWeek(ctx, userID, week)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "no meal plan for this week")
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

	// Anything to actually replace? If the user checked every day there
	// might be nothing to do — just return the plan unchanged.
	var kept []store.MealPlanDay
	for _, d := range full.Days {
		if !target[d.DayOfWeek] {
			kept = append(kept, d)
		}
	}
	if len(kept) == len(full.Days) {
		writeJSON(w, http.StatusOK, full)
		return
	}

	// Ask the AI for new meals for just the target days.
	ingredients, _ := s.store.GetIngredientMemory(ctx, userID)
	cookbook, _ := s.store.ListCookbook(ctx, userID)
	newMeals := s.generateMealsForDays(ctx, body.DaysToRegenerate, kept, ingredients, cookbook)

	// Update each target day's row. Map by dayOfWeek so we hit the right
	// row even if the AI orders them differently.
	dayByOfWeek := map[int]store.MealPlanDay{}
	for _, d := range full.Days {
		dayByOfWeek[d.DayOfWeek] = d
	}
	for _, m := range newMeals {
		if !target[m.DayOfWeek] {
			continue
		}
		row, ok := dayByOfWeek[m.DayOfWeek]
		if !ok {
			continue
		}
		if err := s.store.UpdateMealPlanDayMeal(ctx, row.ID, m.MealName, m.Notes); err != nil {
			writeError(w, http.StatusInternalServerError, "internal error")
			return
		}
	}

	// Return the fresh plan so the iOS client can swap state in one shot.
	plan2, err := s.store.GetMealPlanByWeek(ctx, userID, week)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	out, err := s.store.GetMealPlanWithDays(ctx, plan2)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	// Background image generation for just the replaced days — the
	// untouched days still have their old images. See images.go.
	replaced := make([]store.MealPlanDay, 0, len(target))
	for _, d := range out.Days {
		if target[d.DayOfWeek] {
			replaced = append(replaced, d)
		}
	}
	s.kickoffMealDayImages(userID, replaced)
	writeJSON(w, http.StatusOK, out)
}

// generateMealsForDays asks the model for new meals targeting a subset
// of the week's days. Mirrors the structure of generateMealPlanMeals
// but adds an `avoidMeals` list (meals already in the plan that we're
// keeping) and a tight day-selection prompt. Returns nil on any
// failure; caller falls back to fallback meals for those days.
func (s *Server) generateMealsForDays(
	ctx context.Context,
	daysToRegenerate []int,
	keptDays []store.MealPlanDay,
	ingredients []store.Ingredient,
	cookbook []store.CookbookRecipe,
) []store.MealInput {
	dayNamesIdx := []string{"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}
	dayNames := make([]string, 0, len(daysToRegenerate))
	for _, d := range daysToRegenerate {
		if d >= 0 && d <= 6 {
			dayNames = append(dayNames, dayNamesIdx[d])
		}
	}

	ingredientList := "common pantry items"
	if names := ingredientNames(ingredients); len(names) > 0 {
		ingredientList = strings.Join(names, ", ")
	}

	cookbookCtx := buildMealPlanCookbookContext(cookbook)

	// "Avoid these meals" — names of the days the user is keeping, so
	// the model doesn't re-suggest the same dishes.
	avoid := make([]string, 0, len(keptDays))
	for _, d := range keptDays {
		if n := strings.TrimSpace(d.MealName); n != "" {
			avoid = append(avoid, n)
		}
	}
	avoidLine := ""
	if len(avoid) > 0 {
		avoidLine = "Avoid these meals (already planned): " + strings.Join(avoid, ", ") + "."
	}

	// Day-of-week numbers in the prompt so the model can echo them back.
	daysCSV := intsToCSV(daysToRegenerate)

	system := "You are a creative meal planning assistant. " +
		"Generate new dinner suggestions for specific days only. " +
		cookbookCtx + " " + avoidLine + "\n\n" +
		"IMPORTANT: respond with valid JSON containing a \"meals\" array."
	user := "Generate new UNIQUE dinner suggestions for these days only: " +
		strings.Join(dayNames, ", ") + ".\n\n" +
		"This week, lean toward " +
		mealPlanCuisines[rand.IntN(len(mealPlanCuisines))] +
		" influences with " + seasonalFocus(time.Now().UTC()) + " dishes. " +
		"Available ingredients: " + ingredientList + ".\n\n" +
		"Be creative — different from anything already planned.\n\n" +
		"Return JSON in this exact format:\n" +
		"{ \"meals\": [ { \"dayOfWeek\": <number>, \"mealName\": \"…\", \"notes\": \"…\" } ] }\n\n" +
		"Where dayOfWeek is 0=Sunday … 6=Saturday. " +
		"Only include the days I asked for: " + daysCSV + "."

	temperature := 0.95
	maxTokens := 512
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
	all := parseMealPlanJSON(content)
	// Filter to just the days the caller wanted — the model occasionally
	// includes extras.
	want := map[int]bool{}
	for _, d := range daysToRegenerate {
		want[d] = true
	}
	out := make([]store.MealInput, 0, len(all))
	for _, m := range all {
		if want[m.DayOfWeek] {
			out = append(out, m)
		}
	}
	return out
}

// intsToCSV — small helper used in the regenerate-days prompt.
func intsToCSV(xs []int) string {
	parts := make([]string, 0, len(xs))
	for _, x := range xs {
		parts = append(parts, fmt.Sprintf("%d", x))
	}
	return strings.Join(parts, ", ")
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
