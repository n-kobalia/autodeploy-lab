# AutoDeploy Lab

A production-grade DevOps pipeline built from scratch — containerizing a Python/Flask service with multi-stage Docker builds, provisioning Kubernetes infrastructure via Terraform IaC, automating CI/CD through GitHub Actions with deployment gates, deploying via GitOps with ArgoCD, implementing full-stack observability using Prometheus, Grafana, and Loki, and integrating a dedicated PostgreSQL database on a separate private VM.

> Live at: http://152.70.5.232

---

## Architecture

```
Internet
    │
    ▼
Nginx (reverse proxy — port 80 → NodePort 30080)
    │
    ▼
Kubernetes Cluster — VM 1 (autodeploy-vm, public subnet)
    ├── Flask App (2 replicas, rolling updates)
    │   └── Init Container (flask db upgrade before app starts)
    ├── ArgoCD (GitOps — watches k8s/ folder in GitHub)
    ├── Prometheus + Grafana + Loki (observability stack)
    └── HorizontalPodAutoscaler (2–5 pods, 70% CPU)
    │
    │ private VCN network (never exposed to internet)
    ▼
PostgreSQL — VM 2 (postgres-vm, private subnet)
    └── Dedicated database server
        └── Only accessible from app VM on port 5432
```

---

## CI/CD + GitOps Flow

```
git push
    │
    ▼
GitHub Actions
    ├── test job      — runs 9 pytest tests (deployment gate)
    ├── build-and-push — builds multi-stage Docker image
    │                    tags with :latest and :<commit-sha>
    └── update-manifest — updates image tag in k8s/deployment.yaml
                          commits back to repo
    │
    ▼
ArgoCD detects manifest change in GitHub
    │
    ▼
ArgoCD syncs cluster to match Git
    │
    ▼
Kubernetes rolling update (zero downtime)
    ├── Init container runs flask db upgrade
    └── New pods start with updated image
```

---

## Tech Stack

| Layer            | Tool                                          |
| ---------------- | --------------------------------------------- |
| Application      | Python 3.11, Flask, SQLAlchemy, Flask-Migrate |
| Database         | PostgreSQL 16 (dedicated private VM)          |
| Containerization | Docker (multi-stage build)                    |
| Registry         | Docker Hub                                    |
| CI/CD            | GitHub Actions                                |
| GitOps           | ArgoCD                                        |
| IaC              | Terraform + Kubernetes provider               |
| Orchestration    | Kubernetes (kubeadm v1.30.14)                 |
| CNI              | Flannel (10.244.0.0/16)                       |
| Ingress          | Nginx (reverse proxy)                         |
| Cloud            | Oracle Cloud (VM.Standard.E3.Flex)            |
| Metrics          | Prometheus + prometheus-client                |
| Dashboards       | Grafana                                       |
| Logging          | Loki + Promtail                               |
| Testing          | pytest (9 tests)                              |

---

## Project Structure

```
autodeploy-lab/
├── app/
│   ├── app.py                  # Flask app with full CRUD API + Prometheus metrics
│   ├── requirements.txt        # Python dependencies
│   ├── pytest.ini              # pytest configuration
│   ├── templates/
│   │   └── index.html          # Landing page UI
│   ├── migrations/             # Flask-Migrate database migrations
│   │   └── versions/
│   │       └── 69ce641_initial_migration_items_table.py
│   └── tests/
│       ├── __init__.py
│       ├── conftest.py
│       └── test_app.py         # 9 automated tests
├── docker/
│   ├── Dockerfile              # Multi-stage build
│   ├── docker-compose.yml      # Local development (app + postgres)
│   └── .env.example            # Environment variable template
├── .github/
│   └── workflows/
│       ├── ci.yml              # PR: test only
│       └── deploy.yml          # main: test → build → push → update manifest
├── terraform/
│   ├── main.tf                 # Local K8s resources
│   ├── variables.tf
│   └── outputs.tf
├── terraform-oci/
│   ├── main.tf                 # OCI infrastructure (VCN, subnets, security lists)
│   ├── variables.tf
│   ├── versions.tf
│   └── outputs.tf
├── k8s/
│   ├── namespace.yaml
│   ├── configmap.yaml          # Non-sensitive config
│   ├── secret.yaml             # Template only — never committed with real values
│   ├── deployment.yaml         # Rolling updates, init container, probes, limits
│   ├── service.yaml            # NodePort — Nginx proxies port 80 → 30080
│   └── hpa.yaml                # Autoscaler (2–5 replicas, 70% CPU threshold)
├── monitoring/
│   ├── servicemonitor.yaml     # Prometheus scrape config
│   └── grafana-dashboard.json  # Exported Grafana dashboard
└── README.md
```

---

## API Endpoints

| Endpoint      | Method | Description                                                     |
| ------------- | ------ | --------------------------------------------------------------- |
| `/`           | GET    | Landing page UI                                                 |
| `/api`        | GET    | Returns app version and environment as JSON                     |
| `/health`     | GET    | Liveness/readiness probe — includes database connectivity check |
| `/metrics`    | GET    | Prometheus metrics scrape target                                |
| `/items`      | GET    | List all items from PostgreSQL                                  |
| `/items`      | POST   | Create a new item                                               |
| `/items/<id>` | PUT    | Update an existing item                                         |
| `/items/<id>` | DELETE | Delete an item                                                  |

---

## Getting Started

### Prerequisites

- Python 3.11+
- Docker Desktop
- kubectl
- Terraform
- Helm
- ArgoCD CLI

### 1. Run locally with Docker Compose

```bash
# Copy environment template
cp docker/.env.example docker/.env
# Fill in your values in docker/.env

cd docker
docker compose up --build
```

Test the API:

```bash
# Create an item
curl -X POST http://localhost:5000/items \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Item", "description": "My first item"}'

# List all items
curl http://localhost:5000/items
```

### 2. Run tests

```bash
cd app
pytest tests/ -v
```

Expected: 9 tests passing. Tests use SQLite in-memory — no real database needed.

### 3. Deploy to cloud with ArgoCD (GitOps)

ArgoCD watches the `k8s/` folder. Any manifest change triggers an automatic rollout.

```bash
# Create required secrets directly on the cluster (never in Git)
kubectl create secret generic postgres-secret \
  --namespace autodeploy \
  --from-literal=DATABASE_URL="postgresql+psycopg://user:pass@DB_PRIVATE_IP:5432/autodeploy"

kubectl create secret generic autodeploy-lab-secret \
  --namespace autodeploy \
  --from-literal=SECRET_KEY="$(openssl rand -hex 32)"
```

### 4. Install the observability stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

kubectl create namespace monitoring

helm install prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword=admin123 \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set "grafana.additionalDataSources[0].name=Loki" \
  --set "grafana.additionalDataSources[0].type=loki" \
  --set "grafana.additionalDataSources[0].url=http://loki-gateway.monitoring.svc.cluster.local" \
  --set "grafana.additionalDataSources[0].access=proxy" \
  --set "grafana.additionalDataSources[0].isDefault=false"

helm install loki grafana/loki \
  --namespace monitoring \
  --set loki.auth_enabled=false \
  --set loki.commonConfig.replication_factor=1 \
  --set loki.storage.type=filesystem \
  --set deploymentMode=SingleBinary \
  --set singleBinary.replicas=1 \
  --set read.replicas=0 \
  --set write.replicas=0 \
  --set backend.replicas=0 \
  --set monitoring.enabled=false \
  --set test.enabled=false \
  --set loki.useTestSchema=true

helm install promtail grafana/promtail \
  --namespace monitoring \
  --set "config.clients[0].url=http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push"

kubectl apply -f monitoring/servicemonitor.yaml
```

Import `monitoring/grafana-dashboard.json` into Grafana to restore the RED metrics dashboard.

---

## Cloud Infrastructure

### VM 1 — Application Server (public subnet)

- **Shape:** VM.Standard.E3.Flex (2 OCPUs, 32GB RAM)
- **Kubernetes:** vanilla kubeadm (v1.30.14)
- **CNI:** Flannel
- **Ingress:** Nginx reverse proxy (port 80 → NodePort 30080)
- **GitOps:** ArgoCD

### VM 2 — Database Server (private subnet)

- **Shape:** VM.Standard.E2.1.Micro (free tier)
- **Database:** PostgreSQL 16
- **Access:** only reachable from app VM on port 5432
- **Network:** private subnet, no internet inbound
- **Outbound:** NAT Gateway for package updates

### Network Security

- DB VM in private subnet — unreachable from internet
- PostgreSQL port 5432 open only to `10.0.0.0/24` (app VM subnet)
- Database credentials stored as Kubernetes Secrets — never in Git

---

## Kubernetes Features

- **Rolling updates** — zero downtime deploys
- **Init container** — runs `flask db upgrade` before app starts, ensures schema is always current
- **Liveness probe** — restarts crashed pods, checks both app and database connectivity
- **Readiness probe** — removes unhealthy pods from load balancer
- **Resource limits** — prevents noisy neighbour issues
- **ConfigMap** — non-sensitive config decoupled from image
- **Secrets** — credentials injected at runtime, never in Git
- **HPA** — autoscales 2→5 replicas at 70% CPU

---

## Observability

Three Grafana dashboard panels using RED metrics:

| Panel        | Query                                                                    | What it shows                   |
| ------------ | ------------------------------------------------------------------------ | ------------------------------- |
| Request Rate | `rate(app_request_count_total[5m])`                                      | Requests per second by endpoint |
| Error Rate   | `rate(app_request_count_total{status=~"4\|5.."}[5m])`                    | Client and server errors        |
| p95 Latency  | `histogram_quantile(0.95, rate(app_request_latency_seconds_bucket[5m]))` | 95th percentile response time   |

View live logs from all pods in Grafana → Explore → Loki:

```
{namespace="autodeploy"}
```

---

## Secret Management

Secrets are never committed to Git. They are created directly on the cluster:

```bash
# Database connection string
kubectl create secret generic postgres-secret \
  --namespace autodeploy \
  --from-literal=DATABASE_URL="postgresql+psycopg://..."

# Application secret key
kubectl create secret generic autodeploy-lab-secret \
  --namespace autodeploy \
  --from-literal=SECRET_KEY="$(openssl rand -hex 32)"
```
