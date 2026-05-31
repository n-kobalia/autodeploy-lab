# AutoDeploy Lab

A production-grade DevOps pipeline built from scratch — containerizing a Python/Flask service with multi-stage Docker builds, provisioning Kubernetes infrastructure via Terraform IaC, automating CI/CD through GitHub Actions with deployment gates, and implementing full-stack observability using Prometheus, Grafana, and Loki.

---

## Architecture

```
Code Push (GitHub)
      │
      ▼
GitHub Actions CI/CD
  ├── PR: run tests only (deployment gate)
  └── main: test → build → push Docker image
      │
      ▼
Docker Hub (versioned image registry)
      │
      ▼
Terraform (IaC)
  └── provisions: namespace, deployment, service, configmap
      │
      ▼
Kubernetes Cluster (minikube / cloud)
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

| Layer            | Tool                            |
| ---------------- | ------------------------------- |
| Application      | Python 3.11, Flask              |
| Containerization | Docker (multi-stage build)      |
| Registry         | Docker Hub                      |
| CI/CD            | GitHub Actions                  |
| IaC              | Terraform + Kubernetes provider |
| Orchestration    | Kubernetes (minikube)           |
| Metrics          | Prometheus + prometheus-client  |
| Dashboards       | Grafana                         |
| Logging          | Loki + Promtail                 |
| Testing          | pytest                          |

---

## Project Structure

```
autodeploy-lab/
├── app/
│   ├── app.py                  # Flask app (/, /health, /metrics, /items)
│   ├── requirements.txt        # Python dependencies
│   ├── pytest.ini              # pytest configuration
│   └── tests/
│       ├── __init__.py
│       ├── conftest.py
│       └── test_app.py         # 6 automated tests
├── docker/
│   ├── Dockerfile              # Multi-stage build
│   └── docker-compose.yml      # Local development
├── .github/
│   └── workflows/
│       ├── ci.yml              # PR: test only
│       └── deploy.yml          # main: test + build + push
├── terraform/
│   ├── main.tf                 # K8s resources (namespace, deployment, service, configmap)
│   ├── variables.tf            # Input variables
│   └── outputs.tf              # Output values
├── k8s/
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   ├── deployment.yaml         # Rolling update strategy, probes, resource limits
│   ├── service.yaml
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
- minikube
- Terraform
- Helm

### 1. Run the app locally

```bash
cd app
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python app.py
```

Visit `http://localhost:5000/` — or port 8080 if AirPlay Receiver is using 5000:

```bash
PORT=8080 python app.py
```

### 2. Run tests

```bash
cd app
pytest tests/ -v
```

Expected output: 6 tests passing.

### 3. Run with Docker

```bash
# Build
docker build -f docker/Dockerfile -t autodeploy-lab:v1.0.0 .

# Run
docker run -p 5000:5000 autodeploy-lab:v1.0.0

# Or with Docker Compose
cd docker && docker compose up
```

### 4. Deploy with Terraform

```bash
# Start minikube
minikube start

# Edit terraform/terraform.tfvars with your Docker Hub username
cd terraform
terraform init
terraform plan
terraform apply
```

### 5. Deploy with Kubernetes manifests

```bash
kubectl apply -f k8s/
kubectl get all -n autodeploy
```

Access the app:

```bash
minikube service autodeploy-lab -n autodeploy
```

### 6. Install the observability stack

```bash
# Add Helm repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring

# Install Prometheus + Grafana
helm install prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword=admin123 \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set "grafana.additionalDataSources[0].name=Loki" \
  --set "grafana.additionalDataSources[0].type=loki" \
  --set "grafana.additionalDataSources[0].url=http://loki-gateway.monitoring.svc.cluster.local" \
  --set "grafana.additionalDataSources[0].access=proxy" \
  --set "grafana.additionalDataSources[0].isDefault=false"

# Install Loki
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

# Install Promtail
helm install promtail grafana/promtail \
  --namespace monitoring \
  --set "config.clients[0].url=http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push"

# Apply ServiceMonitor so Prometheus scrapes the app
kubectl apply -f monitoring/servicemonitor.yaml
```

Access Grafana:

```bash
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80
```

Open `http://localhost:3000` — login with `admin` / `admin123`.

Import the dashboard from `monitoring/grafana-dashboard.json`.

---

## API Endpoints

| Endpoint   | Method | Description                         |
| ---------- | ------ | ----------------------------------- |
| `/`        | GET    | Returns app version and environment |
| `/health`  | GET    | Kubernetes liveness/readiness probe |
| `/metrics` | GET    | Prometheus metrics scrape target    |
| `/items`   | GET    | Sample resource endpoint            |

---

## CI/CD Pipeline

Two workflows run automatically on GitHub Actions:

**`ci.yml`** — triggers on every pull request to `main`:

- Sets up Python 3.11
- Installs dependencies
- Runs pytest (blocks merge if any test fails)

**`deploy.yml`** — triggers on every push to `main`:

- Runs the full test suite (deployment gate)
- Builds the Docker image
- Pushes to Docker Hub with two tags:
  - `latest`
  - `<git-commit-sha>` (every image traceable to its source commit)

Required GitHub secrets:

| Secret               | Description                            |
| -------------------- | -------------------------------------- |
| `DOCKERHUB_USERNAME` | Your Docker Hub username               |
| `DOCKERHUB_TOKEN`    | Docker Hub access token (Read & Write) |

---

## Kubernetes Features

- **Rolling updates** — zero downtime deploys via `RollingUpdate` strategy
- **Health probes** — liveness probe restarts crashed pods, readiness probe removes unhealthy pods from load balancer
- **Resource limits** — CPU and memory requests/limits prevent noisy neighbour issues
- **ConfigMap injection** — environment config decoupled from the container image
- **Secrets** — sensitive values stored separately from application config
- **HPA** — automatically scales from 2 to 5 replicas when CPU exceeds 70%

---

## Observability

Three Grafana dashboard panels using RED metrics:

| Panel        | Query                                                                    | What it shows                   |
| ------------ | ------------------------------------------------------------------------ | ------------------------------- |
| Request Rate | `rate(app_request_count_total[5m])`                                      | Requests per second by endpoint |
| Error Rate   | `rate(app_request_count_total{status=~"4\|5.."}[5m])`                    | Client and server errors        |
| p95 Latency  | `histogram_quantile(0.95, rate(app_request_latency_seconds_bucket[5m]))` | 95th percentile response time   |

Logs from all pods are available in Grafana via Loki using the query:

```
{namespace="autodeploy"}
```
