-- Categories: top-level sections (folders) in the knowledge base.
CREATE TABLE IF NOT EXISTS categories (
    id         BIGSERIAL PRIMARY KEY,
    name       TEXT        NOT NULL,
    slug       TEXT        NOT NULL UNIQUE,
    position   INT         NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Documents: Markdown articles belonging to a category.
CREATE TABLE IF NOT EXISTS documents (
    id          BIGSERIAL PRIMARY KEY,
    category_id BIGINT      NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
    title       TEXT        NOT NULL,
    slug        TEXT        NOT NULL,
    content     TEXT        NOT NULL DEFAULT '',
    position    INT         NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (category_id, slug)
);

CREATE INDEX IF NOT EXISTS idx_documents_category ON documents (category_id);

-- Full-text search index over title + content.
CREATE INDEX IF NOT EXISTS idx_documents_fts
    ON documents
    USING gin (to_tsvector('english', title || ' ' || content));
