package store

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
)

// GetProfile returns the profile row for a user, or ErrNotFound. The row is
// created automatically on sign-up by a database trigger.
func (s *Store) GetProfile(ctx context.Context, userID string) (Profile, error) {
	row := s.pool.QueryRow(ctx,
		`SELECT id, email, first_name, last_name, profile_image_url, created_at, updated_at
		 FROM profiles WHERE id = $1`, userID)

	var p Profile
	err := row.Scan(&p.ID, &p.Email, &p.FirstName, &p.LastName,
		&p.ProfileImageURL, &p.CreatedAt, &p.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Profile{}, ErrNotFound
	}
	return p, err
}
