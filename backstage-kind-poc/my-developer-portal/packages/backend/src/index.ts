import { createBackend } from '@backstage/backend-defaults';

const backend = createBackend();

// ── Core infrastructure ──────────────────────────────────────────────────────
backend.add(import('@backstage/plugin-app-backend'));           // no /alpha
backend.add(import('@backstage/plugin-proxy-backend'));          // no /alpha
backend.add(import('@backstage/plugin-scaffolder-backend/alpha'));
backend.add(import('@backstage/plugin-techdocs-backend/alpha'));

// ── Catalog ──────────────────────────────────────────────────────────────────
backend.add(import('@backstage/plugin-catalog-backend/alpha'));
backend.add(import('@backstage/plugin-catalog-backend-module-scaffolder-entity-model'));

// ── Auth ─────────────────────────────────────────────────────────────────────
backend.add(import('@backstage/plugin-auth-backend'));
backend.add(import('@backstage/plugin-auth-backend-module-guest-provider'));

// ── Search ───────────────────────────────────────────────────────────────────
backend.add(import('@backstage/plugin-search-backend/alpha'));
backend.add(import('@backstage/plugin-search-backend-module-catalog'));  // no /alpha
backend.add(import('@backstage/plugin-search-backend-module-techdocs/alpha'));

// ── Jenkins ──────────────────────────────────────────────────────────────────
backend.add(import('@backstage-community/plugin-jenkins-backend'));

// ── SonarQube ────────────────────────────────────────────────────────────────
backend.add(import('@backstage-community/plugin-sonarqube-backend'));

// ── Kubernetes ───────────────────────────────────────────────────────────────
backend.add(import('@backstage/plugin-kubernetes-backend'));    // no /alpha

// ── Notifications + Signals ──────────────────────────────────────────────────
backend.add(import('@backstage/plugin-notifications-backend'));
backend.add(import('@backstage/plugin-signals-backend'));

// ── Permissions ──────────────────────────────────────────────────────────────
backend.add(import('@backstage/plugin-permission-backend/alpha'));
backend.add(
  import('@backstage/plugin-permission-backend-module-allow-all-policy'),
);

backend.start();
