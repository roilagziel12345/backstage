# 🚀 Backstage Developer Portal PoC — KIND + Jenkins + ArgoCD + SonarQube

A **fully automated** local Backstage Developer Portal deployed on a KIND (Kubernetes IN Docker) cluster, complete with Jenkins, ArgoCD, SonarQube, and Kubernetes plugins backed by realistic mock data.

---

## 📋 Prerequisites

Run everything directly on **Windows** using PowerShell with Docker Desktop (Linux containers mode):

| Requirement | Version | Install |
|-------------|---------|---------|
| Docker Desktop | Latest | [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/) — enable **Linux containers** |
| KIND | ≥ 0.20 | `winget install Kubernetes.kind` or [kind.sigs.k8s.io](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) |
| kubectl | ≥ 1.28 | `winget install Kubernetes.kubectl` |
| Node.js | 20 LTS | `winget install OpenJS.NodeJS.LTS` |
| Yarn | 1.x (classic) | `npm install -g yarn` |
| npx | (bundled with npm/Node) | ✅ |

**Docker Resources**: Allocate at least **8 GB RAM** and **4 CPUs** in Docker Desktop → Settings → Resources → Advanced.

> **PowerShell Execution Policy**: If scripts are blocked, run once:
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

---

## 🏗️ Project Structure

```
backstage-kind-poc/
├── setup-local-backstage.sh          # ← Master automation script (run this)
├── generate-mock-data.sh             # Refresh ArgoCD apps & verify catalog
├── kind-config.yaml                  # KIND cluster: ports 3000 (Backstage) + 8080 (ArgoCD)
│
├── k8s/                              # Kubernetes manifests
│   ├── namespace.yaml                # backstage namespace
│   ├── rbac.yaml                     # ServiceAccount + ClusterRole + Binding
│   ├── deployment.yaml               # Backstage Deployment
│   ├── service.yaml                  # NodePort → 30000 → host:3000
│   └── mock-server/
│       ├── deployment.yaml           # Mock API server Deployment
│       ├── service.yaml              # ClusterIP mock-server:4010
│       └── Dockerfile                # (reference copy)
│
├── mock-server/                      # Express mock API (Jenkins + SonarQube)
│   ├── server.js                     # Main Express app on port 4010
│   ├── package.json
│   ├── Dockerfile
│   └── routes/
│       ├── jenkins.js                # GET /job/:name/api/json — 5 build history
│       └── sonarqube.js              # GET /sonarqube/api/measures/component, etc.
│
├── dummy-services/                   # Backstage catalog entities
│   ├── all-services.yaml             # Location pointing to all 3 services
│   ├── payment-service/catalog-info.yaml
│   ├── order-service/catalog-info.yaml
│   └── inventory-service/catalog-info.yaml
│
├── argocd-apps/                      # ArgoCD Application manifests
│   ├── payment-service.yaml          # → argoproj/argocd-example-apps (guestbook)
│   ├── order-service.yaml            # → argoproj/argocd-example-apps (helm-guestbook)
│   └── inventory-service.yaml        # → argoproj/argocd-example-apps (kustomize-guestbook)
│
└── backstage-patches/                # Backstage source patches
    ├── scaffold-app.sh               # Phase 1: scaffold + install plugins
    ├── EntityPage.tsx                # Full entity page with all plugin tabs
    ├── backend-index.ts              # New backend system with all plugins
    ├── app-config.local.yaml         # Plugin configuration (Jenkins/SonarQube/ArgoCD/K8s)
    └── Dockerfile                    # Multi-stage Backstage production image
```

---

## ⚡ Quick Start

```powershell
# Open PowerShell (not CMD) in the project directory
cd C:\repos\DEVOPSROI\DEVOPSROI\backstage-kind-poc

# Run the full setup (takes ~15-20 min first run)
.\setup-local-backstage.ps1
```

### Optional flags

```powershell
.\setup-local-backstage.ps1 -SkipCluster    # KIND cluster already exists
.\setup-local-backstage.ps1 -SkipScaffold   # Backstage app already built

# Run just mock data refresh after cluster is up:
.\generate-mock-data.ps1

# Run only the scaffold step:
.\backstage-patches\scaffold-app.ps1
```

---

## 🌐 Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| **Backstage** | http://localhost:3000 | Guest (no login) |
| **ArgoCD UI** | http://localhost:8080 | admin / *printed by script* |

---

## 🔍 What You'll See

### Backstage Catalog

Three services are pre-loaded:

| Service | Team | Stack | CI Builds | SonarQube |
|---------|------|-------|-----------|-----------|
| **payment-service** | platform-team | Java / Spring Boot | ✅ 5 builds (#38–42) | Coverage 87.5%, PASSED |
| **order-service** | backend-team | Node.js / Express | ⚠️ 5 builds (#23–27) | Coverage 74.3%, PASSED |
| **inventory-service** | inventory-team | Python / FastAPI | ✅ 5 builds (#11–15) | Coverage 91.2%, PASSED |

### Entity Tabs (per service)

| Tab | Plugin | Data Source |
|-----|--------|-------------|
| **Overview** | Multiple | Cards: Jenkins latest run, ArgoCD status, SonarQube summary |
| **CI/CD** | Jenkins | Build history table with status, duration, commit |
| **ArgoCD** | ArgoCD | Sync status, health, revision |
| **Code Quality** | SonarQube | Bugs, vulnerabilities, coverage, quality gate |
| **Kubernetes** | Kubernetes | Live pods, deployments from KIND cluster |
| **API** | API Docs | Consumed/provided APIs |
| **Docs** | TechDocs | Documentation |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Host Machine (Windows)                                  │
│  ┌──────────────────────────────────────────────────┐   │
│  │  WSL2 / Docker Desktop                           │   │
│  │  ┌────────────────────────────────────────────┐  │   │
│  │  │  KIND Cluster: kind-backstage              │  │   │
│  │  │                                            │  │   │
│  │  │  ┌──────────────┐  ┌───────────────────┐  │  │   │
│  │  │  │ namespace:   │  │ namespace: argocd │  │  │   │
│  │  │  │ backstage    │  │                   │  │  │   │
│  │  │  │              │  │ ArgoCD Server     │  │  │   │
│  │  │  │ Backstage    │  │ ArgoCD Repo Srv   │  │  │   │
│  │  │  │ (port 7007)  │  │ ArgoCD App Ctrl   │  │  │   │
│  │  │  │      │       │  │                   │  │  │   │
│  │  │  │ Mock Server  │  │ Applications:     │  │  │   │
│  │  │  │ (port 4010)  │  │  payment-service  │  │  │   │
│  │  │  │  Jenkins API │  │  order-service    │  │  │   │
│  │  │  │  SonarQube   │  │  inventory-svc    │  │  │   │
│  │  │  └──────────────┘  └───────────────────┘  │  │   │
│  │  └────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  Browser → http://localhost:3000  (Backstage)            │
│  Browser → http://localhost:8080  (ArgoCD)               │
└─────────────────────────────────────────────────────────┘
```

---

## 🛠️ Troubleshooting

### KIND cluster not creating
```powershell
# Check Docker is running and has enough resources
docker info | Select-String -Pattern "Total Memory|CPUs"
# Should show: Total Memory: 8GiB+, CPUs: 4+

# If kind is not found:
winget install Kubernetes.kind
```

### Backstage pod CrashLoopBackOff
```powershell
kubectl logs -n backstage deployment/backstage --previous
# Common cause: app-config parsing error or missing plugin package
```

### Mock server not responding
```powershell
# Test from inside the cluster
kubectl run test-curl --image=curlimages/curl -it --rm --restart=Never `
  -- curl http://mock-server.backstage.svc.cluster.local:4010/health
```

### ArgoCD apps not syncing
```powershell
kubectl get applications -n argocd
kubectl describe application payment-service -n argocd
# Likely cause: GitHub rate limiting on unauthenticated requests
```

### Jenkins plugin not showing data
Check that the `jenkins.io/job-full-name` annotation matches exactly what the mock server expects (`payment-service`, `order-service`, or `inventory-service`).

### Rebuild only Backstage image
```powershell
docker build -t backstage:latest -f backstage-patches\Dockerfile my-developer-portal
kind load docker-image backstage:latest --name backstage
kubectl rollout restart deployment/backstage -n backstage
```

---

## 🧹 Teardown

```powershell
# Delete the KIND cluster (removes everything)
kind delete cluster --name backstage

# Remove the built Docker images
docker rmi backstage:latest mock-server:latest
```

---

## 📎 Key Plugin Annotations Reference

Add these to any `catalog-info.yaml` to enable plugin integrations:

```yaml
annotations:
  # Jenkins (CI/CD tab)
  jenkins.io/job-full-name: my-service-job-name

  # ArgoCD (ArgoCD tab)
  argocd/app-name: my-argocd-app

  # SonarQube (Code Quality tab)
  sonarqube.org/project-key: my-project-key

  # Kubernetes (Kubernetes tab)
  backstage.io/kubernetes-id: my-service
  backstage.io/kubernetes-namespace: default
```

---

## 🔗 References

- [Backstage Documentation](https://backstage.io/docs)
- [KIND Documentation](https://kind.sigs.k8s.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Backstage Jenkins Plugin](https://github.com/backstage/community-plugins/tree/main/workspaces/jenkins)
- [Backstage SonarQube Plugin](https://github.com/backstage/community-plugins/tree/main/workspaces/sonarqube)
- [RoadieHQ ArgoCD Plugin](https://github.com/RoadieHQ/roadie-backstage-plugins/tree/main/plugins/frontend/backstage-plugin-argo-cd)
