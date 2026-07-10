# Universal Microservice Helm Chart

This chart turns extracted OpenShift application YAML into a reusable values-driven deployment.

It supports:

- `Deployment` or `StatefulSet`
- `Service`
- OpenShift `Route`
- `Secret`
- `ServiceAccount`
- image pull secrets, environment variables, probes, resources, volumes, node placement, and pod metadata

## Client Values

Give clients only `values-minimal.yaml` when they should edit the smallest safe surface:

```powershell
helm upgrade --install my-app .\helm\universal-microservice -f .\helm\universal-microservice\values-minimal.yaml
```

## Full Values

Use `values.yaml` when converting all fields from extracted OpenShift YAML:

```powershell
helm template my-app .\helm\universal-microservice -f .\helm\universal-microservice\values.yaml
```

## Converting Extracted YAMLs

Map the OpenShift objects into values like this:

- `Deployment.spec.template.spec.containers[0].image` -> `image.repository` and `image.tag`
- `Deployment.spec.replicas` -> `replicaCount`
- `Deployment.spec.template.spec.containers[0].env` -> `env`
- `Deployment.spec.template.spec.containers[0].resources` -> `resources`
- `Service.spec.ports` -> `service.ports`
- `Route.spec.host` -> `route.host`
- `Route.spec.tls` -> `route.tls`
- `Secret.stringData` or decoded `Secret.data` -> `secret.stringData`
- `ServiceAccount.metadata.name` -> `serviceAccount.name`

Keep client-specific secrets outside Git. Use CI/CD secret injection or a private values file.

## Batch Conversion Script

This repo includes a single-file Python converter for OpenShift exports. It uses only the Python standard library:

```powershell
python .\scripts\openshift_to_values.py convert --input-dir .\openshift-yamls --output-dir .\generated-values --chart-dir .\helm\universal-microservice
```

For demo data, generate 30 fake OpenShift microservice exports:

```powershell
python .\scripts\openshift_to_values.py generate --input-dir .\openshift-yamls --count 30
```

To regenerate demo exports and values together:

```powershell
python .\scripts\openshift_to_values.py all --input-dir .\openshift-yamls --output-dir .\generated-values --chart-dir .\helm\universal-microservice --count 30
```

The converter reads each `*.yaml`, finds `Deployment` or `StatefulSet`, `Service`, `Route`, `Secret`, and `ServiceAccount`, then writes one `*-values.yaml` file per microservice.
