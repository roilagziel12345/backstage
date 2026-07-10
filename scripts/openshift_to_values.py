#!/usr/bin/env python3
"""
Generate fake OpenShift exports and convert OpenShift-style YAML files into
values files for helm/universal-microservice.

No external Python packages are required. The converter is intentionally
line-oriented so it can run in locked-down on-prem environments without PyYAML.
"""

import argparse
import base64
import re
from pathlib import Path
from typing import Iterable, List, Optional, Tuple


DOMAINS = [
    "payments",
    "orders",
    "inventory",
    "catalog",
    "shipping",
    "billing",
    "identity",
    "notifications",
    "search",
    "analytics",
]
TIERS = ["backend", "worker", "api"]
OWNERS = ["platform", "commerce", "risk", "client-success", "data"]


def b64(value: str) -> str:
    return base64.b64encode(value.encode("utf-8")).decode("ascii")


def split_docs(raw: str) -> List[str]:
    return [doc.strip("\n") for doc in re.split(r"(?m)^---\s*$", raw) if doc.strip()]


def doc_kind(doc: str) -> str:
    match = re.search(r"(?m)^kind:\s+(.+?)\s*$", doc)
    return match.group(1).strip() if match else ""


def doc_by_kind(docs: Iterable[str], kind: str) -> str:
    for doc in docs:
        if doc_kind(doc) == kind:
            return doc
    return ""


def first_match(text: str, pattern: str, default: str = "") -> str:
    match = re.search(pattern, text, re.MULTILINE)
    return match.group(1).strip().strip('"') if match else default


def metadata_name(doc: str) -> str:
    lines = doc.splitlines()
    in_metadata = False
    for line in lines:
        if re.match(r"^metadata:\s*$", line):
            in_metadata = True
            continue
        if in_metadata and line and not line.startswith(" "):
            break
        if in_metadata:
            match = re.match(r"^\s{2}name:\s+(.+?)\s*$", line)
            if match:
                return match.group(1).strip().strip('"')
    return ""


def metadata_namespace(doc: str) -> str:
    lines = doc.splitlines()
    in_metadata = False
    for line in lines:
        if re.match(r"^metadata:\s*$", line):
            in_metadata = True
            continue
        if in_metadata and line and not line.startswith(" "):
            break
        if in_metadata:
            match = re.match(r"^\s{2}namespace:\s+(.+?)\s*$", line)
            if match:
                return match.group(1).strip().strip('"')
    return ""


def get_block(text: str, start_pattern: str, stop_patterns: Iterable[str]) -> List[str]:
    lines = text.splitlines()
    start = -1
    for index, line in enumerate(lines):
        if re.match(start_pattern, line):
            start = index + 1
            break
    if start < 0:
        return []

    block: List[str] = []
    for line in lines[start:]:
        if any(re.match(pattern, line) for pattern in stop_patterns):
            break
        if line.strip():
            block.append(line.rstrip())
    return block


def normalize_block(lines: List[str], indent: int) -> List[str]:
    if not lines:
        return []
    min_indent = min(len(re.match(r"^(\s*)", line).group(1)) for line in lines if line.strip())
    prefix = " " * indent
    return [prefix + line[min_indent:] if len(line) >= min_indent else prefix + line.strip() for line in lines]


def write_block(out: List[str], key: str, lines: List[str], empty: str, indent: int = 2) -> None:
    out.append(f"{key}:")
    if lines:
        out.extend(lines)
    else:
        out.append(" " * indent + empty)


def image_repo_tag(image: str) -> Tuple[str, str]:
    image = image.strip().strip('"').strip("'")
    match = re.match(r"^(.*):([^/:]+)$", image)
    if match:
        return match.group(1), match.group(2)
    return image, "latest"


def bool_yaml(value: bool) -> str:
    return "true" if value else "false"


def generate_fake_openshift_yamls(output_dir: Path, count: int = 30) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    for i in range(1, count + 1):
        num = f"{i:02d}"
        domain = DOMAINS[(i - 1) % len(DOMAINS)]
        tier = TIERS[(i - 1) % len(TIERS)]
        owner = OWNERS[(i - 1) % len(OWNERS)]
        name = f"{domain}-{tier}-{num}"
        namespace = f"client-{(((i - 1) % 6) + 1):02d}"
        replicas = ((i - 1) % 4) + 1
        port = 8080 + ((i - 1) % 5)
        timestamp = f"2026-07-10T{((i + 7) % 24):02d}:{((i * 7) % 60):02d}:00Z"
        kind = "StatefulSet" if i % 10 == 0 else "Deployment"
        cpu_request = [50, 75, 100, 150, 200][(i - 1) % 5]
        cpu_limit = [250, 500, 750, 1000][(i - 1) % 4]
        memory_request = [128, 192, 256, 384, 512][(i - 1) % 5]
        memory_limit = [512, 768, 1024, 1536][(i - 1) % 4]

        if kind == "Deployment":
            workload_specific = """  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 0"""
        else:
            workload_specific = f"""  serviceName: {name}
  podManagementPolicy: OrderedReady
  updateStrategy:
    type: RollingUpdate"""

        content = f"""apiVersion: v1
kind: ServiceAccount
metadata:
  name: {name}
  namespace: {namespace}
  labels:
    app.kubernetes.io/name: {name}
    app.kubernetes.io/component: {tier}
    app.kubernetes.io/part-of: demo-platform
    app.openshift.io/runtime: quarkus
    owner: {owner}
  annotations:
    openshift.io/generated-by: fake-exporter
    exportedAt: "{timestamp}"
automountServiceAccountToken: true
---
apiVersion: v1
kind: Secret
metadata:
  name: {name}-secret
  namespace: {namespace}
  labels:
    app.kubernetes.io/name: {name}
    app.kubernetes.io/component: {tier}
    owner: {owner}
  annotations:
    exportedAt: "{timestamp}"
type: Opaque
data:
  API_TOKEN: {b64("token-" + name)}
  DB_PASSWORD: {b64("password-" + num)}
stringData:
  CLIENT_ID: "{name}-client"
  FEATURE_KEY: "{domain}-feature-{num}"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {name}-config
  namespace: {namespace}
  labels:
    app.kubernetes.io/name: {name}
    owner: {owner}
  annotations:
    exportedAt: "{timestamp}"
data:
  LOG_LEVEL: info
  REGION: eu-west-1
  CLIENT_TIER: gold
  FEATURE_FLAGS: audit,metrics,retry
---
apiVersion: v1
kind: Service
metadata:
  name: {name}
  namespace: {namespace}
  labels:
    app.kubernetes.io/name: {name}
    app.kubernetes.io/component: {tier}
    app.kubernetes.io/instance: {name}
    owner: {owner}
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "{port}"
    exportedAt: "{timestamp}"
spec:
  type: ClusterIP
  sessionAffinity: None
  selector:
    app.kubernetes.io/name: {name}
    app.kubernetes.io/instance: {name}
  ports:
    - name: http
      protocol: TCP
      port: {port}
      targetPort: http
    - name: metrics
      protocol: TCP
      port: 9090
      targetPort: metrics
---
apiVersion: apps/v1
kind: {kind}
metadata:
  name: {name}
  namespace: {namespace}
  labels:
    app.kubernetes.io/name: {name}
    app.kubernetes.io/component: {tier}
    app.kubernetes.io/instance: {name}
    app.kubernetes.io/version: "1.{i}.0"
    app.openshift.io/runtime: quarkus
    owner: {owner}
  annotations:
    app.openshift.io/connects-to: {name}-db
    deployment.kubernetes.io/revision: "{i}"
    exportedAt: "{timestamp}"
spec:
  replicas: {replicas}
{workload_specific}
  selector:
    matchLabels:
      app.kubernetes.io/name: {name}
      app.kubernetes.io/instance: {name}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {name}
        app.kubernetes.io/component: {tier}
        app.kubernetes.io/instance: {name}
        sidecar.istio.io/inject: "true"
        owner: {owner}
      annotations:
        checksum/config: "{num}-{domain}-config"
        exportedAt: "{timestamp}"
    spec:
      serviceAccountName: {name}
      automountServiceAccountToken: true
      imagePullSecrets:
        - name: registry-pull-secret
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      initContainers:
        - name: wait-for-db
          image: registry.access.redhat.com/ubi9/ubi-minimal:latest
          command: ["sh", "-c", "echo waiting-for-db"]
      containers:
        - name: {name}
          image: image-registry.openshift-image-registry.svc:5000/{namespace}/{name}:1.{i}.0
          imagePullPolicy: IfNotPresent
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
          ports:
            - name: http
              containerPort: {port}
              protocol: TCP
            - name: metrics
              containerPort: 9090
              protocol: TCP
          env:
            - name: APP_NAME
              value: "{name}"
            - name: APP_NAMESPACE
              value: "{namespace}"
            - name: LOG_LEVEL
              valueFrom:
                configMapKeyRef:
                  name: {name}-config
                  key: LOG_LEVEL
            - name: API_TOKEN
              valueFrom:
                secretKeyRef:
                  name: {name}-secret
                  key: API_TOKEN
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {name}-secret
                  key: DB_PASSWORD
          envFrom:
            - configMapRef:
                name: {name}-config
            - secretRef:
                name: {name}-secret
          resources:
            requests:
              cpu: {cpu_request}m
              memory: {memory_request}Mi
            limits:
              cpu: {cpu_limit}m
              memory: {memory_limit}Mi
          lifecycle:
            preStop:
              exec:
                command: ["sh", "-c", "sleep 5"]
          livenessProbe:
            httpGet:
              path: /health/live
              port: http
            initialDelaySeconds: 20
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health/ready
              port: http
            initialDelaySeconds: 10
            periodSeconds: 5
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            - name: app-config
              mountPath: /etc/app
              readOnly: true
        - name: log-sidecar
          image: registry.access.redhat.com/ubi9/ubi-minimal:latest
          command: ["sh", "-c", "tail -f /dev/null"]
      volumes:
        - name: tmp
          emptyDir: {{}}
        - name: app-config
          configMap:
            name: {name}-config
      nodeSelector:
        kubernetes.io/os: linux
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: {name}
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: {name}
  namespace: {namespace}
  labels:
    app.kubernetes.io/name: {name}
    app.kubernetes.io/component: {tier}
    owner: {owner}
  annotations:
    haproxy.router.openshift.io/timeout: 60s
    exportedAt: "{timestamp}"
spec:
  host: {name}.apps.demo-openshift.example.com
  path: /
  to:
    kind: Service
    name: {name}
    weight: 100
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
"""
        (output_dir / f"{name}.yaml").write_text(content, encoding="utf-8", newline="\n")


def convert_file(path: Path, output_dir: Path) -> Optional[Path]:
    raw = path.read_text(encoding="utf-8")
    docs = split_docs(raw)
    workload = doc_by_kind(docs, "Deployment")
    workload_type = "Deployment"
    if not workload:
        workload = doc_by_kind(docs, "StatefulSet")
        workload_type = "StatefulSet"
    if not workload:
        print(f"skip {path.name}: no Deployment or StatefulSet")
        return None

    service = doc_by_kind(docs, "Service")
    route = doc_by_kind(docs, "Route")
    secret = doc_by_kind(docs, "Secret")
    configmap = doc_by_kind(docs, "ConfigMap")
    service_account = doc_by_kind(docs, "ServiceAccount")

    name = metadata_name(workload)
    namespace = metadata_namespace(workload)
    replicas = first_match(workload, r"(?m)^\s{2}replicas:\s+(.+)$", "1")
    image = first_match(workload, r"(?m)^\s+image:\s+(.+)$")
    repo, tag = image_repo_tag(image)
    pull_policy = first_match(workload, r"(?m)^\s+imagePullPolicy:\s+(.+)$", "IfNotPresent")
    sa_name = metadata_name(service_account) if service_account else first_match(workload, r"(?m)^\s+serviceAccountName:\s+(.+)$", "")
    service_type = first_match(service, r"(?m)^\s{2}type:\s+(.+)$", "ClusterIP") if service else "ClusterIP"
    session_affinity = first_match(service, r"(?m)^\s{2}sessionAffinity:\s+(.+)$", "") if service else ""
    route_host = first_match(route, r"(?m)^\s{2}host:\s+(.+)$", "") if route else ""
    route_path = first_match(route, r"(?m)^\s{2}path:\s+(.+)$", "") if route else ""
    route_target_port = first_match(route, r"(?m)^\s{4}targetPort:\s+(.+)$", "http") if route else "http"
    route_wildcard = first_match(route, r"(?m)^\s{2}wildcardPolicy:\s+(.+)$", "None") if route else "None"

    container_ports = normalize_block(get_block(workload, r"^\s{10}ports:\s*$", [r"^\s{10}env:\s*$"]), 2)
    env = normalize_block(get_block(workload, r"^\s{10}env:\s*$", [r"^\s{10}envFrom:\s*$", r"^\s{10}resources:\s*$"]), 2)
    env_from = normalize_block(get_block(workload, r"^\s{10}envFrom:\s*$", [r"^\s{10}resources:\s*$"]), 2)
    resources = normalize_block(get_block(workload, r"^\s{10}resources:\s*$", [r"^\s{10}lifecycle:\s*$", r"^\s{10}livenessProbe:\s*$"]), 2)
    lifecycle = normalize_block(get_block(workload, r"^\s{10}lifecycle:\s*$", [r"^\s{10}livenessProbe:\s*$"]), 2)
    liveness = normalize_block(get_block(workload, r"^\s{10}livenessProbe:\s*$", [r"^\s{10}readinessProbe:\s*$"]), 2)
    readiness = normalize_block(get_block(workload, r"^\s{10}readinessProbe:\s*$", [r"^\s{10}startupProbe:\s*$", r"^\s{10}volumeMounts:\s*$"]), 2)
    volume_mounts = normalize_block(get_block(workload, r"^\s{10}volumeMounts:\s*$", [r"^\s{8}-\s+name:", r"^\s{6}volumes:\s*$"]), 2)
    volumes = normalize_block(get_block(workload, r"^\s{6}volumes:\s*$", [r"^\s{6}nodeSelector:\s*$", r"^\s{6}affinity:\s*$", r"^\s{6}tolerations:\s*$", r"^\s{6}topologySpreadConstraints:\s*$"]), 2)
    init_containers = normalize_block(get_block(workload, r"^\s{6}initContainers:\s*$", [r"^\s{6}containers:\s*$"]), 2)
    topology = normalize_block(get_block(workload, r"^\s{6}topologySpreadConstraints:\s*$", [r"^\s{6}[A-Za-z].*:\s*$", r"^---$"]), 2)
    service_ports = normalize_block(get_block(service, r"^\s{2}ports:\s*$", [r"^---$"]), 4) if service else []
    tls = normalize_block(get_block(route, r"^\s{2}tls:\s*$", [r"^\s{2}wildcardPolicy:"]), 4) if route else []
    secret_string_data = normalize_block(get_block(secret, r"^stringData:\s*$", [r"^data:\s*$", r"^---$"]), 4) if secret else []
    secret_data = normalize_block(get_block(secret, r"^data:\s*$", [r"^stringData:\s*$", r"^---$"]), 4) if secret else []
    config_data = normalize_block(get_block(configmap, r"^data:\s*$", [r"^binaryData:\s*$", r"^---$"]), 4) if configmap else []

    out: List[str] = [
        f"nameOverride: {name}",
        f'namespaceOverride: "{namespace}"' if namespace else 'namespaceOverride: ""',
        "",
        f"replicaCount: {replicas}",
        "",
        "workload:",
        f"  type: {workload_type}",
        "  annotations: {}",
        "  labels: {}",
        "",
        "image:",
        f"  repository: {repo}",
        f"  tag: {tag}",
        f"  pullPolicy: {pull_policy}",
        "",
        "imagePullSecrets:",
        "  - name: registry-pull-secret",
        "",
        "serviceAccount:",
        "  create: true",
        f"  name: {sa_name}",
        "  annotations: {}",
        "  labels: {}",
        "",
        "service:",
        "  enabled: true",
        f"  type: {service_type}",
        "  annotations: {}",
        "  labels: {}",
    ]
    if session_affinity:
        out.append(f"  sessionAffinity: {session_affinity}")
    out.append("  ports:")
    out.extend(service_ports or ["    - name: http", "      port: 8080", "      targetPort: http", "      protocol: TCP"])
    out.extend([
        "",
        "route:",
        f"  enabled: {bool_yaml(bool(route))}",
        "  annotations: {}",
        "  labels: {}",
        f'  host: "{route_host}"',
        f'  path: "{route_path}"',
        f"  wildcardPolicy: {route_wildcard}",
        "  port:",
        f"    targetPort: {route_target_port}",
    ])
    if tls:
        out.append("  tls:")
        out.extend(tls)
    else:
        out.append("  tls: {}")

    out.extend(["", "configMap:", f"  enabled: {bool_yaml(bool(configmap))}", f"  name: {metadata_name(configmap) if configmap else ''}", "  annotations: {}", "  labels: {}", "  data:"])
    out.extend(config_data or ["    {}"])
    out.extend(["", "containerPorts:"])
    out.extend(container_ports or ["  - name: http", "    containerPort: 8080", "    protocol: TCP"])
    write_block(out, "initContainers", init_containers, "[]")
    write_block(out, "env", env, "[]")
    write_block(out, "envFrom", env_from, "[]")
    write_block(out, "resources", resources, "{}")
    write_block(out, "lifecycle", lifecycle, "{}")
    write_block(out, "livenessProbe", liveness, "{}")
    write_block(out, "readinessProbe", readiness, "{}")
    write_block(out, "volumeMounts", volume_mounts, "[]")
    write_block(out, "volumes", volumes, "[]")
    write_block(out, "topologySpreadConstraints", topology, "[]")
    out.extend(["", "secret:", f"  enabled: {bool_yaml(bool(secret))}", f"  name: {metadata_name(secret) if secret else name + '-secret'}", "  type: Opaque", "  stringData:"])
    out.extend(secret_string_data or ["    {}"])
    out.append("  data:")
    out.extend(secret_data or ["    {}"])

    if workload_type == "StatefulSet":
        out.extend(["", "statefulSet:", f"  serviceName: {name}", "  podManagementPolicy: OrderedReady", "  updateStrategy:", "    type: RollingUpdate"])

    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"{name}-values.yaml"
    output_path.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
    return output_path


def convert_openshift_yamls(input_dir: Path, output_dir: Path) -> int:
    output_dir.mkdir(parents=True, exist_ok=True)
    count = 0
    for path in sorted(input_dir.glob("*.yaml")):
        if convert_file(path, output_dir):
            count += 1
    return count


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate and convert OpenShift YAMLs to Helm values.")
    parser.add_argument("command", choices=["generate", "convert", "all"], nargs="?", default="all")
    parser.add_argument("--input-dir", default="openshift-yamls")
    parser.add_argument("--output-dir", default="generated-values")
    parser.add_argument("--chart-dir", default="helm/universal-microservice")
    parser.add_argument("--count", type=int, default=30)
    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    chart_dir = Path(args.chart_dir)

    if args.command in {"convert", "all"} and not (chart_dir / "values.yaml").exists():
        raise SystemExit(f"chart values.yaml not found under {chart_dir}")

    if args.command in {"generate", "all"}:
        generate_fake_openshift_yamls(input_dir, args.count)
        print(f"Created {args.count} fake OpenShift microservice YAML files in {input_dir}")

    if args.command in {"convert", "all"}:
        count = convert_openshift_yamls(input_dir, output_dir)
        print(f"Converted {count} OpenShift YAML files into Helm values under {output_dir}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
