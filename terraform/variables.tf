variable "app_name" {
  description = "Name of the application"
  type        = string
  default     = "autodeploy-lab"
}

variable "namespace" {
  description = "Kubernetes namespace to deploy into"
  type        = string
  default     = "autodeploy"
}

variable "docker_image" {
  description = "Docker image to deploy"
  type        = string
}

variable "app_version" {
  description = "Version of the application"
  type        = string
  default     = "1.0.0"
}

variable "replica_count" {
  description = "Number of pod replicas"
  type        = number
  default     = 2
}