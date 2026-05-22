// Command migrate applies the SQL migration files in a directory to the
// database named by DATABASE_URL, in filename order.
//
// It is a one-shot tool for a fresh database: the migration SQL uses plain
// CREATE statements and is not idempotent, so it is meant to be run once
// against a new Supabase project.
//
// Usage:
//
//	go run ./cmd/migrate <migrations-dir>
package main

import (
	"context"
	"log"
	"os"
	"path/filepath"
	"sort"

	"github.com/jackc/pgx/v5/pgxpool"

	"souschef/internal/config"
)

func main() {
	if len(os.Args) != 2 {
		log.Fatal("usage: migrate <migrations-dir>")
	}
	dir := os.Args[1]

	// Load DATABASE_URL from backend/.env in development.
	config.LoadDotEnv(".env")
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		log.Fatal("DATABASE_URL is not set")
	}

	files, err := sqlFiles(dir)
	if err != nil {
		log.Fatalf("read migrations: %v", err)
	}

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		log.Fatalf("connect: %v", err)
	}
	defer pool.Close()
	if err := pool.Ping(ctx); err != nil {
		log.Fatalf("ping: %v", err)
	}

	for _, name := range files {
		sql, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			log.Fatalf("read %s: %v", name, err)
		}
		// pgx uses the simple query protocol when Exec is called with no
		// arguments, which runs every statement in the file.
		if _, err := pool.Exec(ctx, string(sql)); err != nil {
			log.Fatalf("apply %s: %v", name, err)
		}
		log.Printf("applied %s", name)
	}
	log.Printf("done — %d migration(s) applied", len(files))
}

// sqlFiles returns the names of the .sql files in dir, sorted.
func sqlFiles(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var files []string
	for _, e := range entries {
		if !e.IsDir() && filepath.Ext(e.Name()) == ".sql" {
			files = append(files, e.Name())
		}
	}
	sort.Strings(files)
	if len(files) == 0 {
		return nil, os.ErrNotExist
	}
	return files, nil
}
