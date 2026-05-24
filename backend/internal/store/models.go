package store

import (
	"encoding/json"
	"time"
)

// The structs below are the API response shapes. JSON field names are
// camelCase, exactly as required by contract/api-spec.md. Keys inside the CFO
// JSONB blobs stay snake_case — see fooditems.go.

// Profile is a user's profile row (contract Decision D1: replaces "users").
type Profile struct {
	ID              string    `json:"id"`
	Email           *string   `json:"email"`
	FirstName       *string   `json:"firstName"`
	LastName        *string   `json:"lastName"`
	ProfileImageURL *string   `json:"profileImageUrl"`
	CreatedAt       time.Time `json:"createdAt"`
	UpdatedAt       time.Time `json:"updatedAt"`
}

// Conversation is a kitchen-chat conversation.
type Conversation struct {
	ID        int       `json:"id"`
	UserID    string    `json:"userId"`
	Title     string    `json:"title"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
}

// Message is a single chat message.
type Message struct {
	ID             int             `json:"id"`
	ConversationID int             `json:"conversationId"`
	Role           string          `json:"role"`
	Content        string          `json:"content"`
	Metadata       json.RawMessage `json:"metadata"`
	CreatedAt      time.Time       `json:"createdAt"`
}

// ConversationWithMessages is a conversation plus its messages.
type ConversationWithMessages struct {
	Conversation
	Messages []Message `json:"messages"`
}

// MealPlan is a weekly meal plan. WeekStartDate is a YYYY-MM-DD string.
type MealPlan struct {
	ID            int       `json:"id"`
	UserID        string    `json:"userId"`
	WeekStartDate string    `json:"weekStartDate"`
	CreatedAt     time.Time `json:"createdAt"`
	UpdatedAt     time.Time `json:"updatedAt"`
}

// MealPlanDay is one day within a meal plan. `ImageURL` is the persisted
// `data:image/png;base64,…` URL emitted by gpt-image-1 (or nil for "no
// image generated yet; show Tap-to-generate placeholder").
type MealPlanDay struct {
	ID                int     `json:"id"`
	MealPlanID        int     `json:"mealPlanId"`
	DayOfWeek         int     `json:"dayOfWeek"`
	RecipeID          *int    `json:"recipeId"`
	MealName          string  `json:"mealName"`
	Notes             *string `json:"notes"`
	RecipeContent     *string `json:"recipeContent"`
	RecipeImagePrompt *string `json:"recipeImagePrompt"`
	ImageURL          *string `json:"imageUrl"`
}

// MealPlanWithDays is a meal plan plus its days.
type MealPlanWithDays struct {
	MealPlan
	Days []MealPlanDay `json:"days"`
}

// MealPlanDayWithUser is a meal-plan day with the owning user's id, as
// returned by GET /api/kitchen/meal-plan-day/:id.
type MealPlanDayWithUser struct {
	MealPlanDay
	UserID string `json:"userId"`
}

// ShoppingList is a shopping list. WeekStartDate is a *YYYY-MM-DD string.
type ShoppingList struct {
	ID            int       `json:"id"`
	UserID        string    `json:"userId"`
	Name          string    `json:"name"`
	WeekStartDate *string   `json:"weekStartDate"`
	MealPlanID    *int      `json:"mealPlanId"`
	CreatedAt     time.Time `json:"createdAt"`
}

// ShoppingItem is a line item on a shopping list. Checked is 0 or 1, an
// integer (not a boolean), preserved from the original schema.
type ShoppingItem struct {
	ID             int     `json:"id"`
	ShoppingListID int     `json:"shoppingListId"`
	Name           string  `json:"name"`
	Quantity       *string `json:"quantity"`
	Category       string  `json:"category"`
	Checked        int     `json:"checked"`
}

// ShoppingListWithItems is a shopping list plus its items.
type ShoppingListWithItems struct {
	ShoppingList
	Items []ShoppingItem `json:"items"`
}

// CookbookRecipe is a saved recipe. `ImageURL` is the persisted
// `data:image/png;base64,…` URL — same semantics as MealPlanDay.ImageURL.
type CookbookRecipe struct {
	ID          int       `json:"id"`
	UserID      string    `json:"userId"`
	Title       string    `json:"title"`
	Content     string    `json:"content"`
	ImagePrompt *string   `json:"imagePrompt"`
	ImageURL    *string   `json:"imageUrl"`
	CreatedAt   time.Time `json:"createdAt"`
}

// Ingredient is a soft-inventory ingredient-memory row.
type Ingredient struct {
	ID            int       `json:"id"`
	UserID        string    `json:"userId"`
	Name          string    `json:"name"`
	Quantity      *string   `json:"quantity"`
	Confidence    float64   `json:"confidence"`
	LastMentioned time.Time `json:"lastMentioned"`
	CreatedAt     time.Time `json:"createdAt"`
}
