// Package config loads runtime configuration from the environment.
package config

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// Config holds the runtime configuration for the backend.
type Config struct {
	Port              string // HTTP listen port
	DatabaseURL       string // Supabase PostgreSQL connection string
	SupabaseJWTSecret string // HS256 secret used to verify Supabase Auth tokens
	OpenAIAPIKey      string // OpenAI API key
}

// Load reads configuration from environment variables and verifies that the
// required values are present.
func Load() (Config, error) {
	c := Config{
		Port:              getenv("PORT", "8080"),
		DatabaseURL:       os.Getenv("DATABASE_URL"),
		SupabaseJWTSecret: os.Getenv("SUPABASE_JWT_SECRET"),
		OpenAIAPIKey:      os.Getenv("OPENAI_API_KEY"),
	}

	var missing []string
	if c.DatabaseURL == "" {
		missing = append(missing, "DATABASE_URL")
	}
	if c.SupabaseJWTSecret == "" {
		missing = append(missing, "SUPABASE_JWT_SECRET")
	}
	if c.OpenAIAPIKey == "" {
		missing = append(missing, "OPENAI_API_KEY")
	}
	if len(missing) > 0 {
		return Config{}, fmt.Errorf("missing required environment variables: %s", strings.Join(missing, ", "))
	}
	return c, nil
}

// LoadDotEnv reads KEY=VALUE lines from the file at path into the process
// environment, without overwriting variables that are already set. A missing
// file is not an error: in deployed environments real environment variables
// are used instead.
func LoadDotEnv(path string) {
	f, err := os.Open(path)
	if err != nil {
		return
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, val, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		val = strings.Trim(strings.TrimSpace(val), `"'`)
		if _, exists := os.LookupEnv(key); !exists {
			_ = os.Setenv(key, val)
		}
	}
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
