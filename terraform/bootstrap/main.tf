# ---------------------------------------------------------------------------
# Keyless CI/CD identity: GitHub Actions -> GCP via Workload Identity Federation
# ---------------------------------------------------------------------------
# Applied ONCE by an admin. The GitHub Actions CD workflow exchanges its OIDC
# token for short-lived credentials for the gha-deployer SA — no SA keys ever.

resource "google_project_service" "sts" {
  service            = "sts.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iamcredentials" {
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

# --- Workload Identity Pool + GitHub OIDC provider ---
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions"
  description               = "Keyless OIDC federation for GitHub Actions CI/CD."
  depends_on                = [google_project_service.sts]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  # Hard security boundary: only tokens from THIS repository are accepted, even
  # before the IAM binding is evaluated.
  attribute_condition = "assertion.repository == \"${var.github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# --- Dedicated least-privilege deployer service account ---
resource "google_service_account" "deployer" {
  account_id   = "gha-deployer"
  display_name = "GitHub Actions deployer (CI/CD)"
}

# Roles the pipeline needs to provision the full stack (cluster + node pools +
# the app/monitoring SAs + their IAM/Workload-Identity bindings) and read/write
# Terraform state. projectIamAdmin is broad — see README for the custom-role
# hardening note.
resource "google_project_iam_member" "deployer_roles" {
  for_each = toset([
    "roles/container.admin",
    "roles/compute.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/resourcemanager.projectIamAdmin",
    "roles/monitoring.admin",
    "roles/storage.admin",
    "roles/serviceusage.serviceUsageAdmin",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

# --- Trust binding: only the specified GitHub repo may impersonate the SA ---
resource "google_service_account_iam_member" "deployer_wif" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${var.project_number}/locations/global/workloadIdentityPools/${var.pool_id}/attribute.repository/${var.github_repo}"
  depends_on         = [google_iam_workload_identity_pool_provider.github]
}
