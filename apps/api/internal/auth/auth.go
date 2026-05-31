// Package auth provides a tiny stateless authentication layer: a single admin
// identity (configured via env) and HMAC-signed bearer tokens. No external
// dependencies — tokens are a minimal signed `payload.signature` pair, similar
// in spirit to a JWT but deliberately small.
package auth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"time"
)

// ErrInvalidToken is returned when a token is malformed, tampered with, or expired.
var ErrInvalidToken = errors.New("invalid or expired token")

// Claims is the token payload.
type Claims struct {
	Sub string `json:"sub"` // subject (username)
	Exp int64  `json:"exp"` // expiry, unix seconds
}

// Manager authenticates the admin user and issues/validates tokens.
type Manager struct {
	user   string
	pass   string
	secret []byte
	ttl    time.Duration
}

// NewManager builds a Manager. If secret is empty a random one is generated,
// which means tokens will not survive a process restart.
func NewManager(user, pass, secret string, ttl time.Duration) *Manager {
	key := []byte(secret)
	if len(key) == 0 {
		key = make([]byte, 32)
		_, _ = rand.Read(key)
	}
	return &Manager{user: user, pass: pass, secret: key, ttl: ttl}
}

// Authenticate verifies admin credentials using constant-time comparisons.
func (m *Manager) Authenticate(user, pass string) bool {
	uOK := subtle.ConstantTimeCompare([]byte(user), []byte(m.user)) == 1
	pOK := subtle.ConstantTimeCompare([]byte(pass), []byte(m.pass)) == 1
	return uOK && pOK
}

// Issue creates a signed token for the given subject and returns it with its
// expiry time.
func (m *Manager) Issue(subject string) (string, time.Time, error) {
	exp := time.Now().Add(m.ttl)
	payload, err := json.Marshal(Claims{Sub: subject, Exp: exp.Unix()})
	if err != nil {
		return "", time.Time{}, err
	}
	body := b64(payload)
	token := body + "." + b64(m.sign([]byte(body)))
	return token, exp, nil
}

// Validate checks a token's signature and expiry, returning its claims.
func (m *Manager) Validate(token string) (Claims, error) {
	var c Claims
	parts := strings.Split(token, ".")
	if len(parts) != 2 {
		return c, ErrInvalidToken
	}
	sig, err := unb64(parts[1])
	if err != nil {
		return c, ErrInvalidToken
	}
	if !hmac.Equal(sig, m.sign([]byte(parts[0]))) {
		return c, ErrInvalidToken
	}
	payload, err := unb64(parts[0])
	if err != nil {
		return c, ErrInvalidToken
	}
	if err := json.Unmarshal(payload, &c); err != nil {
		return c, ErrInvalidToken
	}
	if time.Now().Unix() > c.Exp {
		return c, ErrInvalidToken
	}
	return c, nil
}

func (m *Manager) sign(data []byte) []byte {
	mac := hmac.New(sha256.New, m.secret)
	mac.Write(data)
	return mac.Sum(nil)
}

func b64(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }

func unb64(s string) ([]byte, error) { return base64.RawURLEncoding.DecodeString(s) }
