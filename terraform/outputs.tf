output "namespace" {
  description = "Kubernetes namespace created"
  value       = kubernetes_namespace.app.metadata[0].name
}

output "deployment_name" {
  description = "Name of the Kubernetes deployment"
  value       = kubernetes_deployment.app.metadata[0].name
}

output "service_name" {
  description = "Name of the Kubernetes service"
  value       = kubernetes_service.app.metadata[0].name
}

output "replica_count" {
  description = "Number of replicas running"
  value       = kubernetes_deployment.app.spec[0].replicas
}

output "docker_image" {
  description = "Docker image being used"
  value       = var.docker_image
}