# scaffold-app.ps1 - Create and configure the Backstage app (Windows)
# Run from backstage-patches\ or called automatically by setup-local-backstage.ps1
# Prerequisites: Node.js 20 LTS, yarn, npx
$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot                        # backstage-patches\
$PocDir    = Split-Path $ScriptDir -Parent        # backstage-kind-poc\
$AppDir    = Join-Path $PocDir "my-developer-portal"

function Log { param($m) Write-Host "[scaffold] $m" -ForegroundColor Cyan }
function Ok  { param($m) Write-Host "[OK]       $m" -ForegroundColor Green }
function Err { param($m) Write-Host "[ERR]      $m" -ForegroundColor Red; exit 1 }

function Invoke-Cmd {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { Err "'$Exe $($Arguments -join ' ')' failed (exit $LASTEXITCODE)" }
}

# ── 1. Pre-flight ─────────────────────────────────────────────────────────────
foreach ($tool in @("node","yarn","npx")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Err "'$tool' not found. Install Node.js 20 LTS and run: npm install -g yarn"
    }
}

$nodeMajor = [int]((node --version) -replace 'v','').Split('.')[0]
if ($nodeMajor -lt 18) { Err "Node.js 18+ required. Found: $(node --version)" }
Log "Node.js $(node --version) OK"
Log "Yarn $(yarn --version) OK"

# ── 2. Scaffold ────────────────────────────────────────────────────────────────
if (Test-Path $AppDir) {
    Log "App directory already exists at $AppDir -- skipping scaffold step"
} else {
    Log "Scaffolding Backstage app to $AppDir ..."
    Push-Location $PocDir
    $env:BACKSTAGE_APP_NAME = "my-developer-portal"
    Invoke-Cmd cmd @("/c", "npx", "@backstage/create-app@latest", "--skip-install", "--path", "my-developer-portal")
    Pop-Location
    Ok "App scaffolded"
}

Push-Location $AppDir

# ── 3. Install base dependencies ──────────────────────────────────────────────
Log "Running yarn install..."
Invoke-Cmd yarn @("install")
Ok "Base dependencies installed"

# ── 4. Frontend plugins ───────────────────────────────────────────────────────
Log "Installing frontend plugins..."
Invoke-Cmd yarn @(
    "--cwd","packages/app","add",
    "@backstage-community/plugin-jenkins",
    "@roadiehq/backstage-plugin-argo-cd",
    "@backstage-community/plugin-sonarqube",
    "@backstage/plugin-kubernetes"
)
Ok "Frontend plugins installed"

# ── 5. Backend plugins ────────────────────────────────────────────────────────
Log "Installing backend plugins..."
Invoke-Cmd yarn @(
    "--cwd","packages/backend","add",
    "@backstage-community/plugin-jenkins-backend",
    "@backstage-community/plugin-sonarqube-backend",
    "@backstage/plugin-kubernetes-backend",
    "@backstage/plugin-permission-backend",
    "@backstage/plugin-permission-backend-module-allow-all-policy",
    "better-sqlite3"
)
Ok "Backend plugins installed"

# ── 6. Apply patches ──────────────────────────────────────────────────────────
Log "Applying EntityPage.tsx patch..."
New-Item -ItemType Directory -Force -Path "packages\app\src\components\catalog" | Out-Null
Copy-Item "$ScriptDir\EntityPage.tsx" "packages\app\src\components\catalog\EntityPage.tsx" -Force
Ok "EntityPage.tsx patched"

Log "Applying backend index.ts patch..."
Copy-Item "$ScriptDir\backend-index.ts" "packages\backend\src\index.ts" -Force
Ok "backend/src/index.ts patched"

Log "Copying app-config.local.yaml..."
Copy-Item "$ScriptDir\app-config.local.yaml" "app-config.local.yaml" -Force
Ok "app-config.local.yaml copied"

# ── 7. Copy catalog files ─────────────────────────────────────────────────────
Log "Copying catalog files..."
$catalogDest = Join-Path $AppDir "catalog"
New-Item -ItemType Directory -Force -Path $catalogDest | Out-Null
Copy-Item -Recurse -Force "$PocDir\dummy-services\*" $catalogDest
Ok "Catalog files copied to $catalogDest"

Pop-Location

Ok "Backstage scaffold complete!"
Write-Host ""
Write-Host "  Next: run .\setup-local-backstage.ps1 -SkipScaffold" -ForegroundColor White
