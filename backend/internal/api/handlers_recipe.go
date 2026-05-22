package api

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"

	"souschef/internal/auth"
	"souschef/internal/openai"
)

// handleGenerateRecipe serves POST /api/kitchen/generate-recipe/{dayId} — it
// streams a full recipe as Markdown, then stores it on the day row.
func (s *Server) handleGenerateRecipe(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	dayID, ok := pathInt(r, "dayId")
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid day id")
		return
	}
	day, owner, err := s.store.GetMealPlanDay(ctx, dayID)
	if writeStoreErr(w, err, "meal-plan day not found") {
		return
	}
	if owner != auth.UserID(ctx) {
		writeError(w, http.StatusForbidden, "forbidden")
		return
	}

	sse, ok := newSSE(w)
	if !ok {
		return
	}

	system := strings.ReplaceAll(recipeGenSystemPrompt, "<mealName>", day.MealName)
	user := "Please give me the full recipe for " + day.MealName + "."
	result, err := s.ai.ChatStream(ctx, openai.ChatParams{
		Model: "gpt-4.1",
		Messages: []openai.Message{
			{Role: "system", Content: system},
			{Role: "user", Content: user},
		},
	}, func(delta string) {
		sse.send(map[string]string{"content": delta})
	})
	if err != nil {
		sse.sendError(err.Error())
		return
	}

	imagePrompt := strings.ReplaceAll(recipeImagePromptTemplate, "<mealName>", day.MealName)
	if err := s.store.SetMealPlanDayRecipe(ctx, dayID, result.Content, imagePrompt); err != nil {
		log.Printf("save recipe for day %d: %v", dayID, err)
	}
	sse.send(map[string]any{"imagePrompt": imagePrompt, "done": true})
}

// handleRecipeMessage serves POST /api/kitchen/recipe-message — per-recipe
// chat. If the model calls update_meal, the day is swapped and reported in the
// final SSE event.
func (s *Server) handleRecipeMessage(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	var body struct {
		Content  string `json:"content"`
		DayID    *int   `json:"dayId"`
		MealName string `json:"mealName"`
		DayName  string `json:"dayName"`
	}
	if err := decodeJSON(r, &body); err != nil || strings.TrimSpace(body.Content) == "" || body.DayID == nil {
		writeError(w, http.StatusBadRequest, "content and dayId are required")
		return
	}

	_, owner, err := s.store.GetMealPlanDay(ctx, *body.DayID)
	if writeStoreErr(w, err, "meal-plan day not found") {
		return
	}
	if owner != auth.UserID(ctx) {
		writeError(w, http.StatusForbidden, "forbidden")
		return
	}

	sse, ok := newSSE(w)
	if !ok {
		return
	}

	system := recipeChatSystemPrompt
	system = strings.ReplaceAll(system, "<mealName>", body.MealName)
	system = strings.ReplaceAll(system, "<dayName>", body.DayName)

	result, err := s.ai.ChatStream(ctx, openai.ChatParams{
		Model: "gpt-4.1",
		Messages: []openai.Message{
			{Role: "system", Content: system},
			{Role: "user", Content: body.Content},
		},
		Tools: openai.RecipeTools(),
	}, func(delta string) {
		sse.send(map[string]string{"content": delta})
	})
	if err != nil {
		sse.sendError(err.Error())
		return
	}

	var updatedMeal any
	for _, tc := range result.ToolCalls {
		if tc.Name != "update_meal" {
			continue
		}
		var args struct {
			MealName string `json:"mealName"`
			Notes    string `json:"notes"`
		}
		if err := json.Unmarshal([]byte(tc.Arguments), &args); err != nil {
			log.Printf("recipe-message update_meal args: %v", err)
			continue
		}
		if strings.TrimSpace(args.MealName) == "" {
			continue
		}
		var notes *string
		if strings.TrimSpace(args.Notes) != "" {
			n := args.Notes
			notes = &n
		}
		if err := s.store.UpdateMealPlanDayMeal(ctx, *body.DayID, args.MealName, notes); err != nil {
			log.Printf("recipe-message update meal: %v", err)
			continue
		}
		updatedMeal = map[string]any{"mealName": args.MealName, "notes": notes}
	}

	sse.send(map[string]any{"done": true, "updatedMeal": updatedMeal})
}
