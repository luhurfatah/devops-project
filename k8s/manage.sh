#!/usr/bin/env bash
# ─── K8s Resource Manager ────────────────────────────────────────────────
# Deploys or destroys all Kubernetes resources in /k8s in the correct order.
#
# Usage:
#   ./k8s/manage.sh deploy <environment>
#   ./k8s/manage.sh destroy <environment>
#
# Examples:
#   ./k8s/manage.sh deploy dev
#   ./k8s/manage.sh destroy staging
#   ./k8s/manage.sh deploy prod
#
# Environments: dev, staging, prod
# ──────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHARTS_DIR="${SCRIPT_DIR}/charts"
ENVS_DIR="${SCRIPT_DIR}/environments"

# ─── Color output helpers ─────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
step()  { echo -e "\n${CYAN}═══ $* ═══${NC}"; }

# ─── Usage ────────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 {deploy|destroy} <environment>"
    echo ""
    echo "Environments: dev, staging, prod"
    exit 1
}

# ─── Validate inputs ──────────────────────────────────────────────────────
ACTION="${1:-}"
ENV="${2:-}"

if [[ -z "$ACTION" || -z "$ENV" ]]; then
    usage
fi

if [[ "$ACTION" != "deploy" && "$ACTION" != "destroy" ]]; then
    error "Invalid action '$ACTION'. Must be 'deploy' or 'destroy'."
    usage
fi

VALID_ENVS=("dev" "staging" "prod")
VALID=0
for e in "${VALID_ENVS[@]}"; do
    if [[ "$e" == "$ENV" ]]; then
        VALID=1
        break
    fi
done

if [[ "$VALID" -ne 1 ]]; then
    error "Invalid environment '$ENV'. Must be one of: ${VALID_ENVS[*]}"
    usage
fi

ENV_VALUES="${ENVS_DIR}/${ENV}/values.yaml"
if [[ ! -f "$ENV_VALUES" ]]; then
    error "Environment values file not found: $ENV_VALUES"
    exit 1
fi

# ─── Prerequisites check ──────────────────────────────────────────────────
prereqs() {
    if ! command -v helm &> /dev/null; then
        error "helm is not installed. Please install Helm v3."
        exit 1
    fi

    if ! helm version --short &> /dev/null; then
        error "Cannot connect to Helm. Ensure Helm is configured."
        exit 1
    fi
}

# ─── Helm upgrade/install wrapper ─────────────────────────────────────────
helm_deploy_chart() {
    local chart="$1"       # path to chart directory
    local release="$2"     # Helm release name
    local extra_args="${3:-}"

    info "Deploying release '$release' from chart: $chart"
    # shellcheck disable=SC2086
    helm upgrade --install "$release" "$chart" \
        --namespace default \
        --create-namespace \
        --values "${ENV_VALUES}" \
        --wait \
        --timeout 5m \
        ${extra_args} \
        --rollback-on-failure
    info "✓ Release '$release' deployed successfully."
}

helm_uninstall_release() {
    local release="$1"
    local chart_label="$2"

    if helm status "$release" --namespace default &> /dev/null; then
        info "Uninstalling release '$release' ($chart_label)..."
        helm uninstall "$release" --namespace default --wait --timeout 3m
        info "✓ Release '$release' uninstalled."
    else
        info "Release '$release' not found — skipping."
    fi
}

# ─── Deploy (correct order: CRDs → Gateway resources → App) ───────────────
deploy() {
    step "Starting deployment for environment: ${ENV}"

    # ── 1. Gateway API CRDs ──────────────────────────────────────────────
    step "Phase 1/3: Gateway API CRDs"
    helm_deploy_chart \
        "${CHARTS_DIR}/gateway-api-crds" \
        "gateway-api-crds"

    # ── 2. Gateway API Resources (GatewayClass, Gateway) ─────────────────
    step "Phase 2/3: Gateway API Resources (GatewayClass / Gateway)"
    helm_deploy_chart \
        "${CHARTS_DIR}/gateway-api-resources" \
        "gateway-api-resources"

    # ── 3. KMS Application (ConfigMap, Secret, Deployments, HTTPRoutes) ──
    step "Phase 3/3: KMS Application (API + Web + HTTPRoutes)"
    helm_deploy_chart \
        "${CHARTS_DIR}/kms-app" \
        "kms-app"

    step "Deployment complete for environment: ${ENV}"
    echo ""
    info "Run 'helm list -n default' to see all releases."
    info "Run 'kubectl get pods -n default' to check pod status."
}

# ─── Destroy (reverse order: App → Gateway resources → CRDs) ─────────────
destroy() {
    step "Starting teardown for environment: ${ENV}"

    # ── 1. KMS Application ───────────────────────────────────────────────
    step "Phase 1/3: KMS Application"
    helm_uninstall_release "kms-app" "kms-app"

    # ── 2. Gateway API Resources ─────────────────────────────────────────
    step "Phase 2/3: Gateway API Resources (GatewayClass / Gateway)"
    helm_uninstall_release "gateway-api-resources" "gateway-api-resources"

    # ── 3. Gateway API CRDs ──────────────────────────────────────────────
    step "Phase 3/3: Gateway API CRDs"
    helm_uninstall_release "gateway-api-crds" "gateway-api-crds"

    step "Teardown complete for environment: ${ENV}"
    echo ""
    info "Run 'helm list -n default' to verify no releases remain."
}

# ─── Main ─────────────────────────────────────────────────────────────────
main() {
    prereqs

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   KMS Kubernetes Manager                                    ║"
    echo "║   Action:    ${ACTION}"
    echo "║   Environment: ${ENV}"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    # Confirm for destroy (safety net)
    if [[ "$ACTION" == "destroy" ]]; then
        echo -e "${RED}WARNING:${NC} This will DESTROY all resources in namespace 'default' for '${ENV}'."
        read -r -p "Are you sure you want to proceed? [y/N] " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            info "Destroy cancelled."
            exit 0
        fi
        echo ""
    fi

    case "$ACTION" in
        deploy)  deploy  ;;
        destroy) destroy ;;
    esac
}

main
