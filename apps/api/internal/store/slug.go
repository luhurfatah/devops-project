package store

import (
	"regexp"
	"strings"
)

var (
	nonAlnum   = regexp.MustCompile(`[^a-z0-9]+`)
	trimDashes = regexp.MustCompile(`^-+|-+$`)
)

// Slugify converts a title into a URL-friendly slug.
func Slugify(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	s = nonAlnum.ReplaceAllString(s, "-")
	s = trimDashes.ReplaceAllString(s, "")
	if s == "" {
		s = "untitled"
	}
	return s
}
