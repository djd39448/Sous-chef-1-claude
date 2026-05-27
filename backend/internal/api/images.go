// Package api — images.go.
//
// Background image generation for meal-plan days and freshly-saved
// cookbook recipes.
//
// Depends on:     internal/openai (GenerateImage), internal/store
//                 (SetMealPlanDayImage, SetCookbookImage), the prompt
//                 template in prompts.go.
// Depended on by: handlers_mealplan.go (handleGenerateMealPlan,
//                 handleRegenerateDays, handlePatchMealPlanDay),
//                 handlers_recipe.go (handleRecipeMessage update_meal
//                 path), handlers_cookbook.go (handleCreateCookbookRecipe),
//                 tools.go (toolCreateMealPlan, toolSaveRecipe).
// Why it exists:  every screen that lists meal-plan days or cookbook
//                 recipes expects the row's image to already be in
//                 place. Firing image generation in the background as
//                 soon as a row lands means Home, Plan, Calendar, and
//                 Cookbook never render the "Tap to generate" placeholder
//                 in the normal flow. The Recipe-screen photo button
//                 stays as a manual "regenerate this one" retry for
//                 images the user doesn't like.

package api

import (
	"context"
	"log"
	"strings"
	"time"

	"souschef/internal/store"
)

// kickoffMealDayImages launches background image generation for each
// of the given meal-plan-day rows that doesn't already have an image.
// Returns immediately; each goroutine uses its own context with a
// 5-minute timeout so it survives the originating HTTP request.
// Errors are logged and dropped — a row whose image generation fails
// stays blank and the user can tap the Recipe-screen regenerate
// button as a retry.
func (s *Server) kickoffMealDayImages(userID string, days []store.MealPlanDay) {
	for _, d := range days {
		if d.ImageURL != nil && strings.TrimSpace(*d.ImageURL) != "" {
			continue
		}
		prompt := mealDayImagePrompt(d)
		if prompt == "" {
			continue
		}
		d := d
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
			defer cancel()
			b64, err := s.ai.GenerateImage(ctx, prompt)
			if err != nil {
				log.Printf("autogen image dayID=%d user=%s: %v", d.ID, userID, err)
				return
			}
			url := "data:image/png;base64," + b64
			if err := s.store.SetMealPlanDayImage(ctx, d.ID, url); err != nil {
				log.Printf("autogen image persist dayID=%d: %v", d.ID, err)
			}
		}()
	}
}

// kickoffCookbookImage launches background image generation for a
// freshly-saved cookbook recipe. Same best-effort semantics as
// kickoffMealDayImages — errors log and drop. No-op if the prompt
// is blank.
func (s *Server) kickoffCookbookImage(userID string, recipeID int, prompt string) {
	p := strings.TrimSpace(prompt)
	if p == "" {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		defer cancel()
		b64, err := s.ai.GenerateImage(ctx, p)
		if err != nil {
			log.Printf("autogen image recipeID=%d user=%s: %v", recipeID, userID, err)
			return
		}
		url := "data:image/png;base64," + b64
		if err := s.store.SetCookbookImage(ctx, recipeID, url); err != nil {
			log.Printf("autogen image persist recipeID=%d: %v", recipeID, err)
		}
	}()
}

// mealDayImagePrompt picks the best available prompt for a meal-plan
// day. Prefers the stored `recipe_image_prompt` (tuned with plating
// language by the recipe-generation flow) and falls back to the
// generic template applied to the meal name.
func mealDayImagePrompt(d store.MealPlanDay) string {
	if d.RecipeImagePrompt != nil && strings.TrimSpace(*d.RecipeImagePrompt) != "" {
		return *d.RecipeImagePrompt
	}
	name := strings.TrimSpace(d.MealName)
	if name == "" {
		return ""
	}
	return strings.ReplaceAll(recipeImagePromptTemplate, "<mealName>", name)
}
