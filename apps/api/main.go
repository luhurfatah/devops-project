package main

import (
	"context"
	"embed"
	"io/fs"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"kms-api/internal/api"
	"kms-api/internal/auth"
	"kms-api/internal/config"
	"kms-api/internal/store"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

func main() {
	log.SetFlags(log.LstdFlags | log.Lmsgprefix)
	log.SetPrefix("[kms-api] ")

	cfg := config.Load()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	st, err := store.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("database: %v", err)
	}
	defer st.Close()

	// Run migrations from the embedded migrations/ directory.
	sub, err := fs.Sub(migrationsFS, "migrations")
	if err != nil {
		log.Fatalf("migrations fs: %v", err)
	}
	if err := st.Migrate(ctx, sub); err != nil {
		log.Fatalf("migrate: %v", err)
	}

	// Seed demo content on first boot.
	if cfg.SeedData {
		empty, err := st.IsEmpty(ctx)
		if err != nil {
			log.Fatalf("seed check: %v", err)
		}
		if empty {
			if err := st.Seed(ctx); err != nil {
				log.Fatalf("seed: %v", err)
			}
			log.Println("seeded demo content")
		}
	}

	if cfg.AuthSecret == "" {
		log.Println("WARNING: AUTH_SECRET is not set — using a random key; tokens will be invalidated on restart. Set AUTH_SECRET in production.")
	}
	if cfg.AdminPassword == "admin" {
		log.Println("WARNING: using the default admin password 'admin' — set ADMIN_PASSWORD.")
	}
	authMgr := auth.NewManager(cfg.AdminUser, cfg.AdminPassword, cfg.AuthSecret, cfg.TokenTTL)

	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      api.New(st, authMgr),
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Graceful shutdown on SIGINT/SIGTERM.
	go func() {
		sig := make(chan os.Signal, 1)
		signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
		<-sig
		log.Println("shutting down...")
		shutdownCtx, c := context.WithTimeout(context.Background(), 10*time.Second)
		defer c()
		_ = srv.Shutdown(shutdownCtx)
		cancel()
	}()

	log.Printf("listening on :%s", cfg.Port)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("server: %v", err)
	}
	log.Println("stopped")
}
