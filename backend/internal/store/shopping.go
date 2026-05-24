package store

import (
	"context"
	"errors"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

const shoppingListCols = `id, user_id, name, week_start_date, meal_plan_id, created_at`
const shoppingItemCols = `id, shopping_list_id, name, quantity, category, checked`

func scanShoppingList(row pgx.Row) (ShoppingList, error) {
	var l ShoppingList
	var wk *time.Time
	err := row.Scan(&l.ID, &l.UserID, &l.Name, &wk, &l.MealPlanID, &l.CreatedAt)
	if wk != nil {
		s := wk.Format("2006-01-02")
		l.WeekStartDate = &s
	}
	return l, err
}

func scanShoppingItem(row pgx.Row) (ShoppingItem, error) {
	var it ShoppingItem
	err := row.Scan(&it.ID, &it.ShoppingListID, &it.Name, &it.Quantity, &it.Category, &it.Checked)
	return it, err
}

// GetMostRecentShoppingList returns the user's newest shopping list, or
// ErrNotFound.
func (s *Store) GetMostRecentShoppingList(ctx context.Context, userID string) (ShoppingList, error) {
	row := s.pool.QueryRow(ctx,
		`SELECT `+shoppingListCols+` FROM shopping_lists
		 WHERE user_id = $1 ORDER BY created_at DESC, id DESC LIMIT 1`, userID)
	l, err := scanShoppingList(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return ShoppingList{}, ErrNotFound
	}
	return l, err
}

// GetShoppingListByID returns one of the user's lists by id, or ErrNotFound.
func (s *Store) GetShoppingListByID(ctx context.Context, userID string, id int) (ShoppingList, error) {
	row := s.pool.QueryRow(ctx,
		`SELECT `+shoppingListCols+` FROM shopping_lists WHERE id = $1 AND user_id = $2`,
		id, userID)
	l, err := scanShoppingList(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return ShoppingList{}, ErrNotFound
	}
	return l, err
}

// GetShoppingListByWeek returns the user's list for a given week, or
// ErrNotFound.
func (s *Store) GetShoppingListByWeek(ctx context.Context, userID, weekStart string) (ShoppingList, error) {
	d, err := parseDate(weekStart)
	if err != nil {
		return ShoppingList{}, ErrNotFound
	}
	row := s.pool.QueryRow(ctx,
		`SELECT `+shoppingListCols+` FROM shopping_lists
		 WHERE user_id = $1 AND week_start_date = $2
		 ORDER BY created_at DESC, id DESC LIMIT 1`, userID, d)
	l, err := scanShoppingList(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return ShoppingList{}, ErrNotFound
	}
	return l, err
}

// ListShoppingLists returns the user's lists, newest first.
func (s *Store) ListShoppingLists(ctx context.Context, userID string) ([]ShoppingList, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT `+shoppingListCols+` FROM shopping_lists
		 WHERE user_id = $1 ORDER BY created_at DESC, id DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	list := []ShoppingList{}
	for rows.Next() {
		l, err := scanShoppingList(rows)
		if err != nil {
			return nil, err
		}
		list = append(list, l)
	}
	return list, rows.Err()
}

// GetShoppingItems returns the items of a list in insertion order.
func (s *Store) GetShoppingItems(ctx context.Context, listID int) ([]ShoppingItem, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT `+shoppingItemCols+` FROM shopping_list_items
		 WHERE shopping_list_id = $1 ORDER BY id ASC`, listID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	list := []ShoppingItem{}
	for rows.Next() {
		it, err := scanShoppingItem(rows)
		if err != nil {
			return nil, err
		}
		list = append(list, it)
	}
	return list, rows.Err()
}

// GetShoppingItem returns one item plus the user id of its owning list, or
// ErrNotFound.
func (s *Store) GetShoppingItem(ctx context.Context, id int) (ShoppingItem, string, error) {
	row := s.pool.QueryRow(ctx,
		`SELECT i.id, i.shopping_list_id, i.name, i.quantity, i.category, i.checked, l.user_id
		 FROM shopping_list_items i
		 JOIN shopping_lists l ON l.id = i.shopping_list_id
		 WHERE i.id = $1`, id)

	var it ShoppingItem
	var owner string
	err := row.Scan(&it.ID, &it.ShoppingListID, &it.Name, &it.Quantity,
		&it.Category, &it.Checked, &owner)
	if errors.Is(err, pgx.ErrNoRows) {
		return ShoppingItem{}, "", ErrNotFound
	}
	return it, owner, err
}

// SetShoppingItemChecked sets an item's checked flag (0 or 1) and returns the
// updated row.
func (s *Store) SetShoppingItemChecked(ctx context.Context, id, checked int) (ShoppingItem, error) {
	row := s.pool.QueryRow(ctx,
		`UPDATE shopping_list_items SET checked = $2 WHERE id = $1
		 RETURNING `+shoppingItemCols, id, checked)
	return scanShoppingItem(row)
}

// DeleteCheckedItems removes every checked item from a list.
func (s *Store) DeleteCheckedItems(ctx context.Context, listID int) error {
	_, err := s.pool.Exec(ctx,
		`DELETE FROM shopping_list_items WHERE shopping_list_id = $1 AND checked = 1`,
		listID)
	return err
}

// CreateShoppingList creates a list. When weekStart is non-nil, any existing
// list for that week is deleted first, so there is one list per week.
func (s *Store) CreateShoppingList(ctx context.Context, userID, name string, weekStart *string, mealPlanID *int) (ShoppingList, error) {
	var wk *time.Time
	if weekStart != nil {
		d, err := parseDate(*weekStart)
		if err != nil {
			return ShoppingList{}, err
		}
		wk = &d
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return ShoppingList{}, err
	}
	defer tx.Rollback(ctx)

	if wk != nil {
		if _, err := tx.Exec(ctx,
			`DELETE FROM shopping_lists WHERE user_id = $1 AND week_start_date = $2`,
			userID, *wk); err != nil {
			return ShoppingList{}, err
		}
	}
	row := tx.QueryRow(ctx,
		`INSERT INTO shopping_lists (user_id, name, week_start_date, meal_plan_id)
		 VALUES ($1, $2, $3, $4) RETURNING `+shoppingListCols,
		userID, name, wk, mealPlanID)
	l, err := scanShoppingList(row)
	if err != nil {
		return ShoppingList{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return ShoppingList{}, err
	}
	return l, nil
}

// InsertShoppingItem adds an item to a list.
func (s *Store) InsertShoppingItem(ctx context.Context, listID int, name string, quantity *string, category string) (ShoppingItem, error) {
	row := s.pool.QueryRow(ctx,
		`INSERT INTO shopping_list_items (shopping_list_id, name, quantity, category)
		 VALUES ($1, $2, $3, $4) RETURNING `+shoppingItemCols,
		listID, name, quantity, category)
	return scanShoppingItem(row)
}

// ShoppingItemUpdate captures partial edits to a shopping_list_items
// row from `PUT /shopping-item/{id}`. Nil pointers mean "don't touch."
// `Quantity`'s pointer-to-pointer dance lets the caller send a literal
// empty string (or null in JSON) to clear the column.
type ShoppingItemUpdate struct {
	Name     *string
	Quantity *string // empty string clears
	Category *string
}

// UpdateShoppingItem applies a partial update and returns the fresh row.
// Builds a dynamic UPDATE so omitted fields keep their existing values.
func (s *Store) UpdateShoppingItem(ctx context.Context, id int, u ShoppingItemUpdate) (ShoppingItem, error) {
	sets := []string{}
	args := []any{id}
	if u.Name != nil {
		sets = append(sets, "name = $"+strconv.Itoa(len(args)+1))
		args = append(args, *u.Name)
	}
	if u.Quantity != nil {
		sets = append(sets, "quantity = $"+strconv.Itoa(len(args)+1))
		if *u.Quantity == "" {
			args = append(args, nil)
		} else {
			args = append(args, *u.Quantity)
		}
	}
	if u.Category != nil {
		sets = append(sets, "category = $"+strconv.Itoa(len(args)+1))
		args = append(args, *u.Category)
	}
	if len(sets) == 0 {
		// No-op — return the current row.
		item, _, err := s.GetShoppingItem(ctx, id)
		return item, err
	}
	row := s.pool.QueryRow(ctx,
		`UPDATE shopping_list_items SET `+strings.Join(sets, ", ")+
			` WHERE id = $1 RETURNING `+shoppingItemCols, args...)
	return scanShoppingItem(row)
}

// DeleteShoppingItem removes a single item by id.
func (s *Store) DeleteShoppingItem(ctx context.Context, id int) error {
	_, err := s.pool.Exec(ctx,
		`DELETE FROM shopping_list_items WHERE id = $1`, id)
	return err
}
