output "cluster_id" {
  description = "OKE cluster OCID"
  value       = oci_containerengine_cluster.main.id
}

output "cluster_name" {
  description = "OKE cluster name"
  value       = oci_containerengine_cluster.main.name
}

output "node_pool_id" {
  description = "Node pool OCID"
  value       = oci_containerengine_node_pool.main.id
}

output "vcn_id" {
  description = "VCN OCID"
  value       = oci_core_vcn.main.id
}

output "kubeconfig_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "oci ce cluster create-kubeconfig --cluster-id ${oci_containerengine_cluster.main.id} --region ${var.region} --token-version 2.0.0"
}