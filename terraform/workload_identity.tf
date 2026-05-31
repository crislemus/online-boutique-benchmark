# ---------------------------------------------------------------------------
# Least-privilege identities + Workload Identity Federation for GKE
# ---------------------------------------------------------------------------
# Replaces the Iteration-1 fallback (Editor-laden default compute SA on nodes,
# node-SA used for monitoring reads). Now:
#   * nodes run as a dedicated minimal SA (gke-node-sa)
#   * the GMP query frontend reads via a dedicated gmp-reader GSA, mapped to the
#     monitoring/gmp-frontend KSA through Workload Identity
#   * application pods get NO Google credentials (their default KSA is unmapped)

locals {
  wi_pool = "${var.project_id}.svc.id.goog"
}

# --- Dedicated minimal node service account (replaces the default compute SA) ---
resource "google_service_account" "node_sa" {
  account_id   = "gke-node-sa"
  display_name = "GKE node SA (boutique-bench, least privilege)"
}

# Minimal roles a GKE node needs: write metrics/logs, resource metadata, pull images.
# The GMP managed collector (DaemonSet) writes metrics through this node SA.
resource "google_project_iam_member" "node_sa_roles" {
  for_each = toset([
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/logging.logWriter",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.node_sa.email}"
}

# --- Dedicated reader GSA for the GMP query frontend (Grafana read path) ---
resource "google_service_account" "gmp_reader" {
  account_id   = "gmp-reader"
  display_name = "GMP query frontend reader (monitoring.viewer only)"
}

resource "google_project_iam_member" "gmp_reader_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gmp_reader.email}"
}

# Workload Identity binding: the monitoring/gmp-frontend KSA may impersonate gmp-reader.
# (The KSA itself + its iam.gke.io/gcp-service-account annotation live in
#  k8s/monitoring/20-gmp-frontend.yaml.)
resource "google_service_account_iam_member" "gmp_reader_wi" {
  service_account_id = google_service_account.gmp_reader.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.wi_pool}[monitoring/gmp-frontend]"

  # The WI pool (PROJECT.svc.id.goog) only exists once a WI-enabled cluster does.
  depends_on = [google_container_cluster.primary]
}

# --- Staged fallback: dedicated writer identity for the managed collector ---
# Only needed if live verification shows the managed collector cannot write under
# Workload Identity using the node SA. Enable with: -var="collector_wi=true".
# When enabled, also annotate the collector KSA:
#   kubectl annotate sa collector -n gmp-system \
#     iam.gke.io/gcp-service-account=gmp-collector@PROJECT.iam.gserviceaccount.com
variable "collector_wi" {
  description = "Create a dedicated WI writer identity for the gmp-system/collector KSA."
  type        = bool
  default     = false
}

resource "google_service_account" "gmp_collector" {
  count        = var.collector_wi ? 1 : 0
  account_id   = "gmp-collector"
  display_name = "GMP managed collector writer (monitoring.metricWriter only)"
}

resource "google_project_iam_member" "gmp_collector_writer" {
  count   = var.collector_wi ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gmp_collector[0].email}"
}

resource "google_service_account_iam_member" "gmp_collector_wi" {
  count              = var.collector_wi ? 1 : 0
  service_account_id = google_service_account.gmp_collector[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.wi_pool}[gmp-system/collector]"

  depends_on = [google_container_cluster.primary]
}
