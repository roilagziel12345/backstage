#!/usr/bin/env bash
# =============================================================================
# generate-mock-data.sh — Regenerate/refresh ArgoCD apps and catalog entries
# =============================================================================
# Run from backstage-kind-poc/ after the KIND cluster is up.
# This script is idempotent — safe to run multiple times.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo -e "\033[1;34m[mock-data]\033[0m $*"; }
ok()  { echo -e "\033[1;32m[✓]\033[0m $*"; }
err() { echo -e "\033[1;31m[✗]\033[0m $*" >&2; }

# ── 1. Verify kubectl context ─────────────────────────────────────────────────
CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
if [[ "$CONTEXT" != "kind-backstage" ]]; then
  log "Switching kubectl context to kind-backstage..."
  kubectl config use-context kind-backstage
fi
ok "kubectl context: $(kubectl config current-context)"

# ── 2. Wait for ArgoCD ───────────────────────────────────────────────────────
log "Waiting for ArgoCD server to be available..."
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=300s
ok "ArgoCD server is running"

# ── 3. Apply ArgoCD Applications ─────────────────────────────────────────────
log "Applying ArgoCD Application manifests..."
kubectl apply -f "$SCRIPT_DIR/argocd-apps/"
ok "ArgoCD applications applied"

# ── 4. Wait for apps to sync ─────────────────────────────────────────────────
log "Waiting for ArgoCD applications to sync (up to 5 min)..."
for app in payment-service order-service inventory-service; do
  log "  Waiting for: $app"
  timeout 300 bash -c "
    until kubectl get application $app -n argocd \
      -o jsonpath='{.status.sync.status}' 2>/dev/null | grep -q 'Synced'; do
      sleep 5
    done
  " && ok "  $app: Synced" || log "  $app: sync timed out (may still be progressing)"
done

# ── 5. Verify catalog files ───────────────────────────────────────────────────
log "Verifying catalog files..."
for svc in payment-service order-service inventory-service; do
  CATALOG="$SCRIPT_DIR/dummy-services/$svc/catalog-info.yaml"
  if [[ -f "$CATALOG" ]]; then
    ok "  Catalog: $CATALOG"
  else
    err "  Missing catalog: $CATALOG"
  fi
done

# ── 6. Print summary ─────────────────────────────────────────────────────────
echo ""
log "=== Mock Data Summary ==="
echo "ArgoCD Applications:"
kubectl get applications -n argocd \
  --no-headers \
  -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status" \
  2>/dev/null || echo "  (ArgoCD not yet ready)"
echo ""
echo "Catalog files:"
find "$SCRIPT_DIR/dummy-services" -name "catalog-info.yaml" | while read f; do
  echo "  • $f"
done
echo ""
ok "Mock data generation complete!"
