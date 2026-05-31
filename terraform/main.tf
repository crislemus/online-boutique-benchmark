# ---------------------------------------------------------------------------
# Dedicated VPC-native network (isolates the benchmark from the default VPC)
# ---------------------------------------------------------------------------
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.10.0.0/20"

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/14"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.24.0.0/20"
  }

  private_ip_google_access = true
}

# ---------------------------------------------------------------------------
# GKE Standard cluster (zonal) with Managed Service for Prometheus enabled
# ---------------------------------------------------------------------------
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.zone

  # Manage node pools separately so each can pin a processor family.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  release_channel {
    channel = "REGULAR"
  }

  # Google Managed Service for Prometheus (GMP) managed collection.
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  # NOTE (permissions-driven decision):
  # Workload Identity node metadata is intentionally NOT enabled. The runtime SA
  # available in this project has Editor but cannot set IAM policy, so KSA->GSA
  # bindings cannot be created. Pods therefore rely on the node's attached SA
  # (Editor -> monitoring read/write) for GMP collection and the Grafana read
  # path. In production, enable Workload Identity + least-privilege GSAs instead
  # (see README "Production hardening").

  # Allow `terraform destroy` for this ephemeral benchmark environment.
  deletion_protection = false

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}

# ---------------------------------------------------------------------------
# One node pool per processor generation under test (N2 vs C3)
# ---------------------------------------------------------------------------
resource "google_container_node_pool" "pools" {
  for_each = var.pools

  name     = "pool-${each.key}"
  location = var.zone
  cluster  = google_container_cluster.primary.name

  autoscaling {
    min_node_count = var.pool_min_nodes
    max_node_count = var.pool_max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = var.node_disk_size_gb
    disk_type    = var.node_disk_type # pd-balanced (C3 does not support pd-standard)

    # `proc` label is used by the Online Boutique overlays' nodeSelector to pin
    # each copy of the app to a specific processor family.
    labels = {
      proc = each.value.proc_label
    }

    # cloud-platform scope so the node SA can write metrics (GMP collection) and
    # the GMP frontend pod can read time series via ADC.
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    # Keep node-SA ADC available to pods (no GKE_METADATA / Workload Identity).
    workload_metadata_config {
      mode = "GCE_METADATA"
    }
  }
}
