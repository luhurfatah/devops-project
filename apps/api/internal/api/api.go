package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"kms-api/internal/auth"
	"kms-api/internal/models"
	"kms-api/internal/store"
)

// Handler bundles dependencies for the HTTP handlers.
type Handler struct {
	store *store.Store
	auth  *auth.Manager
}

// New builds the HTTP handler (router + middleware). Read endpoints are public;
// mutating endpoints are wrapped with requireAuth.
func New(s *store.Store, authMgr *auth.Manager) http.Handler {
	h := &Handler{store: s, auth: authMgr}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/health", h.health)
	mux.HandleFunc("POST /api/auth/login", h.login)
	mux.HandleFunc("GET /api/auth/me", h.requireAuth(h.me))

	mux.HandleFunc("GET /api/tree", h.getTree)

	mux.HandleFunc("GET /api/categories", h.listCategories)
	mux.HandleFunc("POST /api/categories", h.requireAuth(h.createCategory))
	mux.HandleFunc("PUT /api/categories/{id}", h.requireAuth(h.updateCategory))
	mux.HandleFunc("DELETE /api/categories/{id}", h.requireAuth(h.deleteCategory))

	mux.HandleFunc("GET /api/documents", h.listDocuments)
	mux.HandleFunc("POST /api/documents", h.requireAuth(h.createDocument))
	mux.HandleFunc("GET /api/documents/{id}", h.getDocument)
	mux.HandleFunc("PUT /api/documents/{id}", h.requireAuth(h.updateDocument))
	mux.HandleFunc("DELETE /api/documents/{id}", h.requireAuth(h.deleteDocument))

	return logging(cors(mux))
}

// ─── Auth ────────────────────────────────────────────────────────────────

func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if !decode(w, r, &in) {
		return
	}
	if !h.auth.Authenticate(in.Username, in.Password) {
		clientError(w, http.StatusUnauthorized, "invalid username or password")
		return
	}
	token, exp, err := h.auth.Issue(in.Username)
	if err != nil {
		serverError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"token":      token,
		"username":   in.Username,
		"expires_at": exp,
	})
}

// me returns the authenticated user; the frontend uses it to confirm a stored
// token is still valid on load.
func (h *Handler) me(w http.ResponseWriter, r *http.Request) {
	claims, _ := h.auth.Validate(bearerToken(r))
	writeJSON(w, http.StatusOK, map[string]string{"username": claims.Sub})
}

// requireAuth rejects requests without a valid bearer token.
func (h *Handler) requireAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if _, err := h.auth.Validate(bearerToken(r)); err != nil {
			clientError(w, http.StatusUnauthorized, "authentication required")
			return
		}
		next(w, r)
	}
}

func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if len(h) > 7 && strings.EqualFold(h[:7], "Bearer ") {
		return h[7:]
	}
	return ""
}

// ─── Health & Tree ───────────────────────────────────────────────────────

func (h *Handler) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (h *Handler) getTree(w http.ResponseWriter, r *http.Request) {
	tree, err := h.store.Tree(r.Context())
	if err != nil {
		serverError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, tree)
}

// ─── Categories ──────────────────────────────────────────────────────────

func (h *Handler) listCategories(w http.ResponseWriter, r *http.Request) {
	cats, err := h.store.ListCategories(r.Context())
	if err != nil {
		serverError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, cats)
}

func (h *Handler) createCategory(w http.ResponseWriter, r *http.Request) {
	var in models.CategoryInput
	if !decode(w, r, &in) {
		return
	}
	if strings.TrimSpace(in.Name) == "" {
		clientError(w, http.StatusBadRequest, "name is required")
		return
	}
	pos := derefInt(in.Position)
	c, err := h.store.CreateCategory(r.Context(), in.Name, store.Slugify(in.Name), pos)
	if errors.Is(err, store.ErrConflict) {
		clientError(w, http.StatusConflict, "a category with that name already exists")
		return
	}
	if err != nil {
		serverError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, c)
}

func (h *Handler) updateCategory(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var in models.CategoryInput
	if !decode(w, r, &in) {
		return
	}
	if strings.TrimSpace(in.Name) == "" {
		clientError(w, http.StatusBadRequest, "name is required")
		return
	}
	c, err := h.store.UpdateCategory(r.Context(), id, in.Name, store.Slugify(in.Name), derefInt(in.Position))
	switch {
	case errors.Is(err, store.ErrNotFound):
		clientError(w, http.StatusNotFound, "category not found")
	case errors.Is(err, store.ErrConflict):
		clientError(w, http.StatusConflict, "a category with that name already exists")
	case err != nil:
		serverError(w, err)
	default:
		writeJSON(w, http.StatusOK, c)
	}
}

func (h *Handler) deleteCategory(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	err := h.store.DeleteCategory(r.Context(), id)
	switch {
	case errors.Is(err, store.ErrNotFound):
		clientError(w, http.StatusNotFound, "category not found")
	case err != nil:
		serverError(w, err)
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}

// ─── Documents ───────────────────────────────────────────────────────────

func (h *Handler) listDocuments(w http.ResponseWriter, r *http.Request) {
	var categoryID int64
	if v := r.URL.Query().Get("category_id"); v != "" {
		categoryID, _ = strconv.ParseInt(v, 10, 64)
	}
	query := strings.TrimSpace(r.URL.Query().Get("q"))
	docs, err := h.store.ListDocuments(r.Context(), categoryID, query)
	if err != nil {
		serverError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, docs)
}

func (h *Handler) getDocument(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	doc, err := h.store.GetDocument(r.Context(), id)
	switch {
	case errors.Is(err, store.ErrNotFound):
		clientError(w, http.StatusNotFound, "document not found")
	case err != nil:
		serverError(w, err)
	default:
		writeJSON(w, http.StatusOK, doc)
	}
}

func (h *Handler) createDocument(w http.ResponseWriter, r *http.Request) {
	var in models.DocumentInput
	if !decode(w, r, &in) {
		return
	}
	if in.CategoryID == 0 {
		clientError(w, http.StatusBadRequest, "category_id is required")
		return
	}
	if strings.TrimSpace(in.Title) == "" {
		clientError(w, http.StatusBadRequest, "title is required")
		return
	}

	slug := uniqueDocSlug(r, h, in.CategoryID, in.Title, 0)
	doc, err := h.store.CreateDocument(r.Context(), in.CategoryID, in.Title, slug, in.Content, derefInt(in.Position))
	if err != nil {
		serverError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, doc)
}

func (h *Handler) updateDocument(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var in models.DocumentInput
	if !decode(w, r, &in) {
		return
	}
	if in.CategoryID == 0 {
		clientError(w, http.StatusBadRequest, "category_id is required")
		return
	}
	if strings.TrimSpace(in.Title) == "" {
		clientError(w, http.StatusBadRequest, "title is required")
		return
	}

	slug := uniqueDocSlug(r, h, in.CategoryID, in.Title, id)
	doc, err := h.store.UpdateDocument(r.Context(), id, in.CategoryID, in.Title, slug, in.Content, derefInt(in.Position))
	switch {
	case errors.Is(err, store.ErrNotFound):
		clientError(w, http.StatusNotFound, "document not found")
	case err != nil:
		serverError(w, err)
	default:
		writeJSON(w, http.StatusOK, doc)
	}
}

func (h *Handler) deleteDocument(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	err := h.store.DeleteDocument(r.Context(), id)
	switch {
	case errors.Is(err, store.ErrNotFound):
		clientError(w, http.StatusNotFound, "document not found")
	case err != nil:
		serverError(w, err)
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}

// uniqueDocSlug finds a slug that is unique within the category by appending a
// numeric suffix when necessary. excludeID lets a document keep its own slug on
// update.
func uniqueDocSlug(r *http.Request, h *Handler, categoryID int64, title string, excludeID int64) string {
	base := store.Slugify(title)
	existing, err := h.store.ListDocuments(r.Context(), categoryID, "")
	if err != nil {
		return base
	}
	taken := map[string]bool{}
	for _, d := range existing {
		if d.ID != excludeID {
			taken[d.Slug] = true
		}
	}
	if !taken[base] {
		return base
	}
	for i := 2; ; i++ {
		candidate := fmt.Sprintf("%s-%d", base, i)
		if !taken[candidate] {
			return candidate
		}
	}
}

// ─── Helpers ─────────────────────────────────────────────────────────────

func pathID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		clientError(w, http.StatusBadRequest, "invalid id")
		return 0, false
	}
	return id, true
}

func decode(w http.ResponseWriter, r *http.Request, dst any) bool {
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		clientError(w, http.StatusBadRequest, "invalid JSON body: "+err.Error())
		return false
	}
	return true
}

func derefInt(p *int) int {
	if p == nil {
		return 0
	}
	return *p
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if v != nil {
		_ = json.NewEncoder(w).Encode(v)
	}
}

func clientError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func serverError(w http.ResponseWriter, err error) {
	log.Printf("server error: %v", err)
	writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal server error"})
}

// ─── Middleware ──────────────────────────────────────────────────────────

func cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start))
	})
}
