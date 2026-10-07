# Backstage KIND Platform Architecture

This repository is a local developer-portal proof of concept. It combines a Backstage application, a KIND cluster, Argo CD application definitions, Kubernetes visibility, and a mock server that emulates selected Jenkins and SonarQube APIs.

This document describes the architecture evidenced by the committed repository. It separates the current implementation from the intended integration experience and does not claim that the deployment was executed or verified.

## At a glance

```text
Purpose        Demonstrate a local Backstage-based developer portal
Primary user   Developer or platform engineer evaluating portal concepts
Runtime        Backstage and mock server inside a local KIND cluster
Catalog        payment-service, order-service, inventory-service
Delivery       Three Argo CD Application resources
CI/quality     Static Jenkins and SonarQube-compatible mock responses
Packaging      Raw Kubernetes manifests plus a Backstage Helm chart
```

## Current state versus intended state

| Capability | Current repository evidence | Status |
| --- | --- | --- |
| Backstage catalog | `packages/app/src/App.tsx` enables `catalogPlugin`; three catalog entities are committed | Wired |
| Jenkins backend | Backend imports `@backstage-community/plugin-jenkins-backend` | Wired |
| SonarQube backend | Backend imports `@backstage-community/plugin-sonarqube-backend` | Wired |
| Kubernetes backend | Backend imports `@backstage/plugin-kubernetes-backend` | Wired |
| Argo CD frontend package | Declared in `packages/app/package.json` | Installed, not visibly enabled in committed `App.tsx` |
| Integration entity pages | Implemented in `backstage-patches/EntityPage.tsx` | Patch exists, but is not present in the committed app source tree |
| Mock Jenkins/SonarQube APIs | Express routes are mounted by `mock-server/server.js` | Implemented |
| Argo CD applications | Three `Application` manifests reference public example repositories | Declared; runtime state not verified |
| Helm deployment | Chart and PowerShell deployment helper are committed | Declared; runtime state not verified |

The setup scripts skip scaffolding whenever `my-developer-portal/` already exists. In that normal path they synchronize the catalog but do not copy `backstage-patches/EntityPage.tsx` into the committed frontend. Therefore the repository contains both the integration-page design and a simpler committed frontend. Treat plugin presentation in the UI as an open integration task until it is verified in a running build.

## System context

```text
                                      Public network during setup
                                      +--------------------------+
                                      | Argo CD install manifest |
                                      | Example application repos|
                                      | Package/image registries |
                                      +------------+-------------+
                                                   |
                                                   v
+-------------------+                    +---------------------------+
| Developer         |                    | Local workstation         |
|                   |                    |                           |
| - opens portal    |  localhost:3000    | Docker + KIND + kubectl   |
| - inspects catalog+------------------->| PowerShell or Bash setup  |
| - views Argo UI   |  localhost:8080    |                           |
+-------------------+                    +-------------+-------------+
                                                    |
                                                    v
                                      +---------------------------+
                                      | KIND Kubernetes cluster   |
                                      |                           |
                                      | Backstage                 |
                                      | Mock integration server   |
                                      | Argo CD                   |
                                      +---------------------------+
```

For a closed network, the public-network box must be replaced with pinned internal mirrors before setup is run.

## Runtime containers and interfaces

```text
KIND cluster
|
|-- namespace: backstage
|   |
|   |-- Deployment/backstage
|   |   |-- image: backstage:latest
|   |   |-- container port: 7007
|   |   |-- health: GET /healthcheck
|   |   `-- ServiceAccount: backstage
|   |
|   |-- Service/backstage
|   |   `-- 7007 -> NodePort 30000 -> host 3000
|   |
|   |-- Deployment/mock-server
|   |   |-- image: mock-server:latest
|   |   |-- container port: 4010
|   |   `-- health: GET /health
|   |
|   `-- Service/mock-server
|       `-- ClusterIP:4010
|
`-- namespace: argocd
    |-- Argo CD workloads
    |-- Service/argocd-server
    |   `-- NodePort 30001 -> host 8080
    `-- Application resources
        |-- payment-service   -> guestbook
        |-- order-service     -> helm-guestbook
        `-- inventory-service -> kustomize-guestbook
```

## Component map

| Component | Responsibility | Implementation | Depends on |
| --- | --- | --- | --- |
| Backstage frontend | Catalog UI and navigation | `my-developer-portal/packages/app/` | Backstage backend APIs |
| Backstage backend | Catalog, auth, proxy, search, TechDocs and plugin backends | `my-developer-portal/packages/backend/src/index.ts` | Application configuration and cluster services |
| Catalog | Defines three example service components | `my-developer-portal/catalog/` | Backstage catalog processor |
| Catalog source copy | Source synchronized into the app by setup | `dummy-services/` | Setup scripts |
| Integration-page patch | Intended Jenkins, Argo CD, SonarQube and Kubernetes entity pages | `backstage-patches/EntityPage.tsx` | Legacy-style catalog entity page wiring |
| Mock server | Emulates Jenkins and SonarQube endpoints | `mock-server/` | Express, static fixtures |
| Argo CD definitions | Reconciles three example workloads | `argocd-apps/` | Argo CD and public GitHub source |
| Raw deployment | Creates Backstage, mock server, service and RBAC resources | `k8s/` | Kubernetes API and locally loaded images |
| Helm deployment | Packages Backstage configuration and workload | `helm/backstage/` | Helm and an existing local image |
| Environment automation | Creates and configures the local platform | `setup-local-backstage.ps1`, `setup-local-backstage.sh` | Docker, KIND, kubectl, network access |

## Backstage application composition

### Frontend: committed state

```text
packages/app/src/index.tsx
          |
          v
packages/app/src/App.tsx
          |
          +-- createApp(...)
          |     |
          |     +-- catalogPlugin
          |     `-- navModule
          |
          `-- frontend package declares additional integration dependencies
                but App.tsx does not explicitly register them
```

### Backend: committed state

```text
packages/backend/src/index.ts
|
|-- Core: app, proxy, scaffolder, TechDocs
|-- Catalog: catalog backend, scaffolder entity model
|-- Auth: auth backend, guest provider
|-- Search: search backend, catalog and TechDocs modules
|-- Integrations: Jenkins backend, SonarQube backend, Kubernetes backend
|-- Events: notifications and signals
`-- Permissions: permission backend with allow-all policy
```

The Argo CD integration is configured through application configuration and a frontend package dependency. No Argo CD backend module is imported by `packages/backend/src/index.ts`.

## Integration data flow

### Jenkins example

```text
Catalog annotation
jenkins.io/job-full-name: payment-service
                 |
                 v
Backstage Jenkins backend / proxy configuration
                 |
                 v
http://mock-server.backstage.svc.cluster.local:4010
                 |
                 v
GET /job/payment-service/api/json
                 |
                 v
Static build fixtures from mock-server/routes/jenkins.js
```

### SonarQube example

```text
Catalog annotation
sonarqube.org/project-key: payment-service
                 |
                 v
Backstage SonarQube backend configuration
                 |
                 v
http://mock-server.backstage.svc.cluster.local:4010/sonarqube
                 |
                 v
GET /api/measures/component?component=payment-service
                 |
                 v
Static metrics from mock-server/routes/sonarqube.js
```

The reported coverage values are fixture data: payment 87.5%, order 74.3%, and inventory 91.2%. They are not measurements of code in this repository.

### Kubernetes example

```text
Catalog annotation
backstage.io/kubernetes-id: payment-service
                 |
                 v
Backstage Kubernetes backend
                 |
                 v
ServiceAccount token mounted in the Backstage pod
                 |
                 v
Kubernetes API
                 |
                 v
ClusterRole backstage-read-only
get / list / watch selected resources
```

The role is cluster-scoped even though its verbs are read-only. The PoC configuration also skips Kubernetes API TLS verification.

## Delivery control flow

```text
setup-local-backstage.*
        |
        +-- installs Argo CD from a remote stable manifest
        |
        +-- applies argocd-apps/*.yaml
        |       |
        |       +-- payment-service   tracks HEAD / guestbook
        |       +-- order-service     tracks HEAD / helm-guestbook
        |       `-- inventory-service tracks HEAD / kustomize-guestbook
        |
        +-- retrieves the initial Argo CD admin secret
        |
        `-- creates backstage/backstage-secrets
                         |
                         `-- key: argocd-token
```

Each application enables automated synchronization, pruning, and self-healing. The applications target namespace `default`, not namespace `backstage`.

## Deployment paths

### Path A: setup scripts and raw manifests

```text
kind-config.yaml
      |
      v
Create cluster and namespaces
      |
      +--> Install Argo CD and apply three Applications
      |
      +--> Build mock-server:latest -> load into KIND -> apply k8s/mock-server
      |
      +--> Synchronize dummy-services into my-developer-portal/catalog
      |
      `--> Build backstage:latest -> load into KIND -> apply k8s deployment/service
```

### Path B: Helm replacement for Backstage

```text
Existing backstage:latest image
      |
      v
deploy-backstage.ps1
      |
      +-- saves backstage-v2.tar
      +-- copies and imports it into kind-control-plane
      +-- removes raw Backstage Deployment, Service and RBAC objects
      `-- helm upgrade --install --atomic
```

Path B packages only Backstage. It does not create the mock server or install Argo CD.

## Catalog model

```text
System: ecommerce
|
|-- Component: payment-service
|   |-- owner: platform-team
|   |-- provides: payment-api
|   `-- depends on: postgres-payments
|
|-- Component: order-service
|   `-- owner: backend-team
|
`-- Component: inventory-service
    `-- owner: inventory-team
```

All three components declare lifecycle `production`, even though they represent demonstration entities and their source URLs use `example-org` placeholders.

## Boundaries and invariants

| Boundary or invariant | Evidence | Consequence |
| --- | --- | --- |
| Backstage images are local | `imagePullPolicy: Never` | The correct image must be loaded into the selected KIND cluster before deployment |
| Catalog integration keys share the component name | Catalog annotations and mock fixture keys | Renaming a component requires coordinated annotation and fixture changes |
| Backstage reads Kubernetes through one ServiceAccount | Deployment and RBAC manifests | RBAC changes affect visibility for every catalog component |
| Raw and Helm deployments own the same Backstage identity | Resource names in both paths | Do not operate both deployment paths independently |
| Helm runtime configuration is generated from chart values | `helm/backstage/templates/configmap.yaml` | Changes to patched local config do not automatically update Helm output |
| Helm database is in memory | Generated Backstage configuration | Runtime data is lost when the process restarts |
| Mock integrations are not authoritative | Static route fixtures | Do not use displayed values for operational decisions |
| Argo CD sources track `HEAD` | `argocd-apps/*.yaml` | Online deployments can change without a repository commit here |

## Failure behavior

| Failure | Expected behavior in committed code | Owner of recovery |
| --- | --- | --- |
| Mock server receives an unknown route | Returns HTTP 404 JSON | Caller or developer |
| Mock server middleware throws | Returns HTTP 500 JSON | Developer |
| Backstage health check fails | Kubernetes eventually marks the pod unready or restarts it | Kubernetes |
| Local image is absent | Pod cannot start because pulling is disabled | Operator loads the image |
| Argo CD cannot reach GitHub | Applications cannot synchronize | Operator provides network access or an internal mirror |
| Setup targets the wrong context | Resources may be applied to the wrong cluster | Operator must check context before setup |
| Frontend integration page is not wired | Catalog can load without displaying the intended plugin cards | Application developer |

## Known contradictions and open questions

1. PowerShell creates and uses a cluster named `kind`, while Bash creates `backstage`; `kind-config.yaml` itself contains the name `backstage`.
2. Setup-script comments request Node 20, while the committed root package requires Node 22 or 24 and the Dockerfile uses Node 22.
3. Integration-page code exists under `backstage-patches/`, but the committed frontend has no `components/catalog/EntityPage.tsx` and its `App.tsx` enables only catalog and navigation features.
4. The raw-manifest deployment reads only `ARGOCD_AUTH_TOKEN`, while the Helm path also mounts a generated application configuration ConfigMap.
5. Catalog entities describe production services and placeholder source repositories; the deployed Argo CD applications point to unrelated public guestbook examples.
6. No repository-level license file is present.

These items should be resolved or explicitly accepted before this PoC becomes a shared platform baseline.

## Change guide

### Add another catalog service

1. Add `dummy-services/<service>/catalog-info.yaml`.
2. Add it to `dummy-services/all-services.yaml`.
3. Mirror or regenerate the runtime catalog under `my-developer-portal/catalog/`.
4. Add matching mock fixture keys if Jenkins or SonarQube demonstration data is required.
5. Add an Argo CD `Application` only if the service should have a deployment example.
6. Verify every annotation uses the same intended identifier.

### Replace Jenkins mock data with a real server

1. Change the Jenkins `baseUrl` in the active Backstage configuration path.
2. Replace the mock username and API key with secret-backed configuration.
3. Remove or update the `/jenkins/api` proxy target if it is no longer required.
4. Verify that catalog `jenkins.io/job-full-name` values exist on the real server.
5. Confirm that the frontend actually registers and renders the Jenkins integration.

### Replace SonarQube mock data

1. Change the SonarQube `baseUrl` and authentication configuration.
2. Move credentials out of chart values and committed configuration.
3. Verify each `sonarqube.org/project-key` against the real server.
4. Confirm frontend feature wiring and access policies.

### Adapt the platform to OpenShift

This repository contains no OpenShift manifests. A proposed adaptation should address:

- Route resources instead of the KIND NodePort mapping;
- SecurityContextConstraints and non-root image compatibility;
- internal image registry and ImageStreams, if used;
- trusted cluster certificates instead of `skipTLSVerify`;
- persistent PostgreSQL instead of in-memory SQLite;
- sealed or externally managed secrets;
- restricted egress and internal mirrors for every external source;
- namespace-scoped access where cluster-wide RBAC is unnecessary.

Do not present those changes as implemented until corresponding repository files exist.

## Local setup

The committed Backstage package requires Node.js 22 or 24 and Yarn 4.4.1. The complete environment also requires Docker, KIND, kubectl, and PowerShell 7 or Bash. Helm is required for the separate Helm path.

PowerShell:

```powershell
cd backstage-kind-poc
./setup-local-backstage.ps1
```

Bash:

```bash
cd backstage-kind-poc
bash setup-local-backstage.sh
```

The setup is not closed-network safe as committed. It retrieves an Argo CD installation manifest, application sources, package dependencies, and container base images from public services.

## Verify without changing the cluster

```bash
kubectl config current-context
kubectl get nodes
kubectl get pods,services -n backstage
kubectl get applications -n argocd
kubectl logs -n backstage deployment/backstage --tail=100
kubectl logs -n backstage deployment/mock-server --tail=100
```

These commands verify runtime state only when an environment already exists. They were not executed while this document was prepared.

## Architecture decision candidates

The repository has no committed ADR set. The following decisions are important enough to record if this PoC evolves:

| Candidate decision | Why it matters |
| --- | --- |
| Choose one cluster identity and setup workflow | Removes the `kind` versus `backstage` operational split |
| Choose the Backstage frontend system and plugin-wiring pattern | Determines how the integration page patch should be maintained |
| Choose raw manifests or Helm as the deployment owner | Prevents configuration and lifecycle drift |
| Choose real integrations or maintained mocks | Defines credentials, availability, and data ownership |
| Choose an on-prem artifact-mirroring strategy | Makes installation repeatable without public network access |
| Choose persistent database and authentication providers | Establishes production state and identity boundaries |

## Repository map

```text
backstage-kind-poc/
|-- argocd-apps/              Argo CD Application definitions
|-- backstage-patches/        Scaffold-time integration and image inputs
|-- dummy-services/           Catalog source copied by setup
|-- helm/backstage/           Helm packaging path
|-- k8s/                      Raw deployment and access-control path
|-- mock-server/              Jenkins/SonarQube-compatible fixture service
|-- my-developer-portal/      Committed Backstage application
|-- deploy-backstage.ps1      Helm replacement workflow
|-- generate-mock-data.sh     Argo/catalog helper
|-- kind-config.yaml          Local cluster port mapping
|-- setup-local-backstage.ps1 PowerShell environment workflow
`-- setup-local-backstage.sh  Bash environment workflow
```

## Documentation rules used here

- Every material claim maps to a committed path, symbol, manifest, or configuration value.
- Current behavior and proposed improvements are labeled separately.
- Diagrams use portable ASCII rather than Mermaid, HTML, remote images, or CDN assets.
- Unknown runtime state remains unknown because repository inspection cannot prove a successful deployment.
- Examples show change locations and dependencies without pretending those changes already exist.
