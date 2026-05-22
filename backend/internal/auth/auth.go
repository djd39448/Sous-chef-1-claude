// Package auth validates Supabase Auth access tokens and carries the
// authenticated user id on the request context.
package auth

import (
	"context"
	"net/http"
	"strings"

	"github.com/golang-jwt/jwt/v5"
)

type ctxKey int

const userIDKey ctxKey = 0

// Middleware returns net/http middleware that validates the Supabase Auth
// access token on the Authorization header. Supabase signs access tokens with
// the project JWT secret (HS256); the "sub" claim is the user's UUID. The
// /healthz path is exempt so load balancers can probe it unauthenticated.
func Middleware(jwtSecret string) func(http.Handler) http.Handler {
	secret := []byte(jwtSecret)
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path == "/healthz" {
				next.ServeHTTP(w, r)
				return
			}

			raw, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
			if !ok || strings.TrimSpace(raw) == "" {
				unauthorized(w)
				return
			}

			claims := jwt.MapClaims{}
			token, err := jwt.ParseWithClaims(strings.TrimSpace(raw), claims,
				func(*jwt.Token) (any, error) { return secret, nil },
				jwt.WithValidMethods([]string{"HS256"}))
			if err != nil || !token.Valid {
				unauthorized(w)
				return
			}

			sub, _ := claims["sub"].(string)
			if sub == "" {
				unauthorized(w)
				return
			}

			ctx := context.WithValue(r.Context(), userIDKey, sub)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// UserID returns the authenticated user id stored on the request context by
// Middleware. It is empty only if called outside an authenticated request.
func UserID(ctx context.Context) string {
	id, _ := ctx.Value(userIDKey).(string)
	return id
}

func unauthorized(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusUnauthorized)
	_, _ = w.Write([]byte(`{"error":"unauthorized"}`))
}
