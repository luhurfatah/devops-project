# Code Review Findings

## 🔴 Critical / High Severity

### 1. Terraform state file committed to git
**[bootstrap/terraform.tfstate](bootstrap/terraform.tfstate)** — The bootstrap state file is tracked in git. State files can contain sensitive data (resource IDs, ARNs). Bootstrap should use a remote backend too, or at minimum, this file should be gitignored.

### 2. S3 state bucket has `force_destroy = true`
**[bootstrap/s3.tf:8](bootstrap/s3.tf#L8)** — The Terragrunt remote state bucket has `force_destroy = true`. If someone runs `terraform destroy` on bootstrap, all state files for every environment are permanently deleted with no recovery. This should be `false` in production.

### 3. Same AWS account for all environments
**[dev/account.hcl](iaac/terragrunt/live/dev/account.hcl)** — All three environments (dev, stag, prod) use the same account ID `149868069474`. There's no blast-radius isolation. A mistake in dev could affect prod resources. At minimum, prod should be in its own account.

### 4. ~~No DynamoDB state lock~~ (RETRACTED — S3 native locking is correct)
**[root.hcl:22-31](iaac/terragrunt/root.hcl#L22-L31)** — ~~The comment claims S3 native locking via `use_lockfile`, but `use_lockfile` controls Terraform's dependency lock file.~~ **Correction:** As of recent Terraform versions, `use_lockfile` **does** enable S3-native state locking (creates a `.tflock` file alongside the state in S3). DynamoDB-based locking (`dynamodb_table`) is now **deprecated** by HashiCorp in favor of this S3-native approach. The root.hcl configuration is correct, and the OIDC policy correctly grants `s3:PutObject`/`s3:DeleteObject` on `*.tflock`. No fix needed.

### 5. CI workflow paths are broken (not yet applied)
**[tf-dev.yml:43](.github/workflows/tf-dev.yml#L43), [tf-stag.yml:43](.github/workflows/tf-stag.yml#L43), [tf-prod.yml:43](.github/workflows/tf-prod.yml#L43)** — All three IaC workflows reference `iaac/terragrunt/env/<env>` but the actual directory structure is `iaac/terragrunt/live/<env>/us-east-1/`. The `configure.sh` script has logic to fix this (line 195-205) but it hasn't been applied. These workflows will fail at runtime.

### 6. Dev workflow: security scan doesn't block deploy
**[tf-dev.yml:58](.github/workflows/tf-dev.yml#L58)** — The `deploy` job in `tf-dev.yml` has no `needs: security-scan`, so the security scan can fail and deployment still proceeds. Staging and prod have `needs: security-scan` correctly set. Dev should be consistent.

### 7. Docker HEALTHCHECK for API will always fail
**[api/Dockerfile:49-50](apps/api/Dockerfile#L49-L50)** — `CMD ["kms-api", "health"]` — the binary is an HTTP server, not a CLI tool. `kms-api health` is not a valid invocation. In a distroless image (no `curl`/`wget`), this healthcheck will always fail, causing Kubernetes to restart the container repeatedly. Fix: use a Go-based health probe or switch to a base image with `curl`.

### 8. `AdministratorAccess` on GitHub Actions apply role
**[bootstrap/oidc.tf:132](bootstrap/oidc.tf#L132)** — The `GitHubActionApplyRole` gets `AdministratorAccess`. While scoped to the main branch via OIDC trust policy, this is still overly broad. A least-privilege policy scoped to the specific services managed (EKS, VPC, IAM, S3, etc.) would significantly reduce blast radius if the role were ever compromised.

### 9. Invalid Kubernetes version `1.35`
**[eks-stack/variables.tf:37](iaac/modules/aws/eks-stack/variables.tf#L37)** — EKS does not support Kubernetes 1.35. The latest supported versions as of 2026 are approximately 1.31-1.32. This will cause plan failures.

---

## 🟠 Medium Severity

### 10. EKS public endpoint open to `0.0.0.0/0`
**[eks-stack/variables.tf:55](iaac/modules/aws/eks-stack/variables.tf#L55)** — The EKS API endpoint is publicly accessible from anywhere. While authentication is still required, this increases the attack surface. Consider restricting to known CIDR ranges.

### 11. Security groups allow SSH/HTTP/HTTPS from `0.0.0.0/0`
**[vpc-stack/main.tf:138-160](iaac/modules/aws/vpc-stack/main.tf#L138-L160)** — The node security group allows SSH, HTTP, and HTTPS from `0.0.0.0/0`. NACLs also allow SSH from `0.0.0.0/0` on both public and private subnets.

### 12. No EKS secrets encryption
**[eks-stack/main.tf:70-95](iaac/modules/aws/eks-stack/main.tf#L70-L95)** — The EKS cluster doesn't enable envelope encryption for Kubernetes secrets. This is acknowledged in [checkov.yaml](iaac/checkov.yaml) as a skipped check but is a real security gap for production.

### 13. No VPC flow logs
**[vpc-stack/main.tf:14-22](iaac/modules/aws/vpc-stack/main.tf#L14-L22)** — VPC flow logs are not enabled, making network-level security monitoring and forensic analysis impossible.

### 14. No EKS control plane logging
**[eks-stack/main.tf:70-95](iaac/modules/aws/eks-stack/main.tf#L70-L95)** — Control plane logs (API server, audit, authenticator, controller manager, scheduler) are not enabled, making cluster audit and troubleshooting difficult.

### 15. Auth token stored in localStorage (XSS risk)
**[app.js:65](apps/web/public/app.js#L65)** — The bearer token is stored in `localStorage`, accessible to any JavaScript running on the page. If marked.js or Prism.js (loaded from CDN) were compromised, the token could be exfiltrated. HttpOnly cookies would be more secure.

### 16. CORS allows all origins with credentials
**[api.go:368](apps/api/internal/api/api.go#L368)** — `Access-Control-Allow-Origin: *` combined with `Authorization` header means any website can make authenticated cross-origin requests. Restrict to known origins.

### 17. No rate limiting on login endpoint
**[api.go:52-74](apps/api/internal/api/api.go#L52-L74)** — The login endpoint has no rate limiting, making it vulnerable to brute-force attacks.

### 18. Helm values contain plaintext secrets
**[values.yaml:32-36](k8s/charts/kms-app/values.yaml#L32-L36)** — Database credentials and auth secret are in plaintext in the values file. While the Secret template base64-encodes them, they're still plaintext in git. Use `sops`, `sealed-secrets`, or `external-secrets` for production.

### 19. Web proxy forwards all headers unfiltered
**[server.js:24-26](apps/web/server.js#L24-L26)** — The proxy copies all request headers to the upstream API. While safe for local/internal use, adding header sanitization (e.g., stripping `x-forwarded-*` that could confuse the upstream) would be more robust.

### 20. Default admin password is `admin`
**[config.go:28](apps/api/internal/config/config.go#L28)** — The code warns about this at startup but doesn't refuse to run. For production deployments, consider refusing to start with the default password.

---

## 🟡 Lower Severity / Improvements

### 21. Gateway API CRDs installed via `kubectl local-exec` instead of Terraform resource
**[lb-controller/main.tf:141-166](iaac/modules/aws/lb-controller/main.tf#L141-L166)** — Using `null_resource` with `local-exec` for `kubectl apply` is fragile (requires `kubectl` and `aws` CLI on the runner, doesn't track state properly). Consider using `kubectl_manifest` or a Helm-based approach.

### 22. `uniqueDocSlug` does O(n) scan of all documents
**[api.go:296-317](apps/api/internal/api/api.go#L296-L317)** — Slug uniqueness is checked by fetching all documents in a category and scanning in-memory. A `SELECT slug FROM documents WHERE category_id = $1` query would be far more efficient with large datasets.

### 23. SBOM for web generates from filesystem, not image
**[apps-web-ci.yml:365-371](.github/workflows/apps-web-ci.yml#L365-L371)** — The web workflow's SBOM uses `scan-type: fs`, meaning it captures source dependencies but misses OS-level packages in the final image. The API workflow correctly uses `scan-type: image`.

### 24. Checkov installed via pip every CI run
**[tf-dev.yml:44-47](.github/workflows/tf-dev.yml#L44-L47)** — Creating a venv and pip-installing checkov every run takes 30-60s. Use the `bridgecrewio/checkov-action` GitHub Action instead.

### 25. No PodDisruptionBudget or HPA
**[api-deployment.yaml](k8s/charts/kms-app/templates/api-deployment.yaml)** — Single replicas with no PDB or HPA means no high availability and no automatic scaling.

### 26. `latest` tag used in K8s environments
**[dev/values.yaml:12](k8s/environments/dev/values.yaml#L12)** — Using `latest` tag makes rollbacks and debugging difficult since you can't know which exact image is running. Use specific SHA or semver tags.

### 27. No request body size limits
**[api.go](apps/api/internal/api/api.go)** — The API has no `http.MaxBytesReader` or similar limit, making it vulnerable to large payload attacks that could exhaust memory.

### 28. Node.js app uses `express.static` without size limits
**[server.js:54](apps/web/server.js#L54)** — No request size limits on the static file server or proxy.

### 29. No structured logging
Both the Go API and Node.js web use basic `log.Printf`/`console.error`. Adding structured logging (JSON format, request IDs, trace IDs) would improve observability.

### 30. `COSIGN_EXPERIMENTAL=1` is deprecated
**[apps-api-ci.yml:343](.github/workflows/apps-api-ci.yml#L343)** — Cosign keyless signing no longer requires the experimental flag in recent versions. This may stop working when the flag is removed.

### 31. No pre-commit hooks for Terraform
No `.pre-commit-config.yaml` with `terraform fmt`, `tflint`, `terraform-docs`, etc. This would catch formatting and lint issues before they reach CI.

### 32. `package-lock.json*` glob in Dockerfile may fail
**[web/Dockerfile:9](apps/web/Dockerfile#L9)** — If `package-lock.json` doesn't exist, the glob expands literally to `package-lock.json*` and `npm ci` fails with a confusing error.

### 33. Web healthcheck probes `/` (returns full HTML page)
**[values.yaml:88-98](k8s/charts/kms-app/values.yaml#L88-L98)** — The web liveness/readiness probe hits `/` which returns the full HTML page (~30KB). A dedicated `/health` endpoint returning a lightweight response would be better.

### 34. `__pycache__` directory at repo root
**[__pycache__/](__pycache__/)** — A compiled Python cache file is at the project root. While gitignored, it indicates the file may have been committed previously.

---

## ✅ Things Done Well

- **Build-once pattern**: Docker images are built once, exported as tarballs, and reused across scan/push jobs — correct and efficient.
- **OIDC-based GitHub Actions auth**: No static AWS credentials — properly uses keyless OIDC with least-privilege plan vs apply roles.
- **Cosign keyless signing + SBOM attestation**: Images are signed and SBOMs are attested, enabling supply chain verification.
- **Two-role OIDC trust**: Plan role (read-only, PRs) vs Apply role (admin, main only) is a strong security pattern.
- **Custom HMAC token auth**: The Go API has a clean, minimal token implementation with constant-time comparison.
- **`configure.sh`**: The configuration management script is well-designed for multi-account portability.
- **Comprehensive security scanning**: Semgrep (SAST), Trivy (SCA + misconfig + image), npm audit, and Checkov (IaC) all run in CI.
- **Clean separation of concerns**: VPC → EKS → LB Controller dependency chain is well-structured via Terragrunt dependencies.
- **Embedded migrations**: SQL migrations are embedded in the Go binary via `embed.FS` — no external migration tool needed.

---

## Quick Wins (high impact, low effort)

| # | Finding | Fix |
|---|---------|-----|
| 5 | Broken CI `working-directory` paths | Run `./configure.sh` (already has the fix logic) or manually update the paths |
| 6 | Dev workflow missing `needs: security-scan` | Add `needs: security-scan` to the dev deploy job |
| 7 | API HEALTHCHECK broken in distroless | Switch to `curl`-based probe or change base image |
| 9 | Invalid K8s version 1.35 | Change to a supported EKS version (e.g., `1.31`) |
| 2 | `force_destroy = true` on state bucket | Set to `false` |
| 24 | Checkov pip install every CI run | Use `bridgecrewio/checkov-action` |
