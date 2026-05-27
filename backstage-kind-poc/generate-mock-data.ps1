# =============================================================================
# generate-mock-data.ps1 — Refresh ArgoCD apps and verify catalog (Windows)
# =============================================================================
# Run from backstage-kind-poc\ after the KIND cluster is up.
# Idempotent — safe to run multiple times.
# =============================================================================
$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot

function Log  { param($m) Write-Host "[mock-data] $m" -ForegroundColor Cyan }
function Ok   { param($m) Write-Host "[OK] $m"        -ForegroundColor Green }
function Warn { param($m) Write-Host "[!]  $m"        -ForegroundColor Yellow }
function Err  { param($m) Write-Host "[ERR] $m"       -ForegroundColor Red; exit 1 }

# ── 1. Verify context ─────────────────────────────────────────────────────────
$context = kubectl config current-context 2>&1
if ($context -ne "kind-backstage") {
    Log "Switching to kind-backstage context..."
    kubectl config use-context kind-backstage
}
Ok "kubectl context: $(kubectl config current-context)"

# ── 2. Wait for ArgoCD ───────────────────────────────────────────────────────
Log "Waiting for ArgoCD server..."
kubectl wait --for=condition=available deployment/argocd-server `
    -n argocd --timeout=300s
Ok "ArgoCD server is running"

# ── 3. Apply ArgoCD Applications ─────────────────────────────────────────────
Log "Applying ArgoCD Application manifests..."
kubectl apply -f "$ScriptDir\argocd-apps\"
Ok "ArgoCD applications applied"

# ── 4. Wait for apps to sync ─────────────────────────────────────────────────
Log "Waiting for ArgoCD apps to sync (up to 5 min)..."
$apps = @("payment-service","order-service","inventory-service")
foreach ($app in $apps) {
    Log "  Waiting: $app"
    $deadline = (Get-Date).AddSeconds(300)
    while ((Get-Date) -lt $deadline) {
        $status = kubectl get application $app -n argocd `
            -o jsonpath="{.status.sync.status}" 2>$null
        if ($status -eq "Synced") {
            Ok "  $app : Synced"
            break
        }
        Start-Sleep -Seconds 5
    }
    if ($status -ne "Synced") {
        Warn "  $app : sync timed out (may still be progressing)"
    }
}

# ── 5. Verify catalog files ───────────────────────────────────────────────────
Log "Verifying catalog files..."
foreach ($svc in @("payment-service","order-service","inventory-service")) {
    $path = "$ScriptDir\dummy-services\$svc\catalog-info.yaml"
    if (Test-Path $path) { Ok "  $path" }
    else { Warn "  Missing: $path" }
}

# ── 6. Summary ───────────────────────────────────────────────────────────────
Write-Host ""
Log "=== ArgoCD Application Status ==="
kubectl get applications -n argocd `
    --no-headers `
    -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status" `
    2>&1

Write-Host ""
Log "=== Catalog Files ==="
Get-ChildItem -Recurse "$ScriptDir\dummy-services" -Filter "catalog-info.yaml" |
    ForEach-Object { Write-Host "  • $($_.FullName)" }

Write-Host ""
Ok "Mock data generation complete!"
