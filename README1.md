# Backstage Developer Portal PoC

A local Backstage proof of concept running on KIND with the packages, backend modules, configuration, mock APIs, and patch sources for Argo CD, Jenkins, SonarQube, and Kubernetes integrations.

## Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Configuration](#configuration)
- [Development](#development)
- [Deployment](#deployment)
- [Validation](#validation)
- [Troubleshooting](#troubleshooting)
- [Security and limitations](#security-and-limitations)
- [Repository structure](#repository-structure)

## Overview

The project demonstrates how Backstage can aggregate common developer-platform signals in a single catalog. It includes a committed Backstage application, three example services, a local Kubernetes environment, an Argo CD installation flow, and a mock server that implements the Jenkins and SonarQube endpoints used by the demo.

| Item | Value |
| --- | --- |
| Project directory | `backstage-kind-poc` |
| Portal URL | `http://localhost:3000` |
| Argo CD URL | `http://localhost:8080` |
| Backstage container port | `7007` |
| Mock-server port | `4010` |
| KIND cluster name | `backstage` in the Bash workflow |
| Catalog services | `payment-service`, `order-service`, `inventory-service` |
| Backstage package manager | Yarn 4.4.1 |
| Backstage Node.js requirement | 22 or 24 |

## Features

- Backstage software catalog with three e-commerce service components.
- Jenkins, SonarQube, Kubernetes, and Argo CD packages and configuration.
- Static Jenkins build and SonarQube quality data for repeatable demonstrations.
- Argo CD applications with automated sync, pruning, and self-healing.
- Read-only Kubernetes RBAC for the Backstage ServiceAccount.
- Raw Kubernetes manifests and a separate Helm chart.
- PowerShell and Bash setup workflows.
- Local images loaded directly into KIND with no runtime image pull.

### Integration implementation status

| Layer | Current state |
| --- | --- |
| Catalog | Enabled by the committed frontend and backed by three entity files |
| Jenkins backend | Imported by the committed backend |
| SonarQube backend | Imported by the committed backend |
| Kubernetes backend | Imported by the committed backend |
| Frontend packages | Jenkins, SonarQube, Kubernetes, and Argo CD dependencies are declared |
| Integration entity pages | Present in `backstage-patches/EntityPage.tsx`, but absent from the committed application source tree |

The committed `packages/app/src/App.tsx` registers only `catalogPlugin` and `navModule`. Normal setup skips scaffolding because `my-developer-portal/` already exists, so it does not apply the integration entity-page patch. Plugin panels should be treated as intended but unverified until the frontend wiring is completed.

## Architecture

```text
                         +----------------------+
                         | Browser              |
                         | localhost:3000       |
                         +----------+-----------+
                                    |
                                    v
                         +----------------------+
                         | Backstage            |
                         | frontend + backend   |
                         +----+--------+--------+
                              |        |
                 +------------+        +----------------+
                 |                                      |
                 v                                      v
       +---------------------+                +---------------------+
       | Kubernetes / Argo CD|                | Mock server         |
       | cluster state       |                | Jenkins routes      |
       | delivery state      |                | SonarQube routes    |
       +---------------------+                +---------------------+
```

All runtime components are intended to run in the local KIND cluster. Host port 3000 maps to the Backstage NodePort, and host port 8080 maps to the Argo CD NodePort.

## Prerequisites

Install or provide these tools before using the full setup workflow:

| Requirement | Used for |
| --- | --- |
| Docker | Building and storing local container images |
| KIND | Running the local Kubernetes cluster |
| kubectl | Installing and inspecting cluster resources |
| Node.js 22 or 24 | Satisfying the Backstage root package engine |
| Yarn 4.4.1 | Managing the Backstage workspace |
| PowerShell 7 or Bash | Running the appropriate setup workflow |
| Helm | Running `deploy-backstage.ps1` |

The setup-script comments say Node 20 LTS, but the committed root package manifest requires Node 22 or 24. The package manifest should be treated as authoritative.

The existing project notes recommend at least 4 CPUs, 8 GB RAM, and about 10 GB of free disk space for Docker Desktop.

## Installation

Clone the repository using your normal approved Git host, then enter the project directory:

```bash
cd backstage-kind-poc
```

Choose one setup command.

### PowerShell

```powershell
./setup-local-backstage.ps1
```

Optional switches:

```powershell
./setup-local-backstage.ps1 -SkipCluster
./setup-local-backstage.ps1 -SkipScaffold
./setup-local-backstage.ps1 -SkipCluster -SkipScaffold
```

### Bash

```bash
bash setup-local-backstage.sh
```

Optional flags:

```bash
bash setup-local-backstage.sh --skip-cluster
bash setup-local-backstage.sh --skip-scaffold
bash setup-local-backstage.sh --skip-cluster --skip-scaffold
```

The Backstage application is already present in `my-developer-portal`. Both setup workflows detect it during a standard run.

## Usage

After setup succeeds:

1. Open `http://localhost:3000`.
2. Use the configured guest sign-in.
3. Open the catalog.
4. Select payment, order, or inventory.
5. Inspect the catalog. After the integration page patch is wired and verified, inspect the CI, quality, delivery, and Kubernetes panels.

### Catalog model

| Component | Type | Lifecycle | Owner | System |
| --- | --- | --- | --- | --- |
| `payment-service` | service | production | `platform-team` | `ecommerce` |
| `order-service` | service | production | `backend-team` | `ecommerce` |
| `inventory-service` | service | production | `inventory-team` | `ecommerce` |

The catalog annotations use each component name as its Jenkins job, Argo CD application, SonarQube project, and Kubernetes identifier.

### Demonstration data

`mock-server/routes/jenkins.js` returns five builds per service. `mock-server/routes/sonarqube.js` returns quality measures including the following fixture coverage values:

| Component | Mock coverage |
| --- | --- |
| `payment-service` | 87.5% |
| `order-service` | 74.3% |
| `inventory-service` | 91.2% |

These values are static fixtures and do not describe test coverage in this repository.

## Configuration

### Environment variables

| Name | Location | Description |
| --- | --- | --- |
| `ARGOCD_AUTH_TOKEN` | Kubernetes and Helm deployments | Argo CD token read from `backstage-secrets` |
| `ARGOCD_ADMIN_PASSWORD` | Local patched configuration | Argo CD password substitution |
| `GITHUB_TOKEN` | Base Backstage configuration | Optional GitHub integration token |
| `POSTGRES_HOST` | Production Backstage configuration | PostgreSQL server |
| `POSTGRES_PORT` | Production Backstage configuration | PostgreSQL port |
| `POSTGRES_USER` | Production Backstage configuration | PostgreSQL user |
| `POSTGRES_PASSWORD` | Production Backstage configuration | PostgreSQL password |
| `PORT` | Mock server | HTTP port; default `4010` |

### Main configuration files

| File | Responsibility |
| --- | --- |
| `kind-config.yaml` | KIND topology and host-port mappings |
| `k8s/deployment.yaml` | Raw Backstage workload |
| `k8s/rbac.yaml` | Read-only cluster access |
| `k8s/mock-server/` | Mock-server workload and service |
| `helm/backstage/values.yaml` | Helm defaults and application configuration |
| `my-developer-portal/app-config.yaml` | Development Backstage defaults |
| `my-developer-portal/app-config.production.yaml` | Production-mode database configuration |
| `backstage-patches/app-config.local.yaml` | PoC integration configuration |

### Closed-network preparation

The default setup makes external requests and is not air-gap ready as committed:

- Argo CD installation reads a stable manifest from `raw.githubusercontent.com`.
- The Argo CD applications read three paths from `argoproj/argocd-example-apps` and track `HEAD`.
- Dependency installation and scaffolding require JavaScript package registries.
- Container builds may require external base images.

Before use on an on-premises closed network, mirror these artifacts internally, pin immutable versions, update all source URLs, and verify the required package and image caches.

## Development

Run Backstage commands from `backstage-kind-poc/my-developer-portal`.

| Command | Description |
| --- | --- |
| `yarn start` | Start the development workspace |
| `yarn build:backend` | Build the backend package |
| `yarn build:all` | Build all packages |
| `yarn build-image` | Build the backend image |
| `yarn tsc` | Run incremental TypeScript checks |
| `yarn tsc:full` | Run full TypeScript checks |
| `yarn test` | Test changes since the default branch |
| `yarn test:all` | Run the full test suite with coverage |
| `yarn test:e2e` | Run Playwright tests |
| `yarn lint` | Lint changed files |
| `yarn lint:all` | Lint the entire workspace |
| `yarn prettier:check` | Check formatting |
| `yarn fix` | Apply supported formatting and lint fixes |
| `yarn clean` | Clean workspace output and caches |

Run the mock server from `backstage-kind-poc/mock-server`:

```bash
npm start
```

Its own package manifest accepts Node.js 18 or newer.

## Deployment

### Raw manifests

The setup scripts apply resources from `k8s/` after building and loading `backstage:latest` and `mock-server:latest` into KIND.

### Helm

The Helm helper requires a running KIND cluster and a local `backstage:latest` image:

```powershell
cd backstage-kind-poc
./deploy-backstage.ps1
```

It saves the image to `backstage-v2.tar`, imports it into the `kind-control-plane` container, removes the raw-manifest Backstage resources, and runs:

```text
helm upgrade --install backstage helm/backstage --namespace backstage --create-namespace --wait --timeout 5m --atomic
```

## Validation

Inspect the cluster without modifying it:

```bash
kubectl config current-context
kubectl get nodes
kubectl get pods,services -n backstage
kubectl get applications -n argocd
kubectl logs -n backstage deployment/backstage --tail=100
kubectl logs -n backstage deployment/mock-server --tail=100
```

Health probes expect:

| Workload | Path | Port |
| --- | --- | --- |
| Backstage | `/healthcheck` | 7007 |
| Mock server | `/health` | 4010 |

## Troubleshooting

### `ImagePullBackOff` or missing image

The manifests set `imagePullPolicy: Never`. Load both images into the named cluster:

```bash
kind load docker-image backstage:latest --name backstage
kind load docker-image mock-server:latest --name backstage
```

### Integration panels have no data

Confirm that the mock-server pod and service are healthy:

```bash
kubectl get pods,services -n backstage
kubectl logs -n backstage deployment/mock-server --tail=100
```

The configured in-cluster endpoint is `mock-server.backstage.svc.cluster.local:4010`.

### Argo CD applications do not synchronize

```bash
kubectl get applications -n argocd
kubectl describe application payment-service -n argocd
```

Check cluster DNS, external or mirrored repository access, and the application source revisions.

### Wrong KIND context

The Bash setup creates `backstage`, whose usual context is `kind-backstage`. The PowerShell setup uses `kind` and `kind-kind` in some checks even though `kind-config.yaml` names the cluster `backstage`. Always inspect `kubectl config current-context` before applying resources.

### Host port conflict

Ports 3000 and 8080 are mapped in `kind-config.yaml`. If either is occupied, update the KIND mapping and the corresponding NodePort and application URL settings together.

## Security and limitations

- Guest access is allowed outside development, and the default Backstage auth policy is disabled.
- Kubernetes TLS certificate verification is skipped by the PoC configuration.
- Mock Jenkins and SonarQube credentials are embedded in configuration.
- The Helm deployment uses an in-memory SQLite database and does not persist application data.
- The Kubernetes role is cluster-scoped, although its verbs are read-only.
- Argo CD is configured to prune and self-heal automatically.
- Setup writes Kubernetes Secrets and cluster-scoped resources to the active context.
- Catalog source and Jenkins URLs use placeholder domains.
- No repository-level license file was found.

Review and replace these choices before adapting the project for a shared, production, OpenShift, or enterprise environment.

## Repository structure

```text
backstage-kind-poc/
|-- argocd-apps/                 Argo CD Application manifests
|-- backstage-patches/           PoC patch sources and configuration
|-- dummy-services/              Catalog source entities
|-- helm/backstage/              Backstage Helm chart
|-- k8s/                         Raw Kubernetes resources
|   `-- mock-server/             Mock workload resources
|-- mock-server/                 Express mock API
|-- my-developer-portal/         Backstage application
|   |-- catalog/                 Runtime catalog copy
|   |-- packages/app/            Frontend package
|   `-- packages/backend/        Backend package
|-- deploy-backstage.ps1         Helm deployment helper
|-- generate-mock-data.sh        Argo/catalog helper
|-- kind-config.yaml             KIND configuration
|-- setup-local-backstage.ps1    Windows setup
`-- setup-local-backstage.sh     Bash setup
```

## Documentation scope

This file documents only behavior supported by committed manifests, package metadata, configuration, scripts, catalog entities, and mock routes. The commands were reviewed for existence but were not executed while this README variant was prepared.
