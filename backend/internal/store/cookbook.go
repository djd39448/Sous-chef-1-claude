package store

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
)

const cookbookCols = `id, user_id, title, content, image_prompt, created_at`

func scanCookbook(row pgx.Row) (CookbookRecipe, error) {
	var c CookbookRecipe
	err := row.Scan(&c.ID, &c.UserID, &c.Title, &c.Content, &c.ImagePrompt, &c.CreatedAt)
	return c, err
}

// ListCookbook returns the user's saved recipes, newest first.
func (s *Store) ListCookbook(ctx context.Context, userID string) ([]CookbookRecipe, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT `+cookbookCols+` FROM cookbook_recipes
		 WHERE user_id = $1 ORDER BY created_at DESC, id DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	list := []CookbookRecipe{}
	for rows.Next() {
		c, err := scanCookbook(rows)
		if err != nil {
			return nil, err
		}
		list = append(list, c)
	}
	return list, rows.Err()
}

// GetCookbookRecipe returns one saved recipe by id, or ErrNotFound.
func (s *Store) GetCookbookRecipe(ctx context.Context, id int) (CookbookRecipe, error) {
	row := s.pool.QueryRow(ctx,
		`SELECT `+cookbookCols+` FROM cookbook_recipes WHERE id = $1`, id)
	c, err := scanCookbook(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return CookbookRecipe{}, ErrNotFound
	}
	return c, err
}

// CreateCookbookRecipe saves a recipe to the cookbook.
func (s *Store) CreateCookbookRecipe(ctx context.Context, userID, title, content string, imagePrompt *string) (CookbookRecipe, error) {
	row := s.pool.QueryRow(ctx,
		`INSERT INTO cookbook_recipes (user_id, title, content, image_prompt)
		 VALUES ($1, $2, $3, $4) RETURNING `+cookbookCols,
		userID, title, content, imagePrompt)
	return scanCookbook(row)
}

// DeleteCookbookRecipe deletes a saved recipe by id.
func (s *Store) DeleteCookbookRecipe(ctx context.Context, id int) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM cookbook_recipes WHERE id = $1`, id)
	return err
}
