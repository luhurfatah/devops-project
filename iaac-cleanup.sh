#!/usr/bin/env bash
# =============================================================================
#  iaac-cleanup.sh — Clean up Terraform & Terragrunt cache/lock/state files
#
#  Removes the following artifacts recursively across the project:
#    - .terragrunt-cache/      (Terragrunt module cache)
#    - .terraform/             (Terraform provider cache & state)
#    - .terraform.lock.hcl     (Terraform dependency lock files)
#    - terraform.tfstate*      (Local Terraform state files)
#    - .terraform.tfstate.lock.info  (State lock info)
#    - *.tfplan                (Terraform plan files)
#    - tfplan                  (Terraform plan files)
#
#  Usage:
#    ./iaac-cleanup.sh              # Dry-run mode (shows what would be deleted)
#    ./iaac-cleanup.sh --apply      # Actually delete the files
#    ./iaac-cleanup.sh --help       # Show this help message
# =============================================================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=true

# ── Help ────────────────────────────────────────────────────────────────────

print_help() {
    sed -n 's/^#  //p; /^$/q; /^# ===/d' "$0"
    exit 0
}

# ── Parse arguments ─────────────────────────────────────────────────────────

for arg in "$@"; do
    case "$arg" in
        --apply) DRY_RUN=false ;;
        --help)  print_help ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--apply] [--help]"
            exit 1
            ;;
    esac
done

# ── Cleanup logic ───────────────────────────────────────────────────────────

TOTAL_DIRS=0
TOTAL_FILES=0
DELETED_DIRS=0
DELETED_FILES=0

collect_items() {
    local pattern="$1"
    local type="$2" # f or d

    while IFS= read -r -d '' item; do
        # Skip anything inside .git
        if [[ "$item" == *".git"* ]]; then
            continue
        fi

        if [[ "$type" == "d" ]]; then
            TOTAL_DIRS=$((TOTAL_DIRS + 1))
            if $DRY_RUN; then
                echo "  [DIR ]  $item"
            else
                echo "  [RM ]   $item"
                rm -rf "$item" 2>/dev/null && DELETED_DIRS=$((DELETED_DIRS + 1)) || echo "  [FAIL]  $item"
            fi
        else
            TOTAL_FILES=$((TOTAL_FILES + 1))
            if $DRY_RUN; then
                echo "  [FILE]  $item"
            else
                echo "  [RM ]   $item"
                rm -f "$item" 2>/dev/null && DELETED_FILES=$((DELETED_FILES + 1)) || echo "  [FAIL]  $item"
            fi
        fi
    done < <(find "$PROJECT_DIR" -name "$pattern" -not -path '*/.git/*' -print0 2>/dev/null)
}

echo ""
echo "============================================="
echo "  IaC Cleanup"
echo "  Project: $PROJECT_DIR"
if $DRY_RUN; then
    echo "  Mode:    DRY RUN (pass --apply to delete)"
else
    echo "  Mode:    APPLY"
fi
echo "============================================="
echo ""

# ── Scan & collect ──────────────────────────────────────────────────────────

echo ">> Scanning for .terragrunt-cache/ directories ..."
collect_items ".terragrunt-cache" d

echo ""
echo ">> Scanning for .terraform/ directories ..."
collect_items ".terraform" d

echo ""
echo ">> Scanning for .terraform.lock.hcl files ..."
collect_items ".terraform.lock.hcl" f

echo ""
echo ">> Scanning for terraform.tfstate* files ..."
collect_items "terraform.tfstate*" f

echo ""
echo ">> Scanning for .terraform.tfstate.lock.info files ..."
collect_items ".terraform.tfstate.lock.info" f

echo ""
echo ">> Scanning for tfplan / *.tfplan files ..."
collect_items "tfplan" f
collect_items "*.tfplan" f

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "============================================="
if $DRY_RUN; then
    echo "  Summary: Found $TOTAL_DIRS dir(s) and $TOTAL_FILES file(s)"
    echo "  Nothing was deleted. Re-run with --apply to clean."
else
    echo "  Summary: Removed $DELETED_DIRS/$TOTAL_DIRS dir(s) and $DELETED_FILES/$TOTAL_FILES file(s)"
fi
echo "============================================="
echo ""

exit 0
