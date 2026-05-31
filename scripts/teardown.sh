#!/usr/bin/env bash
# Destroy all billable resources created for the benchmark.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT/terraform"

echo "==> terraform destroy (GKE cluster, node pools, VPC)"
terraform destroy -auto-approve -input=false

echo "==> Done. Verify no clusters remain:"
gcloud container clusters list || true
