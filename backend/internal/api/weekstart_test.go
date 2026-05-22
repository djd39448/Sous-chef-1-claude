package api

import (
	"testing"
	"time"
)

func TestWeekStart(t *testing.T) {
	cases := []struct{ in, want string }{
		{"2026-05-18", "2026-05-18"}, // Monday  -> itself
		{"2026-05-22", "2026-05-18"}, // Friday  -> that week's Monday
		{"2026-05-24", "2026-05-18"}, // Sunday  -> the preceding Monday
		{"2026-01-01", "2025-12-29"}, // Thursday, crossing the year boundary
	}
	for _, c := range cases {
		in, err := time.Parse("2006-01-02", c.in)
		if err != nil {
			t.Fatalf("bad test date %q: %v", c.in, err)
		}
		if got := weekStart(in); got != c.want {
			t.Errorf("weekStart(%s) = %s, want %s", c.in, got, c.want)
		}
	}
}
