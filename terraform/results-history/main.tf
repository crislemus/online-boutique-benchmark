# Durable benchmark results-history bucket.
#
# System-of-record for per-run benchmark artifacts (manifest.json,
# metrics-snapshot.json, summary.md, charts, index.html). Written to by the
# benchmark publish step (local + on-demand CI) and read by the ops AI agent for
# regression analysis. PERSISTENT — must survive every cluster teardown, which is
# why it lives in its own Terraform state (see versions.tf).
resource "google_storage_bucket" "results" {
  name     = var.bucket_name
  location = var.region
  project  = var.project_id

  uniform_bucket_level_access = true

  # WARNING: force_destroy lets `terraform destroy` delete the bucket even when
  # it still holds run history. That is intentional (so teardown works) but means
  # one destroy wipes ALL stored results. The `make destroy` target guards this
  # with a typed confirmation.
  force_destroy = true

  # Optional cost hygiene: expire old runs. retention_days = 0 keeps forever.
  dynamic "lifecycle_rule" {
    for_each = var.retention_days > 0 ? [1] : []
    content {
      condition {
        age = var.retention_days
      }
      action {
        type = "Delete"
      }
    }
  }

  labels = {
    purpose = "benchmark-results-history"
    app     = "online-boutique-benchmark"
  }
}
