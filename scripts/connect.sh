#!/usr/bin/env bash
# Fetch kubeconfig credentials for the benchmark cluster.
# Requires the gke-gcloud-auth-plugin (standard on Cloud Build / Cloud Shell;
# install via `gcloud components install gke-gcloud-auth-plugin` on a
# non-snap SDK install).
set -euo pipefail

PROJECT="${PROJECT_ID:-performance-analysis-2026}"
ZONE="${ZONE:-us-central1-a}"
CLUSTER="${CLUSTER_NAME:-boutique-bench}"

gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project "$PROJECT"
kubectl config current-context
