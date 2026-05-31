# ── OCI Authentication ───────────────────────────────────────────────
variable "tenancy_ocid" {
  description = "OCID of your OCI tenancy (root account)"
  type        = string
}

variable "user_ocid" {
  description = "OCID of your OCI user"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of your API key"
  type        = string
}

variable "private_key_path" {
  description = "Path to your OCI API private key"
  type        = string
  default     = "~/.oci/oci_api_key.pem"
}

variable "region" {
  description = "OCI region"
  type        = string
  default     = "eu-frankfurt-1"
}

# ── Project ──────────────────────────────────────────────────────────
variable "compartment_ocid" {
  description = "OCID of the compartment to deploy into"
  type        = string
}

variable "availability_domain" {
  description = "Availability domain name (e.g. efXT:EU-FRANKFURT-1-AD-1)"
  type        = string
}

variable "app_name" {
  description = "Name of the application"
  type        = string
  default     = "autodeploy-lab"
}

# ── Kubernetes ───────────────────────────────────────────────────────
variable "kubernetes_version" {
  description = "Kubernetes version for OKE cluster"
  type        = string
  default     = "v1.32.1"
}

variable "node_shape" {
  description = "Compute shape for worker nodes"
  type        = string
  default     = "VM.Standard.E2.1"
}

variable "node_ocpus" {
  description = "Number of OCPUs per node (free tier: up to 4 total)"
  type        = number
  default     = 1
}

variable "node_memory_gb" {
  description = "Memory per node in GB (free tier: up to 24GB total)"
  type        = number
  default     = 8
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}