// Package store is the data-access layer over the Supabase PostgreSQL
// database. It connects directly with a service-role-level credential and
// bypasses row-level security; per-user ownership is enforced by the API
// layer, faithful to the original Express server (see contract RLS note).
package store

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound is returned by lookups when the requested row does not exist.
var ErrNotFound = errors.New("not found")

// Store wraps a PostgreSQL connection pool.
type Store struct {
	pool *pgxpool.Pool
}

// New opens a connection pool to the database at databaseURL and verifies it
// with a ping.
func New(ctx context.Context, databaseURL string) (*Store, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, err
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, err
	}
	return &Store{pool: pool}, nil
}

// Close releases the connection pool.
func (s *Store) Close() {
	s.pool.Close()
}

// parseDate parses a YYYY-MM-DD string into a time.Time at UTC midnight, the
// form the PostgreSQL date codec expects.
func parseDate(s string) (time.Time, error) {
	return time.Parse("2006-01-02", s)
}

func ptrFloat(f float64) *float64 { return &f }
