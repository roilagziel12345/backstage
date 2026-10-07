# See Your Delivery Platform in One Place

This proof of concept is designed to turn a local KIND cluster into a Backstage developer portal. Three catalog services define a shared identity for Kubernetes state, Argo CD delivery, Jenkins build history, and SonarQube quality signals without requiring real Jenkins or SonarQube servers.

```text
                              DEVELOPER PORTAL

  Catalog             Delivery             Runtime              Quality
  payment-service     Argo CD              Kubernetes           SonarQube
  order-service       automated sync       KIND                 Jenkins
  inventory-service   self-healing         read-only view       mock data

                         http://localhost:3000
```

Built for local demonstration and learning. It is not hardened for production.

## The experience

Start one local environment, sign in as a guest, and browse three production-style catalog components:

| Service | Team | Delivery example | Quality data |
| --- | --- | --- | --- |
| Payment | `platform-team` | Argo CD guestbook | Jenkins history and 87.5% mock coverage |
| Order | `backend-team` | Argo CD Helm guestbook | Jenkins history and 74.3% mock coverage |
| Inventory | `inventory-team` | Argo CD Kustomize guestbook | Jenkins history and 91.2% mock coverage |

The build histories and quality measures are fixtures served by the included mock server. They are for UI demonstration, not measurements of code in this repository.

Current wiring note: the committed frontend registers the catalog and navigation features. The integration dependencies are installed and a richer `EntityPage.tsx` is provided under `backstage-patches/`, but that patch is not present in the committed app source tree. The integration cards remain an intended experience until that frontend wiring is applied and verified.

## How it fits together

```text
Your browser
     |
     |  localhost:3000
     v
+-------------------------------------------------------------------+
| KIND: backstage                                                   |
|                                                                   |
|  +-----------------------+       +-----------------------------+  |
|  | Backstage             |------>| Mock integration server     |  |
|  |                       |       |                             |  |
|  | Software Catalog      |       | Jenkins-compatible routes   |  |
|  | Catalog + navigation  |       | SonarQube-compatible routes |  |
|  | Integration backends  |       | Health endpoint             |  |
|  +-----------+-----------+       +-----------------------------+  |
|              |                                                    |
|       +------+----------------------+                             |
|       | Kubernetes API             | Argo CD API                 |
|       | read-only ServiceAccount   | token from Secret           |
|       +-----------------------------+                             |
|                                                                   |
|  Backstage :7007 -> NodePort 30000 -> host 3000                  |
|  Argo CD                    NodePort 30001 -> host 8080           |
+-------------------------------------------------------------------+
```

## Start here

You need Docker, KIND, kubectl, Node.js 22 or 24, Yarn 4.4.1, and either PowerShell 7 or Bash. Helm is also required for the separate Helm deployment helper.

The setup scripts mention Node 20 in comments, but `my-developer-portal/package.json` requires Node 22 or 24. Follow the package manifest.

### Windows

```powershell
cd backstage-kind-poc
./setup-local-backstage.ps1
```

### Bash

```bash
cd backstage-kind-poc
bash setup-local-backstage.sh
```

When setup completes:

- Open Backstage at `http://localhost:3000`.
- Open Argo CD at `http://localhost:8080`.
- Use guest sign-in for the portal.

Already have the cluster or application prepared?

```powershell
./setup-local-backstage.ps1 -SkipCluster -SkipScaffold
```

```bash
bash setup-local-backstage.sh --skip-cluster --skip-scaffold
```

## What gets created

```text
Local machine
|-- backstage:latest image
|-- mock-server:latest image
`-- KIND cluster: backstage
    |-- namespace: backstage
    |   |-- Backstage workload and NodePort service
    |   |-- mock-server workload and ClusterIP service
    |   |-- read-only ServiceAccount and Argo CD Secret
    |   `-- three software catalog entities
    `-- namespace: argocd
        |-- Argo CD installation
        `-- three automated Application resources
```

The application code is already committed under `backstage-kind-poc/my-developer-portal`, so a normal setup detects it instead of scaffolding another app.

## Feature tour

### A catalog that connects the tools

Each component carries annotations for the same service name across Jenkins, SonarQube, Argo CD, and Kubernetes. The catalog definitions live in `my-developer-portal/catalog`; a second source copy lives in `dummy-services`.

### Real plugins, controlled demo data

The Backstage backend loads Jenkins, SonarQube, and Kubernetes integrations; the app package declares frontend dependencies for those integrations and Argo CD. The committed `App.tsx` currently enables only the catalog and navigation features. The Express mock server supplies deterministic Jenkins and SonarQube responses on port 4010 for completing and testing the intended UI wiring.

### Two deployment paths

The main setup uses raw manifests from `k8s/`. A separate Helm chart under `helm/backstage/` packages the Backstage workload and configuration.

```powershell
cd backstage-kind-poc
./deploy-backstage.ps1
```

That helper expects the KIND cluster and local `backstage:latest` image to exist. It imports the image, removes the previous raw-manifest Backstage resources, and performs an atomic Helm release installation.

## Project map

```text
backstage-kind-poc/
|
|-- my-developer-portal/     Backstage Yarn workspace
|   |-- packages/app/        Browser application
|   |-- packages/backend/    Backend and plugin wiring
|   `-- catalog/             Three service entities
|
|-- mock-server/             Jenkins and SonarQube simulator
|-- argocd-apps/             Three Argo CD applications
|-- k8s/                     Raw Kubernetes deployment path
|-- helm/backstage/          Helm deployment path
|-- backstage-patches/       PoC configuration and source patches
|-- dummy-services/          Catalog source files
|-- kind-config.yaml         Cluster and host-port mapping
|-- setup-local-backstage.ps1
|-- setup-local-backstage.sh
`-- deploy-backstage.ps1
```

## Everyday commands

From `backstage-kind-poc/my-developer-portal`:

| Goal | Command |
| --- | --- |
| Start development | `yarn start` |
| Build everything | `yarn build:all` |
| Build the backend | `yarn build:backend` |
| Build its image | `yarn build-image` |
| Type-check | `yarn tsc:full` |
| Run all tests | `yarn test:all` |
| Run browser tests | `yarn test:e2e` |
| Lint everything | `yarn lint:all` |
| Check formatting | `yarn prettier:check` |

From `backstage-kind-poc/mock-server`, use `npm start` for the mock server. Its package manifest requires Node 18 or newer, and `PORT` can override the default port 4010.

## Configuration at a glance

| Setting | Default in this PoC |
| --- | --- |
| Backstage image | `backstage:latest`, never pulled |
| Mock image | `mock-server:latest`, never pulled |
| Backstage replicas | 1 |
| Backstage resources | 250m/512Mi requested; 1000m/1Gi limited |
| Database in Helm path | In-memory SQLite |
| Portal authentication | Guest enabled outside development |
| Kubernetes authentication | Mounted ServiceAccount token |
| Kubernetes TLS check | Skipped |
| TechDocs | Local builder and publisher |
| Argo CD policy | Automated sync, prune, and self-heal |

`ARGOCD_AUTH_TOKEN` connects the portal to Argo CD. Other committed configurations also recognize `ARGOCD_ADMIN_PASSWORD`, `GITHUB_TOKEN`, and PostgreSQL connection variables. The mock server recognizes `PORT`.

## Before you run it on a closed network

The repository is local-first but not currently air-gap ready.

```text
External dependency                 Required action for an air gap
----------------------------------  -----------------------------------------
Argo CD install URL                 Mirror and pin the install manifest
argocd-example-apps on GitHub       Mirror and pin all three application paths
Node/Yarn package registries        Pre-populate an approved internal mirror
Container base images               Mirror into an internal registry or cache
Backstage scaffolder latest tag     Avoid it; use the committed application
```

The Argo CD application manifests track `HEAD`, so an online run is not reproducible unless you replace it with an approved revision.

## Verify the result

```bash
kubectl get nodes
kubectl get pods,services -n backstage
kubectl get applications -n argocd
kubectl logs -n backstage deployment/backstage --tail=100
kubectl logs -n backstage deployment/mock-server --tail=100
```

Health checks used by the manifests:

- Backstage: `/healthcheck` on port 7007.
- Mock server: `/health` on port 4010.

If an image is missing from KIND, load it explicitly:

```bash
kind load docker-image backstage:latest --name backstage
kind load docker-image mock-server:latest --name backstage
```

## Read this before adapting it

- Guest authentication and the disabled default auth policy make this configuration unsuitable for exposure beyond a trusted demo environment.
- Kubernetes TLS verification is disabled.
- The chart contains obvious mock API tokens and uses ephemeral in-memory storage.
- Setup changes the current Kubernetes cluster, creates cluster-scoped RBAC, and installs automated Argo CD resources. Confirm the current context first.
- The PowerShell setup refers to `kind-kind` in some operations, while the Bash path consistently creates the cluster named `backstage`. Validate the active context before relying on either flow.
- The catalog's example GitHub and Jenkins links are placeholders.
- No repository-level license file is present.

## Design note

This README uses only portable Markdown, tables, fenced text diagrams, and repository-relative paths. It intentionally has no badges, remote images, HTML, Mermaid, or emoji so it remains readable on Bitbucket Server and inside a closed network.
