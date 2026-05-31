# ── Provider ─────────────────────────────────────────────────────────
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# ── VCN (Virtual Cloud Network) ──────────────────────────────────────
# Equivalent to a VPC in AWS or VNet in Azure.
resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  cidr_block     = "10.0.0.0/16"
  display_name   = "${var.app_name}-vcn"
  dns_label      = "autodeploy"
}

# ── Internet Gateway ──────────────────────────────────────────────────
resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  enabled        = true
  display_name   = "${var.app_name}-igw"
}

# ── Route Table ───────────────────────────────────────────────────────
resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.app_name}-public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.main.id
  }
}

# ── Security List for Worker Nodes ────────────────────────────────────
resource "oci_core_security_list" "workers" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.app_name}-workers-sl"

  # Allow all outbound traffic
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # Allow all inbound traffic within the VCN (pod-to-pod communication)
  ingress_security_rules {
    source   = "10.0.0.0/16"
    protocol = "all"
  }

  # Allow NodePort range (for services exposed externally)
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 30000
      max = 32767
    }
  }

  # Allow SSH for debugging
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # Allow nodes to receive connections from OKE control plane (kubelet)
  # Port 10250 = kubelet API — control plane calls this to manage pods
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 10250
      max = 10250
    }
  }

  # Allow nodes to receive Kubernetes API traffic
  # Port 6443 = Kubernetes API server
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 6443
      max = 6443
    }
  }
}

# ── Security List for Load Balancer ───────────────────────────────────
resource "oci_core_security_list" "lb" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.app_name}-lb-sl"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 443
      max = 443
    }
  }
}

# ── Public Subnet for Worker Nodes ────────────────────────────────────
resource "oci_core_subnet" "workers" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = "10.0.1.0/24"
  display_name      = "${var.app_name}-workers-subnet"
  dns_label         = "workers"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.workers.id]
}

# ── Public Subnet for Load Balancer ───────────────────────────────────
resource "oci_core_subnet" "lb" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = "10.0.2.0/24"
  display_name      = "${var.app_name}-lb-subnet"
  dns_label         = "lb"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.lb.id]
}

# ── OKE Cluster ───────────────────────────────────────────────────────
# OKE = Oracle Kubernetes Engine (equivalent to EKS/AKS)
# OCI manages the control plane for free — you only pay for worker nodes.
resource "oci_containerengine_cluster" "main" {
  compartment_id     = var.compartment_ocid
  kubernetes_version = var.kubernetes_version
  name               = "${var.app_name}-cluster"
  vcn_id             = oci_core_vcn.main.id

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = oci_core_subnet.lb.id
  }

  options {
    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }

    service_lb_subnet_ids = [oci_core_subnet.lb.id]
  }
}

# ── Node Pool ─────────────────────────────────────────────────────────
# VM.Standard.E2.1 = AMD fixed shape, OKE-supported, always available.
# Fixed shapes don't use node_shape_config — shape is fully defined by name.
resource "oci_containerengine_node_pool" "main" {
  cluster_id         = oci_containerengine_cluster.main.id
  compartment_id     = var.compartment_ocid
  kubernetes_version = var.kubernetes_version
  name               = "${var.app_name}-node-pool"
  node_shape         = "VM.Standard.E2.1"

  node_source_details {
    image_id    = data.oci_core_images.oracle_linux.images[0].id
    source_type = "IMAGE"
  }

  node_config_details {
    size = var.node_count

    placement_configs {
      availability_domain = var.availability_domain
      subnet_id           = oci_core_subnet.workers.id
    }
  }
}

# ── Data source: latest Oracle Linux 8 image for VM.Standard.E2.1 ────
# Shape must match exactly what the node pool uses.
data "oci_core_images" "oracle_linux" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = "VM.Standard.E2.1"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}
