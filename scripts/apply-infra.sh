#!/usr/bin/env sh
# Provision infrastructure with Terraform (init + apply). Single source of truth
# used by both `make up` and cloudbuild/provision.yaml. POSIX sh so it also runs
# in the Alpine-based hashicorp/terraform image (no bash there).
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT/terraform"

terraform init -input=false
terraform apply -auto-approve -input=false
