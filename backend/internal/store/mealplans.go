package store

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

const mealPlanCols = `id, user_id, week_start_date, created_at, updated_at`
const mealPlanDayCols = `id, meal_plan_id, day_of_week, recipe_id, meal_name, notes, recipe_content, recipe_image_prompt, image_url`

// MealInput is one meal to place into a plan.
type MealInput struct {
	DayOfWeek int
	MealName  string
	Notes     *string
}

func scanMealPlan(row pgx.Row) (MealPlan, error) {
	var p MealPlan
	var wk time.Time
	err := row.Scan(&p.ID, &p.UserID, &wk, &p.CreatedAt, &p.UpdatedAt)
	p.WeekStartDate = wk.Format("2006-01-02")
	return p, err
}

func scanMealPlanDay(row pgx.Row) (MealPlanDay, error) {
	var d MealPlanDay
	err := row.Scan(&d.ID, &d.MealPlanID, &d.DayOfWeek, &d.RecipeID,
		&d.MealName, &d.Notes, &d.RecipeContent, &d.RecipeImagePrompt, &d.ImageURL)
	return d, err
}

// GetMostRecentMealPlan returns the user's most recently created meal plan,
// or ErrNotFound.
func (s *Store) GetMostRecentMealPlan(ctx context.Context, userID string) (MealPlan, error) {
	row := s.pool.QueryRow(ctx,
		`SELECT `+mealPlanCols+` FROM meal_plans
		 WHERE user_id = $1 ORDER BY created_at DESC, id DESC LIMIT 1`, userID)
	p, err := scanMealPlan(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return MealPlan{}, ErrNotFound
	}
	return p, err
}

// GetMealPlanByWeek returns the user's plan for a given week (a Monday date),
// or ErrNotFound.
func (s *Store) GetMealPlanByWeek(ctx context.Context, userID, weekStart string) (MealPlan, error) {
	d, err := parseDate(weekStart)
	if err != nil {
		return MealPlan{}, ErrNotFound
	}
	row := s.pool.QueryRow(ctx,
		`SELECT `+mealPlanCols+` FROM meal_plans
		 WHERE user_id = $1 AND week_start_date = $2`, userID, d)
	p, err := scanMealPlan(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return MealPlan{}, ErrNotFound
	}
	return p, err
}

// ListMealPlans returns all of the user's plans, newest week first.
func (s *Store) ListMealPlans(ctx context.Context, userID string) ([]MealPlan, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT `+mealPlanCols+` FROM meal_plans
		 WHERE user_id = $1 ORDER BY week_start_date DESC, id DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	list := []MealPlan{}
	for rows.Next() {
		p, err := scanMealPlan(rows)
		if err != nil {
			return nil, err
		}
		list = append(list, p)
	}
	return list, rows.Err()
}

// GetMealPlanDays returns a plan's days in insertion order.
func (s *Store) GetMealPlanDays(ctx context.Context, mealPlanID int) ([]MealPlanDay, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT `+mealPlanDayCols+` FROM meal_plan_days
		 WHERE meal_plan_id = $1 ORDER BY id ASC`, mealPlanID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	list := []MealPlanDay{}
	for rows.Next() {
		d, err := scanMealPlanDay(rows)
		if err != nil {
			return nil, err
		}
		list = append(list, d)
	}
	return list, rows.Err()
}

// GetMealPlanWithDays loads a plan's days and bundles them with the plan.
func (s *Store) GetMealPlanWithDays(ctx context.Context, plan MealPlan) (MealPlanWithDays, error) {
	days, err := s.GetMealPlanDays(ctx, plan.ID)
	if err != nil {
		return MealPlanWithDays{}, err
	}
	return MealPlanWithDays{MealPlan: plan, Days: days}, nil
}

// GetMealPlanDay returns one meal-plan day plus the user id of the plan that
// owns it, or ErrNotFound.
func (s *Store) GetMealPlanDay(ctx context.Context, id int) (MealPlanDay, string, error) {
	row := s.pool.QueryRow(ctx,
		`SELECT d.id, d.meal_plan_id, d.day_of_week, d.recipe_id, d.meal_name,
		        d.notes, d.recipe_content, d.recipe_image_prompt, d.image_url, p.user_id
		 FROM meal_plan_days d
		 JOIN meal_plans p ON p.id = d.meal_plan_id
		 WHERE d.id = $1`, id)

	var d MealPlanDay
	var owner string
	err := row.Scan(&d.ID, &d.MealPlanID, &d.DayOfWeek, &d.RecipeID, &d.MealName,
		&d.Notes, &d.RecipeContent, &d.RecipeImagePrompt, &d.ImageURL, &owner)
	if errors.Is(err, pgx.ErrNoRows) {
		return MealPlanDay{}, "", ErrNotFound
	}
	return d, owner, err
}

// SetMealPlanDayRecipe stores generated recipe content and an image prompt on
// a meal-plan day.
func (s *Store) SetMealPlanDayRecipe(ctx context.Context, id int, content, imagePrompt string) error {
	_, err := s.pool.Exec(ctx,
		`UPDATE meal_plan_days SET recipe_content = $2, recipe_image_prompt = $3
		 WHERE id = $1`, id, content, imagePrompt)
	return err
}

// UpdateMealPlanDayMeal swaps a day's meal name and notes, and clears any
// previously generated recipe content, image prompt, and stored image —
// the old image was of the old dish, so leaving it would be misleading.
func (s *Store) UpdateMealPlanDayMeal(ctx context.Context, id int, mealName string, notes *string) error {
	_, err := s.pool.Exec(ctx,
		`UPDATE meal_plan_days
		 SET meal_name = $2, notes = $3,
		     recipe_content = NULL, recipe_image_prompt = NULL, image_url = NULL
		 WHERE id = $1`, id, mealName, notes)
	return err
}

// SwapMealPlanDays atomically swaps the dish content between two
// meal-plan days — meal_name, notes, recipe_content, recipe_image_prompt,
// image_url — while leaving day_of_week, meal_plan_id, and the row ids
// fixed. Used by the Plan-tab drag-to-reorder flow: the *meal* moves to
// a different day; the day's position in the week doesn't. Returns the
// two fresh rows in (aFresh, bFresh) order. Both ids must belong to the
// same meal plan; ownership is enforced by the caller.
func (s *Store) SwapMealPlanDays(ctx context.Context, aID, bID int) (MealPlanDay, MealPlanDay, error) {
	if aID == bID {
		return MealPlanDay{}, MealPlanDay{}, errors.New("cannot swap a day with itself")
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return MealPlanDay{}, MealPlanDay{}, err
	}
	defer tx.Rollback(ctx)

	// Read both rows under the transaction so concurrent updates can't
	// interleave between read and write. SELECT ... FOR UPDATE locks the
	// rows until commit/rollback.
	loadOne := func(id int) (MealPlanDay, error) {
		row := tx.QueryRow(ctx,
			`SELECT `+mealPlanDayCols+` FROM meal_plan_days
			 WHERE id = $1 FOR UPDATE`, id)
		return scanMealPlanDay(row)
	}
	a, err := loadOne(aID)
	if errors.Is(err, pgx.ErrNoRows) {
		return MealPlanDay{}, MealPlanDay{}, ErrNotFound
	}
	if err != nil {
		return MealPlanDay{}, MealPlanDay{}, err
	}
	b, err := loadOne(bID)
	if errors.Is(err, pgx.ErrNoRows) {
		return MealPlanDay{}, MealPlanDay{}, ErrNotFound
	}
	if err != nil {
		return MealPlanDay{}, MealPlanDay{}, err
	}
	if a.MealPlanID != b.MealPlanID {
		return MealPlanDay{}, MealPlanDay{}, errors.New("cannot swap days from different plans")
	}

	// Write A's content into B's row, and vice versa.
	const updateSQL = `UPDATE meal_plan_days
	    SET meal_name = $2, notes = $3, recipe_content = $4,
	        recipe_image_prompt = $5, image_url = $6
	    WHERE id = $1`
	if _, err := tx.Exec(ctx, updateSQL,
		bID, a.MealName, a.Notes, a.RecipeContent, a.RecipeImagePrompt, a.ImageURL); err != nil {
		return MealPlanDay{}, MealPlanDay{}, err
	}
	if _, err := tx.Exec(ctx, updateSQL,
		aID, b.MealName, b.Notes, b.RecipeContent, b.RecipeImagePrompt, b.ImageURL); err != nil {
		return MealPlanDay{}, MealPlanDay{}, err
	}

	// Read back the post-swap rows so the caller has the canonical state.
	aFresh, err := loadOne(aID)
	if err != nil {
		return MealPlanDay{}, MealPlanDay{}, err
	}
	bFresh, err := loadOne(bID)
	if err != nil {
		return MealPlanDay{}, MealPlanDay{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return MealPlanDay{}, MealPlanDay{}, err
	}
	return aFresh, bFresh, nil
}

// SetMealPlanDayImage stores a generated image (data:image/png;base64,…)
// URL on a meal-plan day. Called after a successful /regenerate-image
// for an mpd target. The URL persists across launches so the iOS hero
// stays the same until the user explicitly regenerates.
func (s *Store) SetMealPlanDayImage(ctx context.Context, id int, imageURL string) error {
	_, err := s.pool.Exec(ctx,
		`UPDATE meal_plan_days SET image_url = $2 WHERE id = $1`, id, imageURL)
	return err
}

// ReplaceMealPlan replaces the user's plan for a week with a new set of meals,
// in a single transaction. Any existing plan for that week is deleted first
// (cascading to its days).
func (s *Store) ReplaceMealPlan(ctx context.Context, userID, weekStart string, meals []MealInput) (MealPlanWithDays, error) {
	wk, err := parseDate(weekStart)
	if err != nil {
		return MealPlanWithDays{}, err
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return MealPlanWithDays{}, err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx,
		`DELETE FROM meal_plans WHERE user_id = $1 AND week_start_date = $2`,
		userID, wk); err != nil {
		return MealPlanWithDays{}, err
	}

	var plan MealPlan
	var wkOut time.Time
	if err := tx.QueryRow(ctx,
		`INSERT INTO meal_plans (user_id, week_start_date) VALUES ($1, $2)
		 RETURNING `+mealPlanCols, userID, wk).
		Scan(&plan.ID, &plan.UserID, &wkOut, &plan.CreatedAt, &plan.UpdatedAt); err != nil {
		return MealPlanWithDays{}, err
	}
	plan.WeekStartDate = wkOut.Format("2006-01-02")

	days := []MealPlanDay{}
	for _, m := range meals {
		var d MealPlanDay
		if err := tx.QueryRow(ctx,
			`INSERT INTO meal_plan_days (meal_plan_id, day_of_week, meal_name, notes)
			 VALUES ($1, $2, $3, $4) RETURNING `+mealPlanDayCols,
			plan.ID, m.DayOfWeek, m.MealName, m.Notes).
			Scan(&d.ID, &d.MealPlanID, &d.DayOfWeek, &d.RecipeID, &d.MealName,
				&d.Notes, &d.RecipeContent, &d.RecipeImagePrompt, &d.ImageURL); err != nil {
			return MealPlanWithDays{}, err
		}
		days = append(days, d)
	}

	if err := tx.Commit(ctx); err != nil {
		return MealPlanWithDays{}, err
	}
	return MealPlanWithDays{MealPlan: plan, Days: days}, nil
}
