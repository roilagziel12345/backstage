#!/usr/bin/env bash
# =============================================================================
# setup-local-backstage.sh — Master PoC automation script
# =============================================================================
# Deploys a complete Backstage Developer Portal on KIND with:
#   • ArgoCD (with 3 demo applications)
#   • Mock API server (Jenkins + SonarQube)
#   • Backstage (with Kubernetes, Jenkins, SonarQube, ArgoCD plugins)
#
# Prerequisites (in WSL2 / Linux):
#   • docker CLI connected to Docker Desktop
#   • kind CLI
#   • kubectl CLI
#   • Node.js 20 LTS + yarn
#   • npx
#   • At least 8GB RAM allocated to Docker
#
# Usage:
#   chmod +x setup-local-backstage.sh
#   bash setup-local-backstage.sh
#   bash setup-local-backstage.sh --skip-scaffold   # if app already built
#   bash setup-local-backstage.sh --skip-cluster    # if KIND cluster exists
# =============================================================================
set -euo pipefail

# ── Parse flags ───────────────────────────────────────────────────────────────
SKIP_SCAFFOLD=false
SKIP_CLUSTER=false
for arg in "$@"; do
  case $arg in
    --skip-scaffold) SKIP_SCAFFOLD=true ;;
    --skip-cluster)  SKIP_CLUSTER=true ;;
  esac
done

# ── Colours & helpers ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[1;34m'
YELLOW='\033[1;33m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${BLUE}[setup]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
step() { echo -e "\n${BOLD}══════════════════════════════════════════════════${NC}"; \
         echo -e "${BOLD} $*${NC}"; \
         echo -e "${BOLD}══════════════════════════════════════════════════${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR/my-developer-portal"

# ── Pre-flight checks ─────────────────────────────────────────────────────────
step "Step 0: Pre-flight checks"

for cmd in docker kind kubectl; do
  command -v "$cmd" &>/dev/null || err "'$cmd' not found. Please install it first."
  ok "$cmd: $(command -v "$cmd")"
done

if [[ "$SKIP_SCAFFOLD" == "false" ]]; then
  for cmd in node yarn npx; do
    command -v "$cmd" &>/dev/null || err "'$cmd' not found. Please install Node.js 20 LTS."
    ok "$cmd: $(command -v "$cmd")"
  done
fi

# Check Docker is running
docker info &>/dev/null || err "Docker daemon not running. Start Docker Desktop."
ok "Docker daemon is running"

# ── Step 1: Create KIND cluster ───────────────────────────────────────────────
step "Step 1: Create KIND cluster"

if [[ "$SKIP_CLUSTER" == "true" ]]; then
  warn "Skipping cluster creation (--skip-cluster)"
elif kind get clusters 2>/dev/null | grep -q "^backstage$"; then
  warn "KIND cluster 'backstage' already exists — skipping creation"
else
  log "Creating KIND cluster 'backstage'..."
  kind create cluster \
    --name backstage \
    --config "$SCRIPT_DIR/kind-config.yaml" \
    --wait 120s
  ok "KIND cluster created"
fi

kubectl config use-context kind-backstage
ok "kubectl context: kind-backstage"

# ── Step 2: Install ArgoCD ────────────────────────────────────────────────────
step "Step 2: Install ArgoCD"

if kubectl get namespace argocd &>/dev/null; then
  warn "Namespace 'argocd' already exists — skipping ArgoCD install"
else
  log "Creating argocd namespace..."
  kubectl create namespace argocd

  log "Installing ArgoCD..."
  kubectl apply -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  log "Waiting for ArgoCD deployments to be ready (up to 5 min)..."
  kubectl wait --for=condition=available deployment \
    -l "app.kubernetes.io/name=argocd-server" \
    -n argocd --timeout=300s
  ok "ArgoCD installed"
fi

# ── Step 3: Apply ArgoCD Applications ─────────────────────────────────────────
step "Step 3: Apply ArgoCD demo applications"

log "Applying ArgoCD Application manifests..."
kubectl apply -f "$SCRIPT_DIR/argocd-apps/"
ok "ArgoCD applications applied: payment-service, order-service, inventory-service"

# ── Step 4: Backstage namespace + RBAC ────────────────────────────────────────
step "Step 4: Create Backstage namespace and RBAC"

kubectl apply -f "$SCRIPT_DIR/k8s/namespace.yaml"
ok "Namespace 'backstage' applied"

kubectl apply -f "$SCRIPT_DIR/k8s/rbac.yaml"
ok "RBAC (ServiceAccount, ClusterRole, ClusterRoleBinding) applied"

# ── Step 5: Get ArgoCD auth token ────────────────────────────────────────────
step "Step 5: Retrieve ArgoCD admin credentials"

ARGOCD_PASSWORD=""
for i in $(seq 1 12); do
  ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || true)
  [[ -n "$ARGOCD_PASSWORD" ]] && break
  log "Waiting for ArgoCD admin secret... ($i/12)"
  sleep 10
done

if [[ -z "$ARGOCD_PASSWORD" ]]; then
  warn "Could not retrieve ArgoCD password. Backstage ArgoCD integration will use empty token."
  ARGOCD_AUTH_TOKEN=""
else
  ok "ArgoCD admin password retrieved"
  # Try to get a proper API token (requires argocd CLI or port-forward + curl)
  # We'll use the password as a Bearer token workaround for the PoC
  ARGOCD_AUTH_TOKEN="$ARGOCD_PASSWORD"
  log "ArgoCD password: $ARGOCD_PASSWORD (save this for ArgoCD UI at http://localhost:8080)"
fi

# Create Kubernetes Secret for Backstage
kubectl create secret generic backstage-secrets \
  --namespace backstage \
  --from-literal=argocd-token="${ARGOCD_AUTH_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -
ok "Backstage secrets created"

# ── Step 6: Build and load mock server ────────────────────────────────────────
step "Step 6: Build and load mock server Docker image"

log "Building mock-server Docker image..."
docker build -t mock-server:latest "$SCRIPT_DIR/mock-server/"
ok "mock-server:latest built"

log "Loading mock-server image into KIND cluster..."
kind load docker-image mock-server:latest --name backstage
ok "mock-server:latest loaded into KIND"

log "Deploying mock server..."
kubectl apply -f "$SCRIPT_DIR/k8s/mock-server/"
ok "Mock server deployed"

log "Waiting for mock server to be ready..."
kubectl wait --for=condition=available deployment/mock-server \
  -n backstage --timeout=60s
ok "Mock server is ready"

# ── Step 7: Scaffold Backstage ────────────────────────────────────────────────
step "Step 7: Scaffold and configure Backstage app"

if [[ "$SKIP_SCAFFOLD" == "true" ]]; then
  warn "Skipping scaffold (--skip-scaffold)"
elif [[ -d "$APP_DIR" ]]; then
  warn "App directory exists at $APP_DIR — skipping scaffold"
  warn "Remove it or use --skip-scaffold to force skip"
else
  log "Running scaffold-app.sh..."
  bash "$SCRIPT_DIR/backstage-patches/scaffold-app.sh"
  ok "Backstage app scaffolded and configured"
fi

# Copy catalog files (always refresh)
if [[ -d "$APP_DIR" ]]; then
  mkdir -p "$APP_DIR/catalog"
  cp -r "$SCRIPT_DIR/dummy-services/." "$APP_DIR/catalog/"
  ok "Catalog files synced to $APP_DIR/catalog/"
fi

# ── Step 8: Build and load Backstage Docker image ─────────────────────────────
step "Step 8: Build Backstage Docker image"

if [[ ! -d "$APP_DIR" ]]; then
  err "Backstage app directory not found at $APP_DIR. Run without --skip-scaffold first."
fi

log "Building Backstage Docker image (this takes ~5-10 min)..."
docker build \
  -t backstage:latest \
  -f "$SCRIPT_DIR/backstage-patches/Dockerfile" \
  "$APP_DIR"
ok "backstage:latest built"

log "Loading backstage image into KIND cluster..."
kind load docker-image backstage:latest --name backstage
ok "backstage:latest loaded into KIND"

# ── Step 9: Deploy Backstage ──────────────────────────────────────────────────
step "Step 9: Deploy Backstage to KIND"

kubectl apply -f "$SCRIPT_DIR/k8s/deployment.yaml"
kubectl apply -f "$SCRIPT_DIR/k8s/service.yaml"
ok "Backstage deployment and service applied"

log "Waiting for Backstage pod to be ready (up to 5 min)..."
kubectl wait --for=condition=ready pod \
  -l app=backstage \
  -n backstage \
  --timeout=300s
ok "Backstage pod is running"

# ── Step 10: Verification ─────────────────────────────────────────────────────
step "Step 10: Verification"

echo ""
log "Cluster nodes:"
kubectl get nodes

echo ""
log "Backstage pods:"
kubectl get pods -n backstage

echo ""
log "Mock server pods:"
kubectl get pods -n backstage -l app=mock-server

echo ""
log "ArgoCD applications:"
kubectl get applications -n argocd \
  --no-headers \
  -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status" \
  2>/dev/null || warn "ArgoCD not yet ready"

echo ""
log "Verifying mock server health via in-cluster exec..."
MOCK_POD=$(kubectl get pod -n backstage -l app=mock-server \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "$MOCK_POD" ]]; then
  kubectl exec -n backstage "$MOCK_POD" -- \
    wget -qO- http://localhost:4010/health 2>/dev/null \
    | python3 -m json.tool 2>/dev/null || warn "wget not available in pod"
fi

# ── Final Summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════╗"
echo "║        ✅  SETUP COMPLETE!                        ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  Backstage UI  →  http://localhost:3000           ║"
echo "║  ArgoCD UI     →  http://localhost:8080           ║"
echo "║                    user: admin                   ║"
if [[ -n "$ARGOCD_PASSWORD" ]]; then
  printf  "║                    pass: %-26s║\n" "$ARGOCD_PASSWORD"
fi
echo "╠══════════════════════════════════════════════════╣"
echo "║  Catalog entries:                                 ║"
echo "║    • payment-service   (Java / Spring Boot)       ║"
echo "║    • order-service     (Node.js / Express)        ║"
echo "║    • inventory-service (Python / FastAPI)         ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Expose ArgoCD via NodePort ────────────────────────────────────────────────
log "Patching ArgoCD server service to NodePort 30001..."
kubectl patch svc argocd-server -n argocd \
  -p '{"spec":{"type":"NodePort","ports":[{"name":"https","port":443,"targetPort":8080,"nodePort":30001}]}}' \
  2>/dev/null || warn "Could not patch ArgoCD service (may already be patched)"
ok "ArgoCD accessible at http://localhost:8080 (via KIND port mapping)"

log "Backstage is ready! 🚀"
log "No port-forward needed — NodePort is mapped via KIND extraPortMappings."
