# setup-local-backstage.ps1 - Master PoC automation script (Windows / PowerShell)
# Usage:
#   .\setup-local-backstage.ps1
#   .\setup-local-backstage.ps1 -SkipScaffold    # if app already built
#   .\setup-local-backstage.ps1 -SkipCluster     # if KIND cluster already exists
param(
    [switch]$SkipScaffold,
    [switch]$SkipCluster
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptDir = $PSScriptRoot
$AppDir    = Join-Path $ScriptDir "my-developer-portal"

function Log  { param($msg) Write-Host "[setup] $msg" -ForegroundColor Cyan }
function Ok   { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green }
function Warn { param($msg) Write-Host "[!]     $msg" -ForegroundColor Yellow }
function Err  { param($msg) Write-Host "[ERR]   $msg" -ForegroundColor Red; exit 1 }

function Step {
    param($msg)
    Write-Host ""
    Write-Host ("=" * 56) -ForegroundColor Magenta
    Write-Host "  $msg"    -ForegroundColor Magenta
    Write-Host ("=" * 56) -ForegroundColor Magenta
}

function Invoke-Cmd {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        Err "'$Exe $($Arguments -join ' ')' failed with exit code $LASTEXITCODE"
    }
}

function Wait-ForDeployment {
    param([string]$Name, [string]$Namespace, [int]$TimeoutSec = 300)
    Log "Waiting for deployment/$Name in ns=$Namespace (timeout ${TimeoutSec}s)..."
    Invoke-Cmd kubectl @("wait","--for=condition=available","deployment/$Name","-n",$Namespace,"--timeout=${TimeoutSec}s")
}

# ── Step 0: Pre-flight checks ─────────────────────────────────────────────────
Step "Step 0: Pre-flight checks"

foreach ($tool in @("docker","kind","kubectl")) {
    $found = Get-Command $tool -ErrorAction SilentlyContinue
    if (-not $found) { Err "'$tool' not found. Please install it first." }
    Ok "$tool found at: $($found.Source)"
}

if (-not $SkipScaffold) {
    foreach ($tool in @("node","yarn","npx")) {
        $found = Get-Command $tool -ErrorAction SilentlyContinue
        if (-not $found) { Err "'$tool' not found. Install Node.js 20 LTS + run: npm install -g yarn" }
        Ok "$tool found at: $($found.Source)"
    }
}

$_prevEA = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
docker info *>$null
$_dockerExit = $LASTEXITCODE
$ErrorActionPreference = $_prevEA
if ($_dockerExit -ne 0) { Err "Docker daemon not running. Please start Docker Desktop." }
Ok "Docker daemon is running"

# ── Step 1: KIND cluster ──────────────────────────────────────────────────────
Step "Step 1: KIND cluster"

if ($SkipCluster) {
    Warn "Skipping cluster creation (-SkipCluster flag set)"
} else {
    $existingClusters = kind get clusters 2>&1
    if ($existingClusters -match "kind") {
        Warn "KIND cluster 'kind' already exists -- skipping creation"
    } else {
        Log "Creating KIND cluster 'kind'..."
        Invoke-Cmd kind @("create","cluster","--name","kind","--config","$ScriptDir\kind-config.yaml","--wait","120s")
        Ok "KIND cluster created"
    }
}

Invoke-Cmd kubectl @("config","use-context","kind-kind")
Ok "kubectl context set to kind-kind"

# ── Step 2: Install ArgoCD ────────────────────────────────────────────────────
Step "Step 2: Install ArgoCD"

$_prevEA = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
$nsExists = kubectl get namespace argocd 2>$null
$ErrorActionPreference = $_prevEA

if ($nsExists) {
    Warn "Namespace 'argocd' already exists -- skipping ArgoCD install"
} else {
    Log "Creating argocd namespace..."
    Invoke-Cmd kubectl @("create","namespace","argocd")

    Log "Installing ArgoCD stable manifests..."
    Invoke-Cmd kubectl @("apply","--server-side","-n","argocd","-f","https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml")

    Log "Waiting 15s for pods to initialise..."
    Start-Sleep -Seconds 15

    Wait-ForDeployment -Name "argocd-server" -Namespace "argocd" -TimeoutSec 300
    Ok "ArgoCD installed"
}

# ── Step 3: ArgoCD Applications ───────────────────────────────────────────────
Step "Step 3: Apply ArgoCD demo applications"

Log "Applying ArgoCD Application manifests..."
Invoke-Cmd kubectl @("apply","-f","$ScriptDir\argocd-apps")
Ok "ArgoCD applications applied (payment-service, order-service, inventory-service)"

# ── Step 4: Backstage namespace + RBAC ───────────────────────────────────────
Step "Step 4: Backstage namespace and RBAC"

Invoke-Cmd kubectl @("apply","-f","$ScriptDir\k8s\namespace.yaml")
Ok "Namespace 'backstage' applied"

Invoke-Cmd kubectl @("apply","-f","$ScriptDir\k8s\rbac.yaml")
Ok "RBAC applied (ServiceAccount + ClusterRole + Binding)"

# ── Step 5: ArgoCD credentials ────────────────────────────────────────────────
Step "Step 5: Retrieve ArgoCD admin credentials"

$ArgoCDPassword  = ""
$ArgoCDAuthToken = ""

for ($i = 1; $i -le 12; $i++) {
    try {
        $b64raw = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>$null
        if ($LASTEXITCODE -eq 0 -and $b64raw) {
            $ArgoCDPassword  = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64raw.Trim()))
            $ArgoCDAuthToken = $ArgoCDPassword
            break
        }
    } catch { }
    Log "Waiting for ArgoCD admin secret... ($i/12)"
    Start-Sleep -Seconds 10
}

if ($ArgoCDPassword) {
    Ok "ArgoCD admin password retrieved: $ArgoCDPassword"
} else {
    Warn "Could not retrieve ArgoCD password -- ArgoCD plugin will use empty token"
}

# Build the secret YAML without embedded quotes inside here-string
$secretYamlLines = @(
    "apiVersion: v1",
    "kind: Secret",
    "metadata:",
    "  name: backstage-secrets",
    "  namespace: backstage",
    "type: Opaque",
    "stringData:",
    "  argocd-token: $ArgoCDAuthToken"
)
$secretYaml = $secretYamlLines -join "`n"
$secretYaml | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Err "Failed to apply backstage-secrets" }
Ok "Backstage secrets applied"

# ── Step 6: Mock server ───────────────────────────────────────────────────────
Step "Step 6: Build and load mock server"

Log "Building mock-server Docker image..."
Invoke-Cmd docker @("build","-t","mock-server:latest","$ScriptDir\mock-server")
Ok "mock-server:latest built"

Log "Loading mock-server image into KIND cluster..."
Invoke-Cmd kind @("load","docker-image","mock-server:latest","--name","kind")
Ok "mock-server:latest loaded"

Log "Deploying mock server to cluster..."
Invoke-Cmd kubectl @("apply","-f","$ScriptDir\k8s\mock-server")

Log "Waiting for mock server to be ready..."
Wait-ForDeployment -Name "mock-server" -Namespace "backstage" -TimeoutSec 60
Ok "Mock server is ready"

# ── Step 7: Scaffold Backstage ────────────────────────────────────────────────
Step "Step 7: Scaffold and configure Backstage app"

if ($SkipScaffold) {
    Warn "Skipping scaffold (-SkipScaffold flag set)"
} elseif (Test-Path $AppDir) {
    Warn "App already exists at $AppDir -- skipping scaffold"
    Warn "To re-scaffold: remove the directory and re-run without -SkipScaffold"
} else {
    Log "Running scaffold-app.ps1..."
    & "$ScriptDir\backstage-patches\scaffold-app.ps1"
    if ($LASTEXITCODE -ne 0) { Err "scaffold-app.ps1 failed" }
    Ok "Backstage app scaffolded and configured"
}

# Always sync catalog files into the app directory
if (Test-Path $AppDir) {
    $catalogDest = Join-Path $AppDir "catalog"
    New-Item -ItemType Directory -Force -Path $catalogDest | Out-Null
    Copy-Item -Recurse -Force "$ScriptDir\dummy-services\*" $catalogDest
    Ok "Catalog files synced to $catalogDest"
}

# ── Step 8: Build Backstage Docker image ──────────────────────────────────────
Step "Step 8: Build Backstage Docker image"

if (-not (Test-Path $AppDir)) {
    Err "Backstage app not found at $AppDir. Run without -SkipScaffold first."
}

Log "Building backstage:latest (takes 5-10 min)..."
Invoke-Cmd docker @("build","-t","backstage:latest","-f","$ScriptDir\backstage-patches\Dockerfile","$AppDir")
Ok "backstage:latest built"

Log "Loading backstage image into KIND cluster..."
Invoke-Cmd kind @("load","docker-image","backstage:latest","--name","kind")
Ok "backstage:latest loaded into KIND"

# ── Step 9: Deploy Backstage ──────────────────────────────────────────────────
Step "Step 9: Deploy Backstage"

Invoke-Cmd kubectl @("apply","-f","$ScriptDir\k8s\deployment.yaml")
Invoke-Cmd kubectl @("apply","-f","$ScriptDir\k8s\service.yaml")
Ok "Backstage deployment and service applied"

Log "Waiting for Backstage pod to be ready (up to 5 min)..."
Invoke-Cmd kubectl @("wait","--for=condition=ready","pod","-l","app=backstage","-n","backstage","--timeout=300s")
Ok "Backstage pod is running"

# ── Step 10: Expose ArgoCD UI ─────────────────────────────────────────────────
Step "Step 10: Expose ArgoCD UI via NodePort"

$patchJson = '{"spec":{"type":"NodePort","ports":[{"name":"https","port":443,"targetPort":8080,"nodePort":30001}]}}'
kubectl patch svc argocd-server -n argocd -p $patchJson 2>&1 | Out-Null
Ok "ArgoCD service patched to NodePort 30001 -> host port 8080"

# ── Verification ──────────────────────────────────────────────────────────────
Step "Verification"

Write-Host ""
Write-Host "--- Nodes ---" -ForegroundColor DarkGray
kubectl get nodes

Write-Host ""
Write-Host "--- Backstage pods ---" -ForegroundColor DarkGray
kubectl get pods -n backstage

Write-Host ""
Write-Host "--- ArgoCD applications ---" -ForegroundColor DarkGray
kubectl get applications -n argocd --no-headers `
    -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status" 2>&1

Write-Host ""
Write-Host ("=" * 56) -ForegroundColor Green
Write-Host "  SETUP COMPLETE!" -ForegroundColor Green
Write-Host ("=" * 56) -ForegroundColor Green
Write-Host "  Backstage : http://localhost:3000" -ForegroundColor White
Write-Host "  ArgoCD UI : http://localhost:8080" -ForegroundColor White
if ($ArgoCDPassword) {
    Write-Host "              user: admin" -ForegroundColor White
    Write-Host "              pass: $ArgoCDPassword" -ForegroundColor White
}
Write-Host ("=" * 56) -ForegroundColor Green
Write-Host ""
