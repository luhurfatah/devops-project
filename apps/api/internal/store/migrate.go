package store

import (
	"context"
	"fmt"
	"io/fs"
	"sort"
)

// Migrate applies every *.sql file found in migrationsFS (in lexical order)
// that has not yet been recorded in the schema_migrations table. Each file is
// applied inside its own transaction so a failure leaves the DB consistent.
func (s *Store) Migrate(ctx context.Context, migrationsFS fs.FS) error {
	if _, err := s.pool.Exec(ctx,
		`CREATE TABLE IF NOT EXISTS schema_migrations (
			version    TEXT PRIMARY KEY,
			applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
		)`); err != nil {
		return fmt.Errorf("create schema_migrations: %w", err)
	}

	entries, err := fs.Glob(migrationsFS, "*.sql")
	if err != nil {
		return err
	}
	sort.Strings(entries)

	for _, name := range entries {
		var exists bool
		if err := s.pool.QueryRow(ctx,
			`SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version = $1)`, name).
			Scan(&exists); err != nil {
			return err
		}
		if exists {
			continue
		}

		sqlBytes, err := fs.ReadFile(migrationsFS, name)
		if err != nil {
			return err
		}

		tx, err := s.pool.Begin(ctx)
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, string(sqlBytes)); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("apply migration %s: %w", name, err)
		}
		if _, err := tx.Exec(ctx,
			`INSERT INTO schema_migrations (version) VALUES ($1)`, name); err != nil {
			_ = tx.Rollback(ctx)
			return err
		}
		if err := tx.Commit(ctx); err != nil {
			return err
		}
		fmt.Printf("applied migration: %s\n", name)
	}
	return nil
}

// IsEmpty reports whether there are no categories yet (used to decide seeding).
func (s *Store) IsEmpty(ctx context.Context) (bool, error) {
	var count int
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM categories`).Scan(&count); err != nil {
		return false, err
	}
	return count == 0, nil
}
