package store

import (
	"context"
	"errors"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"
)

const cookbookCols = `id, user_id, title, content, image_prompt, thumbnail_url, created_at`

func scanCookbook(row pgx.Row) (CookbookRecipe, error) {
	var c CookbookRecipe
	err := row.Scan(&c.ID, &c.UserID, &c.Title, &c.Content, &c.ImagePrompt, &c.ThumbnailURL, &c.CreatedAt)
	return c, err
}

// SetCookbookImage stores a generated thumbnail URL on a cookbook
// recipe. Persists across launches so the saved-recipe hero is
// permanent. Column is `thumbnail_url` to match the original schema.
func (s *Store) SetCookbookImage(ctx context.Context, id int, imageURL string) error {
	_, err := s.pool.Exec(ctx,
		`UPDATE cookbook_recipes SET thumbnail_url = $2 WHERE id = $1`, id, imageURL)
	return err
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

// CookbookUpdate captures the fields a PUT /cookbook/{id} caller may
// change. Pointers distinguish "absent" from "set to nil" — a nil
// pointer means "don't touch this column."
type CookbookUpdate struct {
	Title       *string
	Content     *string
	ImagePrompt *string // double-nil-able: pass a non-nil *string whose value is "" to clear
}

// UpdateCookbookRecipe applies a partial update and returns the fresh
// row. Builds a dynamic UPDATE so columns the caller didn't set keep
// their existing values.
func (s *Store) UpdateCookbookRecipe(ctx context.Context, id int, u CookbookUpdate) (CookbookRecipe, error) {
	sets := []string{}
	args := []any{id}
	if u.Title != nil {
		sets = append(sets, "title = $"+strconv.Itoa(len(args)+1))
		args = append(args, *u.Title)
	}
	if u.Content != nil {
		sets = append(sets, "content = $"+strconv.Itoa(len(args)+1))
		args = append(args, *u.Content)
	}
	if u.ImagePrompt != nil {
		sets = append(sets, "image_prompt = $"+strconv.Itoa(len(args)+1))
		// `*string` whose value is "" → store NULL so the row drops the
		// prompt entirely when the caller clears it.
		if *u.ImagePrompt == "" {
			args = append(args, nil)
		} else {
			args = append(args, *u.ImagePrompt)
		}
	}
	if len(sets) == 0 {
		return s.GetCookbookRecipe(ctx, id)
	}
	row := s.pool.QueryRow(ctx,
		`UPDATE cookbook_recipes SET `+strings.Join(sets, ", ")+
			` WHERE id = $1 RETURNING `+cookbookCols, args...)
	return scanCookbook(row)
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
