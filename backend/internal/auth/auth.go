// Package auth validates Supabase Auth access tokens and carries the
// authenticated user id on the request context.
//
// Supabase projects sign Auth-issued JWTs with asymmetric signing keys
// (ES256 by default; RS256 historically). The verification keys are
// published at the project's JWKS endpoint
// (`<project-url>/auth/v1/.well-known/jwks.json`) — this package fetches,
// caches, and refreshes those keys via the `keyfunc` library and verifies
// every incoming bearer token against them.
package auth

import (
	"context"
	"fmt"
	"net/http"
	"strings"

	"github.com/MicahParks/keyfunc/v3"
	"github.com/golang-jwt/jwt/v5"
)

type ctxKey int

const userIDKey ctxKey = 0

// Middleware builds net/http middleware that validates the
// `Authorization: Bearer <jwt>` header against the JWKS at jwksURL.
// The /healthz path is exempt so load balancers can probe it.
//
// Keys are fetched at startup (the constructor returns an error if the
// JWKS is unreachable or malformed) and refreshed in the background by
// keyfunc; an unknown `kid` on an incoming token triggers a one-off
// refresh inside keyfunc as well.
func Middleware(jwksURL string) (func(http.Handler) http.Handler, error) {
	if strings.TrimSpace(jwksURL) == "" {
		return nil, fmt.Errorf("jwks url is empty")
	}
	kf, err := keyfunc.NewDefault([]string{jwksURL})
	if err != nil {
		return nil, fmt.Errorf("init JWKS from %s: %w", jwksURL, err)
	}

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
			token, err := jwt.ParseWithClaims(strings.TrimSpace(raw), claims, kf.Keyfunc,
				jwt.WithValidMethods([]string{"ES256", "RS256"}))
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
	}, nil
}

// UserID returns the authenticated user id stored on the request context
// by Middleware. It is empty only if called outside an authenticated
// request (e.g. /healthz or a test).
func UserID(ctx context.Context) string {
	id, _ := ctx.Value(userIDKey).(string)
	return id
}

func unauthorized(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusUnauthorized)
	_, _ = w.Write([]byte(`{"error":"unauthorized"}`))
}
