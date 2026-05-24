package store

import (
	"context"
	"encoding/json"
	"strings"
	"time"
)

// The Canonical Food Object JSONB shapes. Unlike the row models in models.go,
// CFO blob keys are snake_case — exactly as the original stores them (see
// contract/data-model.md).

// CFOQuantity is an amount with a unit.
type CFOQuantity struct {
	Amount float64 `json:"amount"`
	Unit   string  `json:"unit"`
}

// CFOCategory classifies a food item.
type CFOCategory struct {
	Primary   string `json:"primary"`
	Secondary string `json:"secondary,omitempty"`
}

// CFOFlexibility describes substitution tolerance.
type CFOFlexibility struct {
	SubstitutionAllowed bool     `json:"substitution_allowed"`
	AcceptableVariants  []string `json:"acceptable_variants"`
	Strict              bool     `json:"strict"`
}

// CFOUsageContext records the role a food item plays and its links.
type CFOUsageContext struct {
	Role           string `json:"role"`
	Required       bool   `json:"required"`
	RecipeIDs      []int  `json:"recipe_ids"`
	MealPlanID     *int   `json:"meal_plan_id,omitempty"`
	ShoppingListID *int   `json:"shopping_list_id,omitempty"`
}

// CFOInventoryState records what is known about an item's on-hand status.
type CFOInventoryState struct {
	Status        string   `json:"status"`
	OnHandAmount  *float64 `json:"on_hand_amount"`
	LastConfirmed *string  `json:"last_confirmed"`
}

// CFOSourcing records purchasing preferences.
type CFOSourcing struct {
	StoreAffinity *string `json:"store_affinity"`
	BulkAllowed   bool    `json:"bulk_allowed"`
	GenericOK     bool    `json:"generic_ok"`
}

// CFOMetadata records provenance and confidence.
type CFOMetadata struct {
	CreatedBy  string  `json:"created_by"`
	Confidence float64 `json:"confidence"`
}

// FoodItemUpsert is the full set of fields written by UpsertFoodItem.
type FoodItemUpsert struct {
	UserID         string
	CanonicalName  string
	DisplayName    string
	Quantity       *CFOQuantity
	Category       CFOCategory
	Attributes     map[string]any
	Flexibility    CFOFlexibility
	UsageContext   CFOUsageContext
	InventoryState CFOInventoryState
	Sourcing       CFOSourcing
	Metadata       CFOMetadata
}

// UpsertFoodItem inserts or updates a Canonical Food Object. It matches on the
// CFO identity invariant — (user_id, canonical_name, usage_context.role) —
// via the food_items_identity_uniq expression index.
func (s *Store) UpsertFoodItem(ctx context.Context, f FoodItemUpsert) error {
	if f.Attributes == nil {
		f.Attributes = map[string]any{}
	}
	if f.Flexibility.AcceptableVariants == nil {
		f.Flexibility.AcceptableVariants = []string{}
	}
	if f.UsageContext.RecipeIDs == nil {
		f.UsageContext.RecipeIDs = []int{}
	}
	if f.InventoryState.Status == "" {
		f.InventoryState.Status = "unknown"
	}

	category, _ := json.Marshal(f.Category)
	attributes, _ := json.Marshal(f.Attributes)
	flexibility, _ := json.Marshal(f.Flexibility)
	usageContext, _ := json.Marshal(f.UsageContext)
	inventoryState, _ := json.Marshal(f.InventoryState)
	sourcing, _ := json.Marshal(f.Sourcing)
	metadata, _ := json.Marshal(f.Metadata)

	// A nil quantity is stored as SQL NULL, not the JSON literal null.
	var quantity any
	if f.Quantity != nil {
		b, _ := json.Marshal(f.Quantity)
		quantity = b
	}

	_, err := s.pool.Exec(ctx,
		`INSERT INTO food_items
		   (user_id, canonical_name, display_name, quantity, category, attributes,
		    flexibility, usage_context, inventory_state, sourcing, metadata)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		 ON CONFLICT (user_id, canonical_name, (usage_context ->> 'role'))
		 DO UPDATE SET
		   display_name    = EXCLUDED.display_name,
		   quantity        = EXCLUDED.quantity,
		   category        = EXCLUDED.category,
		   attributes      = EXCLUDED.attributes,
		   flexibility     = EXCLUDED.flexibility,
		   usage_context   = EXCLUDED.usage_context,
		   inventory_state = EXCLUDED.inventory_state,
		   sourcing        = EXCLUDED.sourcing,
		   metadata        = EXCLUDED.metadata,
		   updated_at      = now()`,
		f.UserID, f.CanonicalName, f.DisplayName, quantity, category, attributes,
		flexibility, usageContext, inventoryState, sourcing, metadata)
	return err
}

// IngredientSuggestion is one autocomplete row for the cookbook
// ingredient helper — canonical name + display name.
type IngredientSuggestion struct {
	CanonicalName string `json:"canonical_name"`
	DisplayName   string `json:"display_name"`
}

// ListIngredientSuggestions returns autocomplete candidates pulled
// from (a) the user's inventory-role CFO rows and (b) the legacy
// `ingredient_memory` rows, deduped by canonical name. Mirrors the
// original web app's `/ingredient-suggestions` shape and cap (20).
func (s *Store) ListIngredientSuggestions(ctx context.Context, userID string) ([]IngredientSuggestion, error) {
	out := make([]IngredientSuggestion, 0, 20)
	seen := map[string]bool{}

	// Inventory CFOs first (richer display names).
	rows, err := s.pool.Query(ctx,
		`SELECT canonical_name, display_name FROM food_items
		 WHERE user_id = $1 AND usage_context ->> 'role' = 'inventory'
		 ORDER BY updated_at DESC NULLS LAST, id DESC`, userID)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var canonical, display string
			if err := rows.Scan(&canonical, &display); err != nil {
				continue
			}
			canonical = strings.ToLower(strings.TrimSpace(canonical))
			if canonical == "" || seen[canonical] {
				continue
			}
			seen[canonical] = true
			if display == "" {
				display = canonical
			}
			out = append(out, IngredientSuggestion{CanonicalName: canonical, DisplayName: display})
		}
	}

	// Legacy ingredient_memory fallback.
	rows2, err := s.pool.Query(ctx,
		`SELECT name FROM ingredient_memory
		 WHERE user_id = $1 ORDER BY last_mentioned DESC NULLS LAST, id DESC`, userID)
	if err == nil {
		defer rows2.Close()
		for rows2.Next() {
			var name string
			if err := rows2.Scan(&name); err != nil {
				continue
			}
			canonical := strings.ToLower(strings.TrimSpace(name))
			if canonical == "" || seen[canonical] {
				continue
			}
			seen[canonical] = true
			out = append(out, IngredientSuggestion{CanonicalName: canonical, DisplayName: name})
			if len(out) >= 20 {
				break
			}
		}
	}

	if len(out) > 20 {
		out = out[:20]
	}
	return out, nil
}

// MarkFoodItemOut sets a user's inventory-role CFO for canonicalName to an
// "out" state. It is a no-op when no such item exists.
func (s *Store) MarkFoodItemOut(ctx context.Context, userID, canonicalName string) error {
	now := time.Now().UTC().Format(time.RFC3339)
	state, _ := json.Marshal(CFOInventoryState{
		Status:        "out",
		OnHandAmount:  ptrFloat(0),
		LastConfirmed: &now,
	})
	_, err := s.pool.Exec(ctx,
		`UPDATE food_items SET inventory_state = $3, updated_at = now()
		 WHERE user_id = $1 AND canonical_name = $2
		   AND usage_context ->> 'role' = 'inventory'`,
		userID, canonicalName, state)
	return err
}
