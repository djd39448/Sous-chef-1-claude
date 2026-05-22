package api

import "time"

// weekStart returns the Monday of the week containing t, formatted as
// YYYY-MM-DD. It reproduces the original getWeekStartDate() exactly (see
// contract/ai-behavior.md → "Week-start helper") so plan and list weeks line
// up across the backend and iOS tracks.
func weekStart(t time.Time) string {
	weekday := int(t.Weekday()) // Sunday=0 .. Saturday=6
	offset := 1 - weekday
	if weekday == 0 {
		offset = -6
	}
	return t.AddDate(0, 0, offset).Format("2006-01-02")
}

// currentWeekStart returns the Monday of the current week, in UTC.
func currentWeekStart() string {
	return weekStart(time.Now().UTC())
}
