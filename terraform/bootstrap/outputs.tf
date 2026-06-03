# Values to copy into the GitHub repo's Actions Variables (non-secret, keyless).

output "gcp_workload_identity_provider" {
  description = "Set as GitHub Actions variable GCP_WORKLOAD_IDENTITY_PROVIDER."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "gcp_service_account" {
  description = "Set as GitHub Actions variable GCP_SERVICE_ACCOUNT."
  value       = google_service_account.deployer.email
}

output "gcp_project" {
  description = "Set as GitHub Actions variable GCP_PROJECT."
  value       = var.project_id
}

output "github_setup_summary" {
  description = "Copy these into GitHub: Settings -> Secrets and variables -> Actions -> Variables."
  value       = <<-EOT
    GCP_WORKLOAD_IDENTITY_PROVIDER = ${google_iam_workload_identity_pool_provider.github.name}
    GCP_SERVICE_ACCOUNT            = ${google_service_account.deployer.email}
    GCP_PROJECT                    = ${var.project_id}
  EOT
}
