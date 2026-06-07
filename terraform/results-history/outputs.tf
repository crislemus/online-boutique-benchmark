output "bucket_name" {
  description = "Results-history bucket name."
  value       = google_storage_bucket.results.name
}

output "bucket_url" {
  description = "gs:// URL of the results-history bucket."
  value       = "gs://${google_storage_bucket.results.name}"
}
