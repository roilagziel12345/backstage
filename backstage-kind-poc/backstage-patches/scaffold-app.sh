#!/usr/bin/env bash
# =============================================================================
# scaffold-app.sh — Phase 1: Create and configure the Backstage app
# =============================================================================
# Run this from the backstage-kind-poc/ directory.
# Prerequisites: Node.js 20 LTS, yarn (classic), npx
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$POC_DIR/my-developer-portal"

log() { echo -e "\033[1;34m[scaffold]\033[0m $*"; }
ok()  { echo -e "\033[1;32m[✓]\033[0m $*"; }
err() { echo -e "\033[1;31m[✗]\033[0m $*" >&2; }

# ── 1. Pre-flight checks ──────────────────────────────────────────────────────
for cmd in node yarn npx; do
  if ! command -v "$cmd" &>/dev/null; then
    err "Required command not found: $cmd"
    exit 1
  fi
done

NODE_VER=$(node --version | sed 's/v//' | cut -d. -f1)
if [[ "$NODE_VER" -lt 18 ]]; then
  err "Node.js 18+ required, found: $(node --version)"
  exit 1
fi
log "Node.js $(node --version) ✓"
log "Yarn $(yarn --version) ✓"

# ── 2. Scaffold the Backstage app ─────────────────────────────────────────────
if [[ -d "$APP_DIR" ]]; then
  log "App directory already exists at $APP_DIR — skipping scaffold"
else
  log "Scaffolding Backstage app to $APP_DIR ..."
  cd "$POC_DIR"
  BACKSTAGE_APP_NAME=my-developer-portal \
    npx @backstage/create-app@latest \
    --skip-install \
    --path my-developer-portal
  ok "App scaffolded"
fi

cd "$APP_DIR"

# ── 3. Install base dependencies ─────────────────────────────────────────────
log "Installing base dependencies..."
yarn install
ok "Base dependencies installed"

# ── 4. Install frontend plugins ───────────────────────────────────────────────
log "Installing frontend plugins..."
yarn --cwd packages/app add \
  @backstage-community/plugin-jenkins \
  @roadiehq/backstage-plugin-argo-cd \
  @backstage-community/plugin-sonarqube \
  @backstage/plugin-kubernetes
ok "Frontend plugins installed"

# ── 5. Install backend plugins ────────────────────────────────────────────────
log "Installing backend plugins..."
yarn --cwd packages/backend add \
  @backstage-community/plugin-jenkins-backend \
  @backstage-community/plugin-sonarqube-backend \
  @backstage/plugin-kubernetes-backend \
  @backstage/plugin-permission-backend \
  @backstage/plugin-permission-backend-module-allow-all-policy \
  better-sqlite3
ok "Backend plugins installed"

# ── 6. Apply patches ──────────────────────────────────────────────────────────
log "Applying Backstage patches..."

cp "$SCRIPT_DIR/EntityPage.tsx" \
   "$APP_DIR/packages/app/src/components/catalog/EntityPage.tsx"
ok "EntityPage.tsx patched"

cp "$SCRIPT_DIR/backend-index.ts" \
   "$APP_DIR/packages/backend/src/index.ts"
ok "backend/src/index.ts patched"

cp "$SCRIPT_DIR/app-config.local.yaml" \
   "$APP_DIR/app-config.local.yaml"
ok "app-config.local.yaml copied"

# ── 7. Copy catalog files into the app (for Docker COPY) ─────────────────────
log "Copying catalog files..."
mkdir -p "$APP_DIR/catalog"
cp -r "$POC_DIR/dummy-services/." "$APP_DIR/catalog/"
ok "Catalog files copied to $APP_DIR/catalog/"

cd "$POC_DIR"
ok "Backstage app scaffold complete!"
echo ""
echo "  Next steps:"
echo "    • Run: bash setup-local-backstage.sh"
echo "    • Or:  cd my-developer-portal && yarn dev   (local dev mode)"
