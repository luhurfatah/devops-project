#!/usr/bin/env bash
# ─── configure.sh — repoint this repo at a new AWS account ────
# (and optionally a new profile / region) in one shot.
# Built for Pluralsight sandboxes, where the account ID changes
# every time you spin up a new sandbox.
#
# It discovers EVERY hardcoded account ID, profile, region, and
# GitHub repo across the project and rewrites them all in one
# pass — so bootstrap/*.tf, root.hcl, .github/workflows/*.yml,
# and account.hcl stay in sync.
#
# Usage:
#   ./configure.sh                         # auto-detect new account from AWS creds
#   ./configure.sh 123456789012            # set new account explicitly
#   ./configure.sh 123456789012 --profile sandbox --region us-west-2
#   ./configure.sh --repo my-org/my-repo   # repoint the OIDC trust to a new repo
#   ./configure.sh --dry-run               # preview changes, write nothing
#
# Options:
#   --profile NAME      Also replace the AWS profile name everywhere.
#   --region  NAME      Also replace the AWS region everywhere (use with care).
#   --repo  OWNER/NAME  Also replace the GitHub repo in the OIDC trust policy.
#   -n, --dry-run       Show what would change without writing.
#   -h, --help          This help.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# ─── Pretty Output ─────────────────────────────────────────────
if [ -t 1 ]; then BOLD=$'\e[1m'; RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; DIM=$'\e[2m'; RST=$'\e[0m'
else BOLD=""; RED=""; GRN=""; YEL=""; DIM=""; RST=""; fi
info()  { echo "${GRN}▸${RST} $*"; }
warn()  { echo "${YEL}!${RST} $*" >&2; }
die()   { echo "${RED}✗${RST} $*" >&2; exit 1; }

# ─── Arguments ─────────────────────────────────────────────────
NEW_ACCOUNT=""; NEW_PROFILE=""; NEW_REGION=""; NEW_REPO=""; DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    grep -E '^#' "$0" | sed '1d; s/^# \{0,1\}//'; exit 0 ;;
    -n|--dry-run) DRY_RUN=1; shift ;;
    --profile)    NEW_PROFILE="${2:?--profile needs a value}"; shift 2 ;;
    --region)     NEW_REGION="${2:?--region needs a value}"; shift 2 ;;
    --repo)       NEW_REPO="${2:?--repo needs a value}"; shift 2 ;;
    -*)           die "Unknown option: $1" ;;
    *)            [ -z "$NEW_ACCOUNT" ] && NEW_ACCOUNT="$1" || die "Unexpected arg: $1"; shift ;;
  esac
done

[ -n "$NEW_REPO" ] && { [[ "$NEW_REPO" == */* ]] || die "--repo must be OWNER/NAME, got: '$NEW_REPO'"; }

# ─── Helper ────────────────────────────────────────────────────
hcl_value() { # hcl_value <key> <file> → value of `key = "value"`
  grep -E "^[[:space:]]*$1[[:space:]]*=" "$2" 2>/dev/null | head -1 \
    | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/' | tr -d '\r'
}

# ─── Discover OLD Values from the Project ──────────────────────
# 1. Collect ALL unique 12-digit account IDs from .tf, .hcl, .yml, .yaml files.
mapfile -t OLD_ACCOUNTS < <(
  grep -rohE '\b[0-9]{12}\b' \
    --include='*.tf' --include='*.hcl' --include='*.yml' --include='*.yaml' \
    --exclude-dir=.terragrunt-cache --exclude-dir=.terraform --exclude-dir=.git \
    . 2>/dev/null | sort -u || true
)

# 2. Old AWS profile from any account.hcl.
ACCOUNT_HCL=$(find iaac/terragrunt/live -name account.hcl 2>/dev/null | head -1 || true)
OLD_PROFILE="$( [ -n "$ACCOUNT_HCL" ] && hcl_value aws_profile "$ACCOUNT_HCL" || true)"

# 3. Old AWS region from any region.hcl.
REGION_HCL=$(find iaac/terragrunt/live -name region.hcl 2>/dev/null | head -1 || true)
OLD_REGION="$([ -n "$REGION_HCL" ] && hcl_value aws_region "$REGION_HCL" || true)"

# 4. Old GitHub repo from the OIDC trust policy.
OIDC_TF=$(find bootstrap -name oidc.tf 2>/dev/null | head -1 || true)
OLD_REPO="$([ -n "$OIDC_TF" ] && grep -oE 'repo:[^:"]+' "$OIDC_TF" | head -1 | sed 's/^repo://' || true)"
[ -n "$NEW_REPO" ] && [ -z "$OLD_REPO" ] && die "--repo given but couldn't find an existing repo in bootstrap/oidc.tf."

# 5. Old bucket name pattern — extract the account ID embedded in the bucket name.
#    Bucket names follow: terragrunt-state-<ACCOUNT_ID>-<REGION>
OLD_BUCKET_ACCOUNT=""
BUCKET_SRC=$(grep -rohE 'terragrunt-state-[0-9]{12}-[a-z0-9-]+' \
  --include='*.tf' --include='*.hcl' \
  --exclude-dir=.terragrunt-cache --exclude-dir=.terraform --exclude-dir=.git \
  . 2>/dev/null | head -1 || true)
if [ -n "$BUCKET_SRC" ]; then
  OLD_BUCKET_ACCOUNT=$(echo "$BUCKET_SRC" | sed -E 's/.*-([0-9]{12})-.*/\1/')
fi

[ "${#OLD_ACCOUNTS[@]}" -gt 0 ] || die "Could not find any account IDs in the project."

# ─── Determine the New Account ─────────────────────────────────
HAS_OTHER_REPL=""
if [ -n "$NEW_REPO" ] || [ -n "$NEW_PROFILE" ] || [ -n "$NEW_REGION" ]; then HAS_OTHER_REPL=1; fi

PROFILE_FOR_LOOKUP="${NEW_PROFILE:-$OLD_PROFILE}"
if [ -z "$NEW_ACCOUNT" ]; then
  info "No account ID given — detecting from AWS creds (profile: ${BOLD}${PROFILE_FOR_LOOKUP:-default}${RST})..."
  if command -v aws >/dev/null 2>&1; then
    NEW_ACCOUNT="$(aws sts get-caller-identity \
                     ${PROFILE_FOR_LOOKUP:+--profile "$PROFILE_FOR_LOOKUP"} \
                     --query Account --output text 2>/dev/null || true)"
  fi
  if ! [[ "$NEW_ACCOUNT" =~ ^[0-9]{12}$ ]]; then
    if [ -n "$HAS_OTHER_REPL" ]; then
      warn "Could not detect a new account — leaving the account unchanged."
      NEW_ACCOUNT="${OLD_ACCOUNTS[0]}"
    else
      die "Couldn't detect account from AWS. Configure the profile first, or pass the ID: ./configure.sh <ID>"
    fi
  fi
fi

[[ "$NEW_ACCOUNT" =~ ^[0-9]{12}$ ]] || die "Account ID must be 12 digits, got: '$NEW_ACCOUNT'"

# ─── Build the Replacement Plan ────────────────────────────────
# Each entry: "label|OLD|NEW". Only included when OLD is set and OLD != NEW.
declare -a PLAN=()

add_repl() { [ -n "$2" ] && [ -n "$3" ] && [ "$2" != "$3" ] && PLAN+=("$1|$2|$3") || true; }

# Add each unique old account ID → new account ID
for old_acct in "${OLD_ACCOUNTS[@]}"; do
  add_repl "account ID" "$old_acct" "$NEW_ACCOUNT"
done

# Add the bucket account ID if it wasn't already covered
if [ -n "$OLD_BUCKET_ACCOUNT" ] && [ "$OLD_BUCKET_ACCOUNT" != "$NEW_ACCOUNT" ]; then
  already=false
  for entry in "${PLAN[@]}"; do
    IFS='|' read -r _ old _ <<<"$entry"
    [ "$old" = "$OLD_BUCKET_ACCOUNT" ] && already=true && break
  done
  $already || add_repl "bucket account ID" "$OLD_BUCKET_ACCOUNT" "$NEW_ACCOUNT"
fi

add_repl "AWS profile" "$OLD_PROFILE" "$NEW_PROFILE"
add_repl "AWS region"  "$OLD_REGION"  "$NEW_REGION"
add_repl "GitHub repo" "$OLD_REPO"    "$NEW_REPO"

[ "${#PLAN[@]}" -gt 0 ] || { info "Nothing to change — already configured for ${BOLD}$NEW_ACCOUNT${RST}."; exit 0; }

echo
echo "${BOLD}Planned replacements${RST}  ${DIM}(repo: $ROOT)${RST}"
for entry in "${PLAN[@]}"; do
  IFS='|' read -r label old new <<<"$entry"
  printf "  %-18s %s${DIM} →${RST} %s\n" "$label:" "$old" "$new"
done
echo

# ─── Build Grep Patterns for File Scanning ─────────────────────
declare -a GREP_PATTERNS=()
for entry in "${PLAN[@]}"; do
  IFS='|' read -r _ old _ <<<"$entry"
  GREP_PATTERNS+=(-e "$old")
done

# Files to scan: everything containing any OLD value, minus caches / VCS / self.
mapfile -t SCAN_FILES < <(
  grep -rIl "${GREP_PATTERNS[@]}" . \
    --exclude-dir=.terragrunt-cache --exclude-dir=.terraform --exclude-dir=.git \
    --exclude-dir=.kilo --exclude-dir=node_modules \
    --exclude='terraform.tfstate' --exclude='terraform.tfstate.backup' \
    --exclude=configure.sh 2>/dev/null | sed 's|^\./||' | sort -u || true
)

CHANGED=0
for f in "${SCAN_FILES[@]}"; do
  [ -z "$f" ] || [ ! -f "$f" ] && continue
  hits=""
  for entry in "${PLAN[@]}"; do
    IFS='|' read -r label old new <<<"$entry"
    n=$(grep -c -F "$old" "$f" 2>/dev/null || true); n=${n:-0}
    [ "$n" -gt 0 ] && hits+="    ${DIM}${n}× ${old} → ${new}${RST}\n"
  done
  [ -z "$hits" ] && continue

  CHANGED=$((CHANGED + 1))
  echo "  ${BOLD}$f${RST}"
  printf "%b" "$hits"

  if [ "$DRY_RUN" -eq 0 ]; then
    for entry in "${PLAN[@]}"; do
      IFS='|' read -r _ old new <<<"$entry"
      sed -i "s#${old}#${new}#g" "$f"
    done
  fi
done

# ─── Fix Broken working-directory Paths in GitHub Workflows ────
# The old workflows reference iaac/terragrunt/env/<env> but the actual
# directory structure is iaac/terragrunt/live/<env>/us-east-1.
if [ "$DRY_RUN" -eq 0 ]; then
  for wf in .github/workflows/*.yml; do
    [ -f "$wf" ] || continue
    if grep -q 'iaac/terragrunt/env/' "$wf" 2>/dev/null; then
      sed -i 's|iaac/terragrunt/env/\(dev\|stag\|prod\)|iaac/terragrunt/live/\1/us-east-1|g' "$wf"
      echo "  ${BOLD}$wf${RST}"
      echo "    ${DIM}fixed working-directory path: iaac/terragrunt/env/* → iaac/terragrunt/live/*/us-east-1${RST}"
      CHANGED=$((CHANGED + 1))
    fi
  done
fi

echo
if [ "$DRY_RUN" -eq 1 ]; then
  warn "Dry run — no files written. Re-run without --dry-run to apply."
elif [ "$CHANGED" -eq 0 ]; then
  info "No matching references found to update."
else
  info "Updated ${BOLD}$CHANGED${RST} file(s) for account ${BOLD}$NEW_ACCOUNT${RST}."
  echo
  echo "${BOLD}Next steps${RST} (a new sandbox is a clean account, so re-bootstrap):"
  echo "  1) cd bootstrap && terraform init && terraform apply   ${DIM}# create state bucket + OIDC role${RST}"
  echo "  2) cd iaac/terragrunt/live/dev/us-east-1/vpc && terragrunt init -reconfigure && terragrunt plan"
  echo "  3) cd iaac/terragrunt/live/dev/us-east-1/eks && terragrunt init -reconfigure && terragrunt plan"
  echo "  4) cd iaac/terragrunt/live/dev/us-east-1/lb-controller && terragrunt init -reconfigure && terragrunt plan"
  echo "  ${DIM}(bootstrap uses local state; the old sandbox's state does not carry over)${RST}"
fi