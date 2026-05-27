#!/usr/bin/env pwsh
# deploy-backstage.ps1
# One-shot script: loads image into KIND, deploys Backstage via Helm
# Usage: .\deploy-backstage.ps1

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$REPO_ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
$HELM_DIR  = Join-Path $REPO_ROOT "helm\backstage"
$TAR_FILE  = Join-Path $REPO_ROOT "backstage-v2.tar"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Backstage Helm Deployment Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ─── Step 1: Save Docker image to tar ────────────────────────────────────────
Write-Host "[1/6] Saving backstage:latest to tar (this may take ~60s for 3GB image)..." -ForegroundColor Yellow
if (Test-Path $TAR_FILE) {
    Write-Host "      Tar file already exists, skipping save." -ForegroundColor Gray
} else {
    docker save backstage:latest -o $TAR_FILE
    if ($LASTEXITCODE -ne 0) { Write-Error "docker save failed"; exit 1 }
    Write-Host "      Saved to: $TAR_FILE" -ForegroundColor Green
}

# ─── Step 2: Copy tar into KIND node ─────────────────────────────────────────
Write-Host "[2/6] Copying tar into kind-control-plane node..." -ForegroundColor Yellow
docker cp $TAR_FILE kind-control-plane:/tmp/backstage-import.tar
if ($LASTEXITCODE -ne 0) { Write-Error "docker cp failed"; exit 1 }
Write-Host "      Copied successfully." -ForegroundColor Green

# ─── Step 3: Import image into containerd ────────────────────────────────────
Write-Host "[3/6] Importing image into containerd (k8s.io namespace)..." -ForegroundColor Yellow
docker exec kind-control-plane ctr -n k8s.io images import /tmp/backstage-import.tar
if ($LASTEXITCODE -ne 0) { Write-Error "ctr import failed"; exit 1 }
Write-Host "      Import done." -ForegroundColor Green

# ─── Step 4: Verify image in containerd ──────────────────────────────────────
Write-Host "[4/6] Verifying image in containerd..." -ForegroundColor Yellow
$images = docker exec kind-control-plane crictl images 2>$null
Write-Host $images
if (-not ($images -match "backstage")) {
    Write-Warning "backstage image not found in containerd! Deployment may use wrong image."
} else {
    Write-Host "      Image confirmed in containerd." -ForegroundColor Green
}

# ─── Step 5: Delete old raw-manifest deployment ──────────────────────────────
Write-Host "[5/6] Removing old raw-manifest deployment (if exists)..." -ForegroundColor Yellow
kubectl delete deployment backstage -n backstage --ignore-not-found=true 2>$null
kubectl delete service backstage -n backstage --ignore-not-found=true 2>$null
kubectl delete serviceaccount backstage -n backstage --ignore-not-found=true 2>$null
kubectl delete clusterrole backstage-read 2>$null --ignore-not-found=true
kubectl delete clusterrolebinding backstage-read 2>$null --ignore-not-found=true
Start-Sleep -Seconds 3
Write-Host "      Old resources cleaned up." -ForegroundColor Green

# ─── Step 6: Helm deploy ──────────────────────────────────────────────────────
Write-Host "[6/6] Deploying Backstage with Helm..." -ForegroundColor Yellow
helm upgrade --install backstage $HELM_DIR `
    --namespace backstage `
    --create-namespace `
    --wait `
    --timeout 5m `
    --atomic
if ($LASTEXITCODE -ne 0) { Write-Error "helm deploy failed"; exit 1 }
Write-Host "      Helm deploy successful!" -ForegroundColor Green

# ─── Done ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Backstage is LIVE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  URL:      http://localhost:3000" -ForegroundColor Cyan
Write-Host "  Login:    Sign in as Guest" -ForegroundColor Cyan
Write-Host "  Catalog:  3 services (payment, order, inventory)" -ForegroundColor Cyan
Write-Host "  Plugins:  ArgoCD | Jenkins | SonarQube | Kubernetes" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Pod status:"
kubectl get pods -n backstage
Write-Host ""
Write-Host "  Logs (last 20 lines):"
$POD = (kubectl get pod -n backstage -l app.kubernetes.io/name=backstage -o jsonpath="{.items[0].metadata.name}" 2>$null)
if ($POD) {
    kubectl logs -n backstage $POD --tail=20
}
