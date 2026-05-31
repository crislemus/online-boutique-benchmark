#!/usr/bin/env bash
# Deploy the observability stack and both Online Boutique copies onto the
# already-provisioned GKE cluster. Idempotent.
#
# Prerequisites: kubectl, gke-gcloud-auth-plugin, and cluster credentials
# (run scripts/connect.sh or `make connect` first).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Enabling kubelet/cAdvisor scraping in Managed Service for Prometheus"
# OperatorConfig is an addon-managed singleton; patch it (see 10-operatorconfig.yaml).
kubectl -n gmp-public patch operatorconfig config --type=merge \
  -p '{"collection":{"kubeletScraping":{"interval":"30s"}}}'

echo "==> Deploying observability stack (GMP frontend + Grafana)"
kubectl apply -f k8s/monitoring/00-namespace.yaml
kubectl apply -f k8s/monitoring/20-gmp-frontend.yaml

# Load the dashboard JSON (kept as a standalone artifact) into a ConfigMap.
echo "==> Loading Grafana dashboard ConfigMap from dashboards/"
kubectl create configmap grafana-dashboards \
  --namespace monitoring \
  --from-file=dashboards/ \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f k8s/monitoring/30-grafana.yaml

echo "==> Deploying Online Boutique on the N2 pool (boutique-n2)"
kubectl apply -k k8s/overlays/boutique-n2

echo "==> Deploying Online Boutique on the C3 pool (boutique-c3)"
kubectl apply -k k8s/overlays/boutique-c3

echo "==> Waiting for workloads to become ready (this can take a few minutes)"
for ns in boutique-n2 boutique-c3; do
  kubectl rollout status deploy/frontend -n "$ns" --timeout=300s
done
kubectl rollout status deploy/grafana -n monitoring --timeout=180s
kubectl rollout status deploy/frontend -n monitoring --timeout=120s

echo "==> Done. Pod placement (should match proc label of the node):"
kubectl get pods -n boutique-n2 -o wide | head -5
kubectl get pods -n boutique-c3 -o wide | head -5

cat <<'EOF'

Next steps:
  - View Grafana:   kubectl -n monitoring port-forward svc/grafana 3000:3000
                    then open http://localhost:3000  (anonymous viewer; admin/admin)
  - Run benchmark:  scripts/run-benchmark.sh
EOF
