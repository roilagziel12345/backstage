# Backstage KIND Developer Portal

A local proof of concept for exploring a Backstage developer portal with Kubernetes visibility, Argo CD delivery status, Jenkins build history, and SonarQube quality data. It runs Backstage and a small mock integration server inside a local KIND cluster.

This repository is a demonstration environment, not a production deployment.

## What is in the repository

| Area | Implementation | Source |
| --- | --- | --- |
| Portal | Backstage frontend and backend, Yarn workspace | `backstage-kind-poc/my-developer-portal/` |
| Catalog | Payment, order, and inventory service entities | `backstage-kind-poc/my-developer-portal/catalog/` |
| Delivery | Three Argo CD `Application` resources | `backstage-kind-poc/argocd-apps/` |
| Runtime | KIND cluster and Kubernetes manifests | `backstage-kind-poc/kind-config.yaml`, `backstage-kind-poc/k8s/` |
| Packaging | Backstage Helm chart | `backstage-kind-poc/helm/backstage/` |
| Integrations | Mock Jenkins and SonarQube HTTP endpoints | `backstage-kind-poc/mock-server/` |
| Automation | PowerShell and Bash setup scripts | `backstage-kind-poc/setup-local-backstage.ps1`, `backstage-kind-poc/setup-local-backstage.sh` |

## Architecture

```text
Browser
  |
  | localhost:3000
  v
KIND cluster: backstage
  |
  +-- Backstage service :7007 / NodePort 30000
  |     |
  |     +-- Software catalog: payment, order, inventory
  |     +-- Kubernetes API through a read-only ServiceAccount
  |     +-- Argo CD API through ARGOCD_AUTH_TOKEN
  |     +-- Jenkins and SonarQube plugins
  |              |
  |              v
  |        mock-server service :4010
  |
  +-- Argo CD service / NodePort 30001
        |
        +-- guestbook
        +-- helm-guestbook
        +-- kustomize-guestbook
```

The three Argo CD applications all use `argoproj/argocd-example-apps`; they do not deploy source code from the catalog's example service URLs.

## Prerequisites

For the complete local-cluster workflow:

| Tool | Repository evidence | Notes |
| --- | --- | --- |
| Docker | Images are built locally and loaded into KIND | Docker Desktop is suitable on Windows |
| KIND | Creates the `backstage` cluster | The config maps host ports 3000 and 8080 |
| kubectl | Applies and inspects Kubernetes resources | Must target the intended local cluster |
| Helm | Required by `deploy-backstage.ps1` | The main setup scripts use raw manifests |
| Node.js | `22` or `24` | Required by `my-developer-portal/package.json` |
| Yarn | `4.4.1` | Declared by `packageManager` |
| PowerShell 7 or Bash | Runs the matching setup script | Use the script for your operating system |

The setup-script comments still mention Node 20. The committed package manifest is the stronger constraint and requires Node 22 or 24.

Recommended local capacity from the existing project notes is at least 4 CPUs, 8 GB RAM, and roughly 10 GB free disk space.

## Quick start

From the repository root:

### PowerShell

```powershell
cd backstage-kind-poc
./setup-local-backstage.ps1
```

### Bash

```bash
cd backstage-kind-poc
bash setup-local-backstage.sh
```

After a successful run:

| Service | Address |
| --- | --- |
| Backstage | `http://localhost:3000` |
| Argo CD | `http://localhost:8080` |

The Backstage configuration enables guest sign-in for this PoC.

### Reuse an existing environment

PowerShell:

```powershell
./setup-local-backstage.ps1 -SkipCluster -SkipScaffold
```

Bash:

```bash
bash setup-local-backstage.sh --skip-cluster --skip-scaffold
```

The application directory is already committed, so the scripts detect it and skip scaffolding during a normal run.

## What the setup performs

1. Checks required command-line tools.
2. Creates a KIND cluster from `kind-config.yaml`, unless skipped or already present.
3. Creates the `argocd` namespace and installs Argo CD.
4. Applies the three Argo CD application definitions.
5. Creates the `backstage` namespace and read-only cluster RBAC.
6. Creates `backstage-secrets` with the retrieved Argo CD credential.
7. Builds and loads `mock-server:latest`, then deploys it on port 4010.
8. Uses the committed Backstage application and catalog.
9. Builds and loads `backstage:latest`, then deploys it on port 7007.
10. Exposes Backstage on host port 3000 and Argo CD on host port 8080.

## Catalog and mock data

The catalog contains three production-lifecycle components in the `ecommerce` system.

| Component | Owner | Jenkins job | Argo CD app | SonarQube key |
| --- | --- | --- | --- | --- |
| `payment-service` | `platform-team` | `payment-service` | `payment-service` | `payment-service` |
| `order-service` | `backend-team` | `order-service` | `order-service` | `order-service` |
| `inventory-service` | `inventory-team` | `inventory-service` | `inventory-service` | `inventory-service` |

The Jenkins histories and SonarQube measures displayed by the portal are static demonstration data returned by `mock-server/routes/jenkins.js` and `mock-server/routes/sonarqube.js`. They are not results from real CI or code analysis systems.

## Configuration

### Environment variables

| Variable | Used by | Purpose |
| --- | --- | --- |
| `ARGOCD_AUTH_TOKEN` | Kubernetes and Helm Backstage deployments | Authenticates the Backstage Argo CD integration |
| `ARGOCD_ADMIN_PASSWORD` | `backstage-patches/app-config.local.yaml` | Optional local Argo CD password substitution |
| `GITHUB_TOKEN` | Base Backstage app configuration | Optional GitHub integration token |
| `POSTGRES_HOST` | Production Backstage configuration | PostgreSQL host |
| `POSTGRES_PORT` | Production Backstage configuration | PostgreSQL port |
| `POSTGRES_USER` | Production Backstage configuration | PostgreSQL user |
| `POSTGRES_PASSWORD` | Production Backstage configuration | PostgreSQL password |
| `PORT` | Mock server | Listening port; defaults to `4010` |

The Helm chart renders its Backstage configuration from `helm/backstage/values.yaml`. The raw-manifest path uses configuration assembled by the setup workflow. Keep those paths aligned when changing ports, credentials, catalog locations, or integration endpoints.

### Network dependencies

The default setup is not suitable for an air-gapped network without preparation:

- Argo CD is installed from a `raw.githubusercontent.com` manifest.
- Each Argo CD application pulls from `github.com/argoproj/argocd-example-apps` at `HEAD`.
- A fresh dependency installation or application scaffold uses external package registries.
- Container base images must already be present or available from an internal registry.

For a closed network, mirror and pin the Argo CD install manifest, the three example workloads, package dependencies, and container images. Replace external URLs before running setup.

## Development commands

Run these from `backstage-kind-poc/my-developer-portal` after dependencies are available:

| Command | Purpose |
| --- | --- |
| `yarn start` | Starts the Backstage development workspace |
| `yarn build:backend` | Builds the backend workspace |
| `yarn build:all` | Builds all workspaces |
| `yarn build-image` | Builds the backend container image |
| `yarn tsc` | Runs incremental TypeScript checks |
| `yarn tsc:full` | Runs full TypeScript checks |
| `yarn test` | Runs tests changed since the default branch |
| `yarn test:all` | Runs all tests with coverage |
| `yarn test:e2e` | Runs Playwright end-to-end tests |
| `yarn lint` | Lints changed files |
| `yarn lint:all` | Lints the complete workspace |
| `yarn prettier:check` | Checks formatting |
| `yarn fix` | Applies lint and formatting fixes |
| `yarn clean` | Cleans workspace build output and cache |

The mock server can be developed separately from `backstage-kind-poc/mock-server` with `npm start` or `npm run dev`; it requires Node 18 or newer.

## Deploy with Helm

`deploy-backstage.ps1` expects all of the following to already exist:

- a running KIND node named `kind-control-plane`;
- a local `backstage:latest` image;
- Docker, kubectl, and Helm;
- the repository's `helm/backstage` chart.

Run from `backstage-kind-poc`:

```powershell
./deploy-backstage.ps1
```

The script saves the image to `backstage-v2.tar`, imports it into the KIND node, removes any old raw-manifest deployment, and performs an atomic Helm upgrade/install with a five-minute timeout.

## Verify the deployment

```bash
kubectl get nodes
kubectl get pods -n backstage
kubectl get services -n backstage
kubectl get applications -n argocd
kubectl logs -n backstage deployment/backstage --tail=100
```

The relevant health endpoints are:

- Backstage: `/healthcheck` on container port 7007.
- Mock server: `/health` on container port 4010.

## Repository map

```text
backstage-kind-poc/
|-- argocd-apps/             Argo CD Application resources
|-- backstage-patches/       PoC configuration and source patches
|-- dummy-services/          Source copy of catalog entities
|-- helm/backstage/          Helm chart for Backstage
|-- k8s/                     Namespace, RBAC, workloads, and services
|-- mock-server/             Express-based Jenkins/SonarQube simulator
|-- my-developer-portal/     Backstage Yarn workspace and runtime catalog
|-- deploy-backstage.ps1     Helm deployment helper
|-- generate-mock-data.sh    Argo/catalog verification helper
|-- kind-config.yaml         Local cluster and port mappings
|-- setup-local-backstage.ps1
`-- setup-local-backstage.sh
```

## Known limitations and safety notes

- Guest authentication and `dangerouslyDisableDefaultAuthPolicy` are enabled. Do not expose this configuration as a production portal.
- Kubernetes API TLS verification is disabled in the PoC configuration.
- Jenkins and SonarQube credentials in configuration are mock values, but should still be replaced before adapting the chart.
- The setup scripts create cluster-scoped RBAC and Kubernetes secrets and install workloads into the current cluster. Confirm `kubectl config current-context` first.
- The Argo CD resources use automated sync, pruning, and self-healing.
- The Helm chart uses an in-memory SQLite database; data does not persist across restarts.
- `deploy-backstage.ps1` creates a large local `backstage-v2.tar` file and removes an existing raw-manifest Backstage deployment before installing the Helm release.
- The PowerShell setup uses the context name `kind-kind` in some operations while the Bash workflow creates the `backstage` cluster. Review the active context rather than assuming both paths are interchangeable.
- No repository-level license file was found. Do not assume redistribution terms.

## Troubleshooting

### A pod cannot pull an image

Both workloads use `imagePullPolicy: Never`. Confirm the local images were loaded into the `backstage` KIND cluster:

```bash
kind load docker-image backstage:latest --name backstage
kind load docker-image mock-server:latest --name backstage
```

### Backstage cannot reach an integration

```bash
kubectl get pods,services -n backstage
kubectl logs -n backstage deployment/backstage --tail=100
kubectl logs -n backstage deployment/mock-server --tail=100
```

Check that the mock service is named `mock-server` in namespace `backstage` and listens on port 4010.

### Argo CD applications do not sync

```bash
kubectl get applications -n argocd
kubectl describe application payment-service -n argocd
```

In a restricted network, first confirm that Argo CD can access the mirrored application source. The committed definitions point to public GitHub.

### Port 3000 or 8080 is unavailable

Those host ports are fixed in `kind-config.yaml`. Change the KIND port mapping together with the corresponding NodePort and Backstage base URL values.

## Evidence scope

This document was derived from committed package manifests, scripts, application configuration, catalog entities, Kubernetes resources, the Helm chart, and mock-server routes. Commands and paths above exist in the repository; no deployment result is claimed because the code was not executed while preparing this document.
