package config

import (
	"os"
	"strconv"
	"time"
)

// Config holds runtime configuration sourced from the environment.
type Config struct {
	DatabaseURL   string
	Port          string
	SeedData      bool
	AdminUser     string
	AdminPassword string
	AuthSecret    string        // HMAC signing key for tokens (empty => random at startup)
	TokenTTL      time.Duration // how long an issued token stays valid
}

// Load reads configuration from environment variables, applying sane defaults
// for local development.
func Load() Config {
	return Config{
		DatabaseURL:   env("DATABASE_URL", "postgres://kms:kms_password@localhost:5432/kms?sslmode=disable"),
		Port:          env("PORT", "8080"),
		SeedData:      envBool("SEED_DATA", true),
		AdminUser:     env("ADMIN_USERNAME", "admin"),
		AdminPassword: env("ADMIN_PASSWORD", "admin"),
		AuthSecret:    env("AUTH_SECRET", ""),
		TokenTTL:      time.Duration(envInt("AUTH_TTL_HOURS", 24)) * time.Hour,
	}
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envBool(key string, fallback bool) bool {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	b, err := strconv.ParseBool(v)
	if err != nil {
		return fallback
	}
	return b
}

func envInt(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return fallback
	}
	return n
}
