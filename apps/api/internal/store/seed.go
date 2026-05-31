package store

import "context"

// seedCategory is demo data inserted on first boot when the DB is empty.
type seedCategory struct {
	name string
	docs []seedDoc
}

type seedDoc struct {
	title   string
	content string
}

var seedData = []seedCategory{
	{
		name: "Knowledge Base",
		docs: []seedDoc{
			{
				title: "SRE Principles",
				content: "# SRE Principles\n\n" +
					"> Hope is not a strategy.\n\n" +
					"Site Reliability Engineering treats operations as a software problem.\n\n" +
					"## Core ideas\n\n" +
					"- **SLIs / SLOs / SLAs** — measure what users actually experience.\n" +
					"- **Error budgets** — balance velocity against reliability.\n" +
					"- **Toil reduction** — automate the repetitive, manual work away.\n\n" +
					"## Example error budget\n\n" +
					"```\nSLO        = 99.9% over 30 days\nDowntime  ≈ 43m 12s budget / month\n```\n\n" +
					"When the budget is spent, freeze features and focus on reliability.\n",
			},
			{
				title: "Day-Two Operations",
				content: "# Day-Two Operations\n\n" +
					"Everything that happens *after* the system is live.\n\n" +
					"## Checklist\n\n" +
					"1. Backups are tested (not just scheduled).\n" +
					"2. Dashboards and alerts exist for every SLO.\n" +
					"3. Runbooks are linked from each alert.\n" +
					"4. On-call rotation is fair and documented.\n\n" +
					"```bash\n# Quick health probe\ncurl -fsS https://api.internal/healthz && echo OK\n```\n",
			},
		},
	},
	{
		name: "Interview Prep",
		docs: []seedDoc{
			{
				title: "Kubernetes Cheat Sheet",
				content: "# Kubernetes Cheat Sheet\n\n" +
					"## Inspecting workloads\n\n" +
					"```bash\nkubectl get pods -A -o wide\nkubectl describe pod <name>\nkubectl logs -f deploy/<name>\n```\n\n" +
					"## Common gotchas\n\n" +
					"- `CrashLoopBackOff` → check logs + liveness probe.\n" +
					"- `Pending` → no schedulable node (resources / taints).\n" +
					"- `ImagePullBackOff` → registry auth or wrong tag.\n",
			},
			{
				title: "CI/CD Questions",
				content: "# CI/CD Interview Questions\n\n" +
					"**Q: What is *build once, deploy many*?**\n\n" +
					"Build a single immutable artifact, then promote that exact artifact\n" +
					"through environments — no rebuilds per stage.\n\n" +
					"**Q: Blue/green vs canary?**\n\n" +
					"| Strategy | Rollout | Blast radius |\n" +
					"|----------|---------|--------------|\n" +
					"| Blue/green | All at once (switch) | Full |\n" +
					"| Canary | Gradual % | Small |\n",
			},
		},
	},
	{
		name: "Labs",
		docs: []seedDoc{
			{
				title: "Welcome to your KMS",
				content: "# Welcome to your Knowledge Management System\n\n" +
					"This content is **stored in Postgres** and served by a **Go API** — no Markdown files on disk.\n\n" +
					"## Try it out\n\n" +
					"- ✏️  Click **Edit** to change this document.\n" +
					"- ➕  Use **New** to add a document or category.\n" +
					"- 🗑️  **Delete** removes it from the database.\n" +
					"- 🔎  Search runs against Postgres full-text search.\n\n" +
					"Everything you write is persisted via CRUD endpoints under `/api`.\n",
			},
		},
	},
}

// Seed inserts demo content. Callers should check IsEmpty first.
func (s *Store) Seed(ctx context.Context) error {
	for ci, cat := range seedData {
		c, err := s.CreateCategory(ctx, cat.name, Slugify(cat.name), ci)
		if err != nil {
			return err
		}
		for di, doc := range cat.docs {
			if _, err := s.CreateDocument(ctx, c.ID, doc.title, Slugify(doc.title), doc.content, di); err != nil {
				return err
			}
		}
	}
	return nil
}
