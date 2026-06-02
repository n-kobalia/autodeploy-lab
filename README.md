# AutoDeploy Lab

A production-grade DevOps pipeline built from scratch — containerizing a Python/Flask service with multi-stage Docker builds, provisioning Kubernetes infrastructure via Terraform IaC, automating CI/CD through GitHub Actions with deployment gates, deploying via GitOps with ArgoCD, and implementing full-stack observability using Prometheus, Grafana, and Loki.

> Live at: http://152.70.5.232

---

## Architecture

```
Code Push (GitHub)
      │
      ▼
GitHub Actions CI/CD
  ├── PR: run tests only (deployment gate)
  └── main: test → build → push image → update manifest
      │
      ▼
Docker Hub (versioned image registry)
      │
      ▼
ArgoCD (GitOps — watches k8s/ folder in GitHub)
      │
      ▼
Kubernetes Cluster (kubeadm on Oracle Cloud)
  ├── Nginx (reverse proxy — port 80 → NodePort 30080)
  ├── Deployment (2 replicas, rolling updates)
  ├── Service (NodePort)
  ├── ConfigMap (env config)
  ├── Secret (credentials)
  └── HorizontalPodAutoscaler (2–5 pods, CPU-based)
      │
      ▼
Observability Stack
  ├── Prometheus (scrapes /metrics every 15s)
  ├── Grafana (dashboards: request rate, error rate, p95 latency)
  └── Loki + Promtail (log aggregation from all pods)
```

---

## Tech Stack

| Layer            | Tool                               |
| ---------------- | ---------------------------------- |
| Application      | Python 3.11, Flask                 |
| Containerization | Docker (multi-stage build)         |
| Registry         | Docker Hub                         |
| CI/CD            | GitHub Actions                     |
| GitOps           | ArgoCD                             |
| IaC              | Terraform + Kubernetes provider    |
| Orchestration    | Kubernetes (kubeadm)               |
| CNI              | Flannel                            |
| Ingress          | Nginx (reverse proxy)              |
| Cloud            | Oracle Cloud (VM.Standard.E3.Flex) |
| Metrics          | Prometheus + prometheus-client     |
| Dashboards       | Grafana                            |
| Logging          | Loki + Promtail                    |
| Testing          | pytest                             |

---

## Project Structure

```
autodeploy-lab/
├── app/
│   ├── app.py                  # Flask app (/, /api, /health, /metrics, /items)
│   ├── requirements.txt        # Python dependencies
│   ├── pytest.ini              # pytest configuration
│   ├── templates/
│   │   └── index.html          # Landing page UI
│   └── tests/
│       ├── __init__.py
│       ├── conftest.py
│       └── test_app.py         # automated tests
├── docker/
│   ├── Dockerfile              # Multi-stage build
│   └── docker-compose.yml      # Local development
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
│   ├── configmap.yaml
│   ├── secret.yaml
│   ├── deployment.yaml         # Rolling updates, probes, resource limits
│   ├── service.yaml            # NodePort — Nginx proxies port 80 → 30080
│   └── hpa.yaml                # Autoscaler (2–5 replicas, 70% CPU threshold)
├── monitoring/
│   ├── servicemonitor.yaml     # Prometheus scrape config
│   └── grafana-dashboard.json  # Exported Grafana dashboard
└── README.md
```

---

## Getting Started

### Prerequisites

- Python 3.11+
- Docker Desktop
- kubectl
- minikube (local) or kubeadm cluster (cloud)
- Terraform
- Helm
- ArgoCD CLI

### 1. Run the app locally

```bash
cd app
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python app.py
```

Visit `http://localhost:5000/`

### 2. Run tests

```bash
cd app
pytest tests/ -v
```

Expected: 6 tests passing.

### 3. Run with Docker

```bash
docker build -f docker/Dockerfile -t autodeploy-lab:v1.0.0 .
docker run -p 5000:5000 autodeploy-lab:v1.0.0
```

### 4. Deploy locally with Terraform

```bash
minikube start
cd terraform
terraform init
terraform plan
terraform apply
```

### 5. Deploy to cloud with ArgoCD (GitOps)

ArgoCD watches the `k8s/` folder in this repository. Any change to a manifest automatically triggers a rollout.

```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Expose UI
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "NodePort", "ports": [{"port": 80, "targetPort": 8080, "nodePort": 30090}]}}'

# Connect repo and create application pointing to k8s/ folder
# Destination: https://kubernetes.default.svc — namespace: autodeploy
```

### 6. Install the observability stack

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

Import `monitoring/grafana-dashboard.json` into Grafana to restore the dashboard.

---

## API Endpoints

| Endpoint   | Method | Description                                 |
| ---------- | ------ | ------------------------------------------- |
| `/`        | GET    | Landing page UI                             |
| `/api`     | GET    | Returns app version and environment as JSON |
| `/health`  | GET    | Kubernetes liveness/readiness probe         |
| `/metrics` | GET    | Prometheus metrics scrape target            |
| `/items`   | GET    | Sample resource endpoint                    |

---

## CI/CD Pipeline

Three jobs run automatically on push to `main`:

**`test`** — runs pytest, blocks deploy if any test fails

**`build-and-push`** — builds Docker image, pushes to Docker Hub with two tags:

- `latest`
- `<git-commit-sha>` — every image traceable to its source commit

**`update-manifest`** — automatically updates the image tag in `k8s/deployment.yaml` and commits back to the repo, triggering ArgoCD to detect the change and deploy

---

## GitOps Flow

```
git push → GitHub Actions → new image pushed to Docker Hub
        → manifest updated with commit SHA
        → ArgoCD detects change in k8s/
        → ArgoCD syncs cluster to match Git
        → Kubernetes rolls out new pods (zero downtime)
```

Git is the single source of truth. Nobody applies manifests manually.

---

## Cloud Infrastructure

Deployed on **Oracle Cloud** (always-free tier + $300 credits):

- **Instance:** VM.Standard.E3.Flex (2 OCPUs, 32GB RAM)
- **Kubernetes:** vanilla kubeadm install (v1.30.14)
- **CNI:** Flannel (`10.244.0.0/16` pod CIDR)
- **Ingress:** Nginx reverse proxy (port 80 → NodePort 30080)
- **Storage:** local-path-provisioner (for Loki persistence)
- **GitOps:** ArgoCD watching `k8s/` folder

---

## Kubernetes Features

- **Rolling updates** — zero downtime deploys
- **Liveness probe** — restarts crashed pods automatically
- **Readiness probe** — removes unhealthy pods from load balancer
- **Resource limits** — prevents noisy neighbour issues
- **ConfigMap** — environment config decoupled from image
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
