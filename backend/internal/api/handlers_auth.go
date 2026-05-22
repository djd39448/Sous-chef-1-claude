package api

import (
	"net/http"

	"souschef/internal/auth"
)

// handleGetUser serves GET /api/kitchen/../auth/user — the caller's profile.
func (s *Server) handleGetUser(w http.ResponseWriter, r *http.Request) {
	profile, err := s.store.GetProfile(r.Context(), auth.UserID(r.Context()))
	if writeStoreErr(w, err, "profile not found") {
		return
	}
	writeJSON(w, http.StatusOK, profile)
}
