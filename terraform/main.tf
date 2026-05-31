terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }
  required_version = ">= 1.0"
}

# ── Provider: tells Terraform how to talk to your cluster ───────────
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}

# ── Resource 1: Namespace ────────────────────────────────────────────
# A namespace is like a folder inside Kubernetes — it isolates
# your app's resources from anything else running in the cluster.
resource "kubernetes_namespace" "app" {
  metadata {
    name = var.namespace
    labels = {
      app     = var.app_name
      managed = "terraform"
    }
  }
}

# ── Resource 2: Deployment ───────────────────────────────────────────
# Tells Kubernetes to run N replicas of your container
# and restart them automatically if they crash.
resource "kubernetes_deployment" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.app.metadata[0].name
    labels = {
      app     = var.app_name
      version = var.app_version
    }
  }

  spec {
    replicas = var.replica_count

    selector {
      match_labels = {
        app = var.app_name
      }
    }

    template {
      metadata {
        labels = {
          app     = var.app_name
          version = var.app_version
        }
      }

      spec {
        container {
          name  = var.app_name
          image = var.docker_image

          port {
            container_port = 5000
          }

          # Environment variables injected into the container
          env {
            name  = "ENVIRONMENT"
            value = "production"
          }

          env {
            name  = "APP_VERSION"
            value = var.app_version
          }

          # Liveness probe: Kubernetes restarts the pod if this fails
          liveness_probe {
            http_get {
              path = "/health"
              port = 5000
            }
            initial_delay_seconds = 10
            period_seconds        = 30
          }

          # Readiness probe: Kubernetes only sends traffic when this passes
          readiness_probe {
            http_get {
              path = "/health"
              port = 5000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          # Resource limits: prevents one pod from starving others
          resources {
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
}

# ── Resource 3: Service ──────────────────────────────────────────────
# Exposes your pods as a stable network endpoint.
# NodePort makes it accessible from outside the cluster (needed for minikube).
resource "kubernetes_service" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    selector = {
      app = var.app_name
    }

    port {
      port        = 80
      target_port = 5000
      node_port   = 30080
    }

    type = "NodePort"
  }
}

# ── Resource 4: ConfigMap ────────────────────────────────────────────
# Stores non-sensitive configuration outside the container image.
# Change config without rebuilding the image.
resource "kubernetes_config_map" "app" {
  metadata {
    name      = "${var.app_name}-config"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    ENVIRONMENT = "production"
    APP_VERSION = var.app_version
    LOG_LEVEL   = "INFO"
  }
}