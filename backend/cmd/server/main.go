// Command server runs the Sous Chef AI backend: a REST API over the Supabase
// PostgreSQL database with direct OpenAI integration. The behavior it serves
// is defined by the documents in ../../contract/.
package main

import (
	"context"
	"log"
	"net/http"
	"time"

	"souschef/internal/api"
	"souschef/internal/config"
	"souschef/internal/openai"
	"souschef/internal/store"
)

func main() {
	// Load .env in development; in deployed environments real environment
	// variables are already set and the file is simply absent.
	config.LoadDotEnv(".env")

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	st, err := store.New(context.Background(), cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("database: %v", err)
	}
	defer st.Close()

	handler := api.NewServer(st, openai.New(cfg.OpenAIAPIKey), cfg.SupabaseJWTSecret)

	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
		// No WriteTimeout is set on purpose: the chat and recipe endpoints are
		// long-lived Server-Sent Events streams.
	}

	log.Printf("sous-chef backend listening on :%s", cfg.Port)
	if err := srv.ListenAndServe(); err != nil {
		log.Fatalf("server: %v", err)
	}
}
