package store

import "context"

const ingredientCols = `id, user_id, name, quantity, confidence, last_mentioned, created_at`

// GetIngredientMemory returns the user's soft-inventory ingredient rows,
// most-recently-mentioned first.
func (s *Store) GetIngredientMemory(ctx context.Context, userID string) ([]Ingredient, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT `+ingredientCols+` FROM ingredient_memory
		 WHERE user_id = $1 ORDER BY last_mentioned DESC, id DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	list := []Ingredient{}
	for rows.Next() {
		var ing Ingredient
		if err := rows.Scan(&ing.ID, &ing.UserID, &ing.Name, &ing.Quantity,
			&ing.Confidence, &ing.LastMentioned, &ing.CreatedAt); err != nil {
			return nil, err
		}
		list = append(list, ing)
	}
	return list, rows.Err()
}

// UpsertIngredientMemory inserts or updates a soft-inventory ingredient,
// keyed by (user_id, name). Names are expected lowercased by the caller.
func (s *Store) UpsertIngredientMemory(ctx context.Context, userID, name string, quantity *string, confidence float64) error {
	_, err := s.pool.Exec(ctx,
		`INSERT INTO ingredient_memory (user_id, name, quantity, confidence, last_mentioned)
		 VALUES ($1, $2, $3, $4, now())
		 ON CONFLICT (user_id, name)
		 DO UPDATE SET quantity       = EXCLUDED.quantity,
		               confidence     = EXCLUDED.confidence,
		               last_mentioned = now()`,
		userID, name, quantity, confidence)
	return err
}

// DeleteIngredientMemory removes a soft-inventory ingredient by name.
func (s *Store) DeleteIngredientMemory(ctx context.Context, userID, name string) error {
	_, err := s.pool.Exec(ctx,
		`DELETE FROM ingredient_memory WHERE user_id = $1 AND name = $2`, userID, name)
	return err
}
