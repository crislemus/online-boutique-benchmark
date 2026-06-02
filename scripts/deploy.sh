#!/usr/bin/env bash
# Deploy the observability stack and one Online Boutique copy per selected
# platform (from config/platforms.json) onto the already-provisioned cluster.
# Idempotent. Used by both `make deploy` and cloudbuild/provision.yaml.
#
# Prerequisites: kubectl, gke-gcloud-auth-plugin, cluster credentials
# (run scripts/connect.sh or `make connect` first), python3.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "${REPO_ROOT}/scripts/lib.sh"
cd "$REPO_ROOT" || exit 1

SELECTED="$(platforms_selected)"
echo "==> Selected platforms: ${SELECTED}"

echo "==> Enabling kubelet/cAdvisor scraping in Managed Service for Prometheus"
# OperatorConfig is an addon-managed singleton; patch it (see 10-operatorconfig.yaml).
kubectl -n gmp-public patch operatorconfig config --type=merge \
  -p '{"collection":{"kubeletScraping":{"interval":"30s"}}}'

echo "==> Deploying observability stack (GMP frontend + Grafana)"
kubectl apply -f k8s/monitoring/00-namespace.yaml
kubectl apply -f k8s/monitoring/20-gmp-frontend.yaml

echo "==> Loading Grafana dashboard ConfigMap from dashboards/"
kubectl create configmap grafana-dashboards \
  --namespace monitoring \
  --from-file=dashboards/ \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f k8s/monitoring/30-grafana.yaml

# One Online Boutique copy per selected platform, rendered from the overlay
# template and pinned to that processor pool via nodeSelector proc=<key>.
# The temp dir lives under k8s/overlays/ so the template's ../../base resolves.
TMPL="${REPO_ROOT}/k8s/overlays/boutique.kustomization.tmpl.yaml"
for p in $SELECTED; do
  ns="boutique-${p}"
  echo "==> Deploying Online Boutique on the ${p} pool (${ns} — $(platform_machine_type "$p"))"
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  d="$(mktemp -d "${REPO_ROOT}/k8s/overlays/.render.XXXXXX")"
  trap 'rm -rf "$d"' EXIT
  sed -e "s/__NS__/${ns}/g" -e "s/__PROC__/${p}/g" "$TMPL" > "${d}/kustomization.yaml"
  kubectl apply -k "$d"
  rm -rf "$d"; trap - EXIT
done

echo "==> Running health checks"
"${REPO_ROOT}/scripts/healthcheck.sh"

cat <<EOF

Deploy complete for: ${SELECTED}
  - View Grafana:   kubectl -n monitoring port-forward svc/grafana 3000:3000
                    then open http://localhost:3000  (anonymous viewer; admin/admin)
  - Run benchmark:  scripts/run-benchmark.sh
EOF
