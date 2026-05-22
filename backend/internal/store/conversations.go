package store

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/jackc/pgx/v5"
)

const conversationCols = `id, user_id, title, created_at, updated_at`

func scanConversation(row pgx.Row) (Conversation, error) {
	var c Conversation
	err := row.Scan(&c.ID, &c.UserID, &c.Title, &c.CreatedAt, &c.UpdatedAt)
	return c, err
}

// GetMostRecentConversation returns the user's most recently created
// conversation, or ErrNotFound if they have none.
func (s *Store) GetMostRecentConversation(ctx context.Context, userID string) (Conversation, error) {
	row := s.pool.QueryRow(ctx,
		`SELECT `+conversationCols+` FROM kitchen_conversations
		 WHERE user_id = $1 ORDER BY created_at DESC, id DESC LIMIT 1`, userID)
	c, err := scanConversation(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return Conversation{}, ErrNotFound
	}
	return c, err
}

// GetConversationByID returns a conversation by id, or ErrNotFound.
func (s *Store) GetConversationByID(ctx context.Context, id int) (Conversation, error) {
	row := s.pool.QueryRow(ctx,
		`SELECT `+conversationCols+` FROM kitchen_conversations WHERE id = $1`, id)
	c, err := scanConversation(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return Conversation{}, ErrNotFound
	}
	return c, err
}

// CreateConversation inserts a new conversation with the given title.
func (s *Store) CreateConversation(ctx context.Context, userID, title string) (Conversation, error) {
	row := s.pool.QueryRow(ctx,
		`INSERT INTO kitchen_conversations (user_id, title) VALUES ($1, $2)
		 RETURNING `+conversationCols, userID, title)
	return scanConversation(row)
}

// ListConversations returns the user's conversations, most-recently-updated
// first.
func (s *Store) ListConversations(ctx context.Context, userID string) ([]Conversation, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT `+conversationCols+` FROM kitchen_conversations
		 WHERE user_id = $1 ORDER BY updated_at DESC, id DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	list := []Conversation{}
	for rows.Next() {
		c, err := scanConversation(rows)
		if err != nil {
			return nil, err
		}
		list = append(list, c)
	}
	return list, rows.Err()
}

// TouchConversation bumps a conversation's updated_at to the current time.
func (s *Store) TouchConversation(ctx context.Context, id int) error {
	_, err := s.pool.Exec(ctx,
		`UPDATE kitchen_conversations SET updated_at = now() WHERE id = $1`, id)
	return err
}

const messageCols = `id, conversation_id, role, content, metadata, created_at`

func scanMessage(row pgx.Row) (Message, error) {
	var m Message
	var meta []byte
	err := row.Scan(&m.ID, &m.ConversationID, &m.Role, &m.Content, &meta, &m.CreatedAt)
	m.Metadata = json.RawMessage(meta)
	return m, err
}

func collectMessages(rows pgx.Rows) ([]Message, error) {
	list := []Message{}
	for rows.Next() {
		m, err := scanMessage(rows)
		if err != nil {
			return nil, err
		}
		list = append(list, m)
	}
	return list, rows.Err()
}

// GetMessages returns every message in a conversation, oldest first.
func (s *Store) GetMessages(ctx context.Context, conversationID int) ([]Message, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT `+messageCols+` FROM kitchen_messages
		 WHERE conversation_id = $1 ORDER BY created_at ASC, id ASC`, conversationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return collectMessages(rows)
}

// GetRecentMessages returns up to limit of a conversation's most recent
// messages, excluding the message with id excludeID, ordered oldest first.
func (s *Store) GetRecentMessages(ctx context.Context, conversationID, excludeID, limit int) ([]Message, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT `+messageCols+` FROM kitchen_messages
		 WHERE conversation_id = $1 AND id <> $2
		 ORDER BY created_at DESC, id DESC LIMIT $3`, conversationID, excludeID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	msgs, err := collectMessages(rows)
	if err != nil {
		return nil, err
	}
	// The query returns newest-first; reverse to chronological order.
	for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
		msgs[i], msgs[j] = msgs[j], msgs[i]
	}
	return msgs, nil
}

// InsertMessage stores a message in a conversation.
func (s *Store) InsertMessage(ctx context.Context, conversationID int, role, content string) (Message, error) {
	row := s.pool.QueryRow(ctx,
		`INSERT INTO kitchen_messages (conversation_id, role, content)
		 VALUES ($1, $2, $3) RETURNING `+messageCols, conversationID, role, content)
	return scanMessage(row)
}
