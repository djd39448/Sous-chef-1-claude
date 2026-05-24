// Package api implements the HTTP REST surface defined in
// contract/api-spec.md: routing, middleware, response helpers, and the
// per-endpoint handlers.
package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"

	"souschef/internal/openai"
	"souschef/internal/store"
)

// Server holds the dependencies shared by every handler.
type Server struct {
	store *store.Store
	ai    *openai.Client
}

// NewServer builds the HTTP handler: the routed mux wrapped in CORS and the
// provided auth middleware (typically Supabase JWKS verification).
func NewServer(st *store.Store, ai *openai.Client, authMW func(http.Handler) http.Handler) http.Handler {
	s := &Server{store: st, ai: ai}
	mux := http.NewServeMux()
	s.routes(mux)
	return cors(authMW(mux))
}

func (s *Server) routes(mux *http.ServeMux) {
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	// Auth.
	mux.HandleFunc("GET /api/auth/user", s.handleGetUser)

	// Conversations & chat.
	mux.HandleFunc("GET /api/kitchen/conversation", s.handleGetConversation)
	mux.HandleFunc("GET /api/kitchen/conversations", s.handleListConversations)
	mux.HandleFunc("POST /api/kitchen/conversation/new", s.handleNewConversation)
	mux.HandleFunc("GET /api/kitchen/conversation/{id}", s.handleGetConversationByID)
	mux.HandleFunc("POST /api/kitchen/message", s.handleMessage)

	// Meal plans.
	mux.HandleFunc("GET /api/kitchen/meal-plan", s.handleGetMealPlan)
	mux.HandleFunc("GET /api/kitchen/calendar", s.handleCalendar)
	mux.HandleFunc("GET /api/kitchen/week/{weekStartDate}", s.handleGetWeek)
	mux.HandleFunc("POST /api/kitchen/generate-meal-plan", s.handleGenerateMealPlan)
	mux.HandleFunc("POST /api/kitchen/regenerate-days", s.handleRegenerateDays)
	mux.HandleFunc("GET /api/kitchen/meal-plan-day/{id}", s.handleGetMealPlanDay)
	mux.HandleFunc("PATCH /api/kitchen/meal-plan-day/{id}", s.handlePatchMealPlanDay)
	mux.HandleFunc("POST /api/kitchen/generate-recipe/{dayId}", s.handleGenerateRecipe)
	mux.HandleFunc("POST /api/kitchen/recipe-message", s.handleRecipeMessage)

	// Shopping lists.
	mux.HandleFunc("GET /api/kitchen/shopping-list", s.handleGetShoppingList)
	mux.HandleFunc("GET /api/kitchen/shopping-lists", s.handleListShoppingLists)
	mux.HandleFunc("GET /api/kitchen/shopping-list/{identifier}", s.handleGetShoppingListByIdentifier)
	mux.HandleFunc("POST /api/kitchen/generate-shopping-list", s.handleGenerateShoppingList)
	mux.HandleFunc("PATCH /api/kitchen/shopping-item/{id}", s.handlePatchShoppingItem)
	mux.HandleFunc("DELETE /api/kitchen/shopping-items/checked", s.handleClearCheckedItems)

	// Ingredients.
	mux.HandleFunc("GET /api/kitchen/ingredients", s.handleGetIngredients)

	// Cookbook.
	mux.HandleFunc("GET /api/kitchen/cookbook", s.handleListCookbook)
	mux.HandleFunc("GET /api/kitchen/cookbook/{id}", s.handleGetCookbookRecipe)
	mux.HandleFunc("POST /api/kitchen/cookbook", s.handleCreateCookbookRecipe)
	mux.HandleFunc("DELETE /api/kitchen/cookbook/{id}", s.handleDeleteCookbookRecipe)

	// Images.
	mux.HandleFunc("POST /api/kitchen/regenerate-image", s.handleRegenerateImage)
}

// cors permits the iOS app (and a browser debug client) to call the API and
// answers CORS preflight requests.
func cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("Access-Control-Allow-Origin", "*")
		h.Set("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
		h.Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// ---- response helpers

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func decodeJSON(r *http.Request, v any) error {
	return json.NewDecoder(r.Body).Decode(v)
}

// pathInt reads a path wildcard as an integer.
func pathInt(r *http.Request, name string) (int, bool) {
	n, err := strconv.Atoi(r.PathValue(name))
	if err != nil {
		return 0, false
	}
	return n, true
}

// isAllDigits reports whether s is non-empty and consists only of digits.
func isAllDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// trimNum formats a float without a trailing ".0", for human-readable
// quantity strings ("2 lb", not "2.0 lb").
func trimNum(f float64) string {
	return strconv.FormatFloat(f, 'f', -1, 64)
}

// notFoundOr maps a store error to a handler decision: it returns true when
// the caller should stop because a response (404 or 500) has been written.
func writeStoreErr(w http.ResponseWriter, err error, notFoundMsg string) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, notFoundMsg)
		return true
	}
	writeError(w, http.StatusInternalServerError, "internal error")
	return true
}

// ---- server-sent events

type sseWriter struct {
	w  http.ResponseWriter
	fl http.Flusher
}

// newSSE switches the response into Server-Sent Events mode. It must be called
// only after all pre-flight validation has passed, since it commits a 200
// status; errors after this point are delivered as SSE error events.
func newSSE(w http.ResponseWriter) (*sseWriter, bool) {
	fl, ok := w.(http.Flusher)
	if !ok {
		writeError(w, http.StatusInternalServerError, "streaming unsupported")
		return nil, false
	}
	h := w.Header()
	h.Set("Content-Type", "text/event-stream")
	h.Set("Cache-Control", "no-cache")
	h.Set("Connection", "keep-alive")
	w.WriteHeader(http.StatusOK)
	fl.Flush()
	return &sseWriter{w: w, fl: fl}, true
}

// send writes one SSE event: a single `data:` line carrying v as JSON.
func (s *sseWriter) send(v any) {
	data, err := json.Marshal(v)
	if err != nil {
		return
	}
	_, _ = fmt.Fprintf(s.w, "data: %s\n\n", data)
	s.fl.Flush()
}

// sendError writes an SSE error event.
func (s *sseWriter) sendError(msg string) {
	s.send(map[string]string{"error": msg})
}
