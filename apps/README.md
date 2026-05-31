# 🗄️ KMS — Knowledge Management System

A real Knowledge Management System with full **CRUD**, inspired by
[`myoncalldiaries`](../../myoncalldiaries) — but instead of reading static
Markdown files from disk, documents are **stored in PostgreSQL** and served by a
**Go API**, with a **Node/Express** frontend that keeps the same clean reading
experience and adds create / edit / delete.

```
┌────────────┐      /api/*       ┌────────────┐     SQL      ┌────────────┐
│  Browser   │ ───────────────▶  │  web (Node)│ ──────────▶  │            │
│  (SPA UI)  │ ◀───────────────  │  Express   │              │            │
└────────────┘   static + proxy  └─────┬──────┘              │            │
                                        │ proxy /api          │            │
                                        ▼                     │  Postgres  │
                                  ┌────────────┐    pgx       │     16     │
                                  │  api (Go)  │ ──────────▶  │            │
                                  │ net/http   │ ◀──────────  │            │
                                  └────────────┘              └────────────┘
```

## ✨ Features

- **Full CRUD** over categories and Markdown documents, persisted in Postgres.
- **Simple auth** — public reads; a single env-configured admin signs in to
  create / edit / delete. Stateless HMAC-signed bearer tokens (no extra deps).
- **Go API** (`net/http` + `pgx/v5`) with auto-migrations and demo seeding.
- **Postgres full-text search** wired into the sidebar search box.
- **Live Markdown editor** with split-pane preview, syntax highlighting, and
  one-click code copy.
- **Single-origin frontend** — the Node server proxies `/api` to the Go service,
  so the browser never deals with CORS.
- **Docker Compose** brings up `db` + `api` + `web` with one command.
- **Nix flake** dev shell pins the whole toolchain (Go, Node, Docker, psql).

## 📁 Structure

```
project/apps/
├── docker-compose.yml      # db + api + web
├── flake.nix / .envrc      # Nix dev shell (go, node, docker, postgres)
├── .env.example            # configurable ports / credentials
├── api/                    # Go API
│   ├── main.go             # wiring, embedded migrations, graceful shutdown
│   ├── migrations/         # *.sql applied on startup (tracked in schema_migrations)
│   ├── internal/
│   │   ├── config/         # env config
│   │   ├── models/         # Category, Document
│   │   ├── store/          # pgx pool, queries, migrate, seed, slugify
│   │   └── api/            # HTTP handlers, router, middleware
│   └── Dockerfile
└── web/                    # Node/Express frontend
    ├── server.js           # static server + /api reverse proxy
    ├── public/             # index.html, style.css, app.js (the SPA)
    └── Dockerfile
```

## 🚀 Quick start (Docker Compose)

```bash
cd project/apps
cp .env.example .env        # optional — defaults work out of the box
docker compose up --build
```

Then open:

| Service  | URL                              |
|----------|----------------------------------|
| Web UI   | http://localhost:3000            |
| API      | http://localhost:8080/api/health |
| Postgres | localhost:5432 (`kms` / `kms_password`) |

On first boot the API runs migrations and seeds a few demo documents. To start
empty, set `SEED_DATA=false` in `.env`.

## 🧰 Local development (Nix)

```bash
cd project/apps
nix develop            # go, node, docker, psql all on PATH (creates flake.lock)

# Option A — DB in Docker, app processes local:
docker compose up -d db
(cd api && go run .)                       # API on :8080
(cd web && npm install && npm start)       # web on :3000
```

Without Nix you just need Go 1.22+, Node 18+, and a Postgres instance; point the
API at it via `DATABASE_URL`.

## 🔌 API reference

Base path: `/api` (proxied through the web server, or hit `:8080` directly).

🔒 = requires `Authorization: Bearer <token>` (write endpoints).

| Method | Path                  | Auth | Description                              |
|--------|-----------------------|:----:|------------------------------------------|
| GET    | `/health`             |      | Liveness probe                           |
| POST   | `/auth/login`         |      | `{ username, password }` → `{ token, expires_at }` |
| GET    | `/auth/me`            |  🔒  | Returns the signed-in username           |
| GET    | `/tree`               |      | Categories with nested document metadata |
| GET    | `/categories`         |      | List categories                          |
| POST   | `/categories`         |  🔒  | Create `{ "name": "..." }`               |
| PUT    | `/categories/{id}`    |  🔒  | Rename `{ "name": "..." }`               |
| DELETE | `/categories/{id}`    |  🔒  | Delete category (cascades to documents)  |
| GET    | `/documents?category_id=&q=` |  | List/search document metadata        |
| GET    | `/documents/{id}`     |      | Full document (with Markdown body)       |
| POST   | `/documents`          |  🔒  | Create `{ category_id, title, content }` |
| PUT    | `/documents/{id}`     |  🔒  | Update `{ category_id, title, content }` |
| DELETE | `/documents/{id}`     |  🔒  | Delete document                          |

Example:

```bash
# Reads are public
curl -s "localhost:8080/api/documents?q=failover"

# Writes require a token — log in first, then pass it as a Bearer token
TOKEN=$(curl -s localhost:8080/api/auth/login \
  -d '{"username":"admin","password":"admin"}' | jq -r .token)

curl -s localhost:8080/api/categories \
  -H "Authorization: Bearer $TOKEN" -d '{"name":"Runbooks"}'

curl -s localhost:8080/api/documents \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"category_id":1,"title":"DB failover","content":"# Steps\n1. ..."}'
```

## 🔐 Auth

Authentication is intentionally minimal:

- **Reads are public**; create / edit / delete require a signed-in admin.
- A single admin identity is set via `ADMIN_USERNAME` / `ADMIN_PASSWORD`.
- `POST /api/auth/login` returns an **HMAC-signed bearer token** (a compact
  `payload.signature`, signed with `AUTH_SECRET`, valid for `AUTH_TTL_HOURS`).
  Tokens are stateless — there is no session store.
- In the UI, click **Login** (top-right). Once signed in, the **New** buttons and
  per-document **Edit / Delete** appear; the token is kept in `localStorage` and
  sent automatically.

> ⚠️ Set a strong `ADMIN_PASSWORD` and a stable random `AUTH_SECRET`
> (`openssl rand -hex 32`) in `.env`. With the defaults the API logs a warning,
> and a random secret invalidates existing tokens on every restart.

## ⚙️ Configuration

All settings have working defaults; override via `.env` (compose) or env vars.

| Variable        | Default                  | Used by | Notes                          |
|-----------------|--------------------------|---------|--------------------------------|
| `DATABASE_URL`  | `postgres://kms:...`     | api     | pgx connection string          |
| `PORT`          | `8080` (api) / `3000` (web) | both | Listen port                    |
| `SEED_DATA`     | `true`                   | api     | Seed demo content if DB empty  |
| `API_URL`       | `http://api:8080`        | web     | Proxy target for `/api`        |
| `ADMIN_USERNAME`| `admin`                  | api     | Admin login user               |
| `ADMIN_PASSWORD`| `admin`                  | api     | Admin login password (change!) |
| `AUTH_SECRET`   | _(random if unset)_      | api     | HMAC key for signing tokens    |
| `AUTH_TTL_HOURS`| `24`                     | api     | Token lifetime                 |
| `POSTGRES_*`    | `kms` / `kms_password` / `kms` | db | Credentials & DB name      |

## 🗃️ Data model

```sql
categories(id, name, slug UNIQUE, position, created_at)
documents(id, category_id → categories ON DELETE CASCADE,
          title, slug, content, position, created_at, updated_at,
          UNIQUE(category_id, slug))
```

Migrations live in [`api/migrations`](api/migrations) and are applied
automatically on startup, tracked in a `schema_migrations` table.
```
