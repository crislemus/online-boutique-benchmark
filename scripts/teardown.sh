#!/usr/bin/env bash
# Destroy all billable resources created for the benchmark.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT/terraform"

# Initialize the GCS backend first — on a fresh checkout (e.g. a CI runner) the
# .terraform dir doesn't exist yet, so destroy would fail with "Backend
# initialization required". apply-infra.sh already does this; teardown must too.
echo "==> terraform init"
terraform init -input=false

echo "==> terraform destroy (GKE cluster, node pools, VPC)"
terraform destroy -auto-approve -input=false

echo "==> Done. Verify no clusters remain:"
gcloud container clusters list || true
