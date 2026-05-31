package models

import "time"

// Category is a top-level grouping of documents (like a folder/section).
type Category struct {
	ID        int64     `json:"id"`
	Name      string    `json:"name"`
	Slug      string    `json:"slug"`
	Position  int       `json:"position"`
	CreatedAt time.Time `json:"created_at"`
}

// Document is a single knowledge-base article stored as Markdown.
type Document struct {
	ID         int64     `json:"id"`
	CategoryID int64     `json:"category_id"`
	Title      string    `json:"title"`
	Slug       string    `json:"slug"`
	Content    string    `json:"content"`
	Position   int       `json:"position"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

// DocumentMeta is a lightweight document representation used in listings and
// the navigation tree (no heavy Markdown body).
type DocumentMeta struct {
	ID         int64     `json:"id"`
	CategoryID int64     `json:"category_id"`
	Title      string    `json:"title"`
	Slug       string    `json:"slug"`
	Position   int       `json:"position"`
	UpdatedAt  time.Time `json:"updated_at"`
}

// CategoryTree is a category with its documents nested for the sidebar.
type CategoryTree struct {
	Category
	Documents []DocumentMeta `json:"documents"`
}

// CategoryInput is the request body for creating/updating a category.
type CategoryInput struct {
	Name     string `json:"name"`
	Position *int   `json:"position"`
}

// DocumentInput is the request body for creating/updating a document.
type DocumentInput struct {
	CategoryID int64  `json:"category_id"`
	Title      string `json:"title"`
	Content    string `json:"content"`
	Position   *int   `json:"position"`
}
