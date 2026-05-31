package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"kms-api/internal/models"
)

// ErrNotFound is returned when a requested row does not exist.
var ErrNotFound = errors.New("not found")

// ErrConflict is returned on a unique-constraint violation (duplicate slug).
var ErrConflict = errors.New("conflict")

// Store wraps a Postgres connection pool and exposes data-access methods.
type Store struct {
	pool *pgxpool.Pool
}

// Connect opens a pgx pool and waits (with retries) until Postgres is ready.
func Connect(ctx context.Context, dsn string) (*Store, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("parse dsn: %w", err)
	}

	var pool *pgxpool.Pool
	// Retry the initial connection: in docker-compose the API may start
	// fractionally before Postgres is accepting connections.
	for attempt := 1; attempt <= 15; attempt++ {
		pool, err = pgxpool.NewWithConfig(ctx, cfg)
		if err == nil {
			if pingErr := pool.Ping(ctx); pingErr == nil {
				return &Store{pool: pool}, nil
			} else {
				err = pingErr
				pool.Close()
			}
		}
		fmt.Printf("waiting for database (attempt %d/15): %v\n", attempt, err)
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(2 * time.Second):
		}
	}
	return nil, fmt.Errorf("could not connect to database: %w", err)
}

// Close releases the connection pool.
func (s *Store) Close() { s.pool.Close() }

// isUniqueViolation reports whether err is a Postgres unique-constraint error.
func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

// ─── Categories ──────────────────────────────────────────────────────────

func (s *Store) ListCategories(ctx context.Context) ([]models.Category, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT id, name, slug, position, created_at
		   FROM categories
		  ORDER BY position, name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Category
	for rows.Next() {
		var c models.Category
		if err := rows.Scan(&c.ID, &c.Name, &c.Slug, &c.Position, &c.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (s *Store) CreateCategory(ctx context.Context, name, slug string, position int) (models.Category, error) {
	var c models.Category
	err := s.pool.QueryRow(ctx,
		`INSERT INTO categories (name, slug, position)
		 VALUES ($1, $2, $3)
		 RETURNING id, name, slug, position, created_at`,
		name, slug, position).
		Scan(&c.ID, &c.Name, &c.Slug, &c.Position, &c.CreatedAt)
	if isUniqueViolation(err) {
		return c, ErrConflict
	}
	return c, err
}

func (s *Store) UpdateCategory(ctx context.Context, id int64, name, slug string, position int) (models.Category, error) {
	var c models.Category
	err := s.pool.QueryRow(ctx,
		`UPDATE categories
		    SET name = $2, slug = $3, position = $4
		  WHERE id = $1
		 RETURNING id, name, slug, position, created_at`,
		id, name, slug, position).
		Scan(&c.ID, &c.Name, &c.Slug, &c.Position, &c.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return c, ErrNotFound
	}
	if isUniqueViolation(err) {
		return c, ErrConflict
	}
	return c, err
}

func (s *Store) DeleteCategory(ctx context.Context, id int64) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM categories WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// ─── Documents ───────────────────────────────────────────────────────────

// ListDocuments returns document metadata, optionally filtered by category and
// a full-text search query.
func (s *Store) ListDocuments(ctx context.Context, categoryID int64, query string) ([]models.DocumentMeta, error) {
	sql := `SELECT id, category_id, title, slug, position, updated_at FROM documents`
	args := []any{}
	conds := []string{}

	if categoryID > 0 {
		args = append(args, categoryID)
		conds = append(conds, fmt.Sprintf("category_id = $%d", len(args)))
	}
	if query != "" {
		args = append(args, query)
		conds = append(conds, fmt.Sprintf(
			"to_tsvector('english', title || ' ' || content) @@ plainto_tsquery('english', $%d)", len(args)))
	}
	if len(conds) > 0 {
		sql += " WHERE " + joinAnd(conds)
	}
	sql += " ORDER BY position, title"

	rows, err := s.pool.Query(ctx, sql, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.DocumentMeta
	for rows.Next() {
		var d models.DocumentMeta
		if err := rows.Scan(&d.ID, &d.CategoryID, &d.Title, &d.Slug, &d.Position, &d.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

func (s *Store) GetDocument(ctx context.Context, id int64) (models.Document, error) {
	var d models.Document
	err := s.pool.QueryRow(ctx,
		`SELECT id, category_id, title, slug, content, position, created_at, updated_at
		   FROM documents WHERE id = $1`, id).
		Scan(&d.ID, &d.CategoryID, &d.Title, &d.Slug, &d.Content, &d.Position, &d.CreatedAt, &d.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return d, ErrNotFound
	}
	return d, err
}

func (s *Store) CreateDocument(ctx context.Context, categoryID int64, title, slug, content string, position int) (models.Document, error) {
	var d models.Document
	err := s.pool.QueryRow(ctx,
		`INSERT INTO documents (category_id, title, slug, content, position)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING id, category_id, title, slug, content, position, created_at, updated_at`,
		categoryID, title, slug, content, position).
		Scan(&d.ID, &d.CategoryID, &d.Title, &d.Slug, &d.Content, &d.Position, &d.CreatedAt, &d.UpdatedAt)
	if isUniqueViolation(err) {
		return d, ErrConflict
	}
	return d, err
}

func (s *Store) UpdateDocument(ctx context.Context, id, categoryID int64, title, slug, content string, position int) (models.Document, error) {
	var d models.Document
	err := s.pool.QueryRow(ctx,
		`UPDATE documents
		    SET category_id = $2, title = $3, slug = $4, content = $5, position = $6, updated_at = now()
		  WHERE id = $1
		 RETURNING id, category_id, title, slug, content, position, created_at, updated_at`,
		id, categoryID, title, slug, content, position).
		Scan(&d.ID, &d.CategoryID, &d.Title, &d.Slug, &d.Content, &d.Position, &d.CreatedAt, &d.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return d, ErrNotFound
	}
	if isUniqueViolation(err) {
		return d, ErrConflict
	}
	return d, err
}

func (s *Store) DeleteDocument(ctx context.Context, id int64) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM documents WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// Tree returns all categories with their documents nested, for the sidebar.
func (s *Store) Tree(ctx context.Context) ([]models.CategoryTree, error) {
	cats, err := s.ListCategories(ctx)
	if err != nil {
		return nil, err
	}

	docs, err := s.ListDocuments(ctx, 0, "")
	if err != nil {
		return nil, err
	}

	byCat := map[int64][]models.DocumentMeta{}
	for _, d := range docs {
		byCat[d.CategoryID] = append(byCat[d.CategoryID], d)
	}

	tree := make([]models.CategoryTree, 0, len(cats))
	for _, c := range cats {
		tree = append(tree, models.CategoryTree{
			Category:  c,
			Documents: byCat[c.ID],
		})
	}
	return tree, nil
}

func joinAnd(conds []string) string {
	out := ""
	for i, c := range conds {
		if i > 0 {
			out += " AND "
		}
		out += c
	}
	return out
}
