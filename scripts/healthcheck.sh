#!/usr/bin/env bash
# Functional health checks: confirm the deployed stack is truly ready to take
# load. Runs all checks, aggregates failures, exits non-zero on any failure.
# Used by deploy.sh, `make health`, and cloudbuild/provision.yaml.
#
# Checks (per selected platform from config/platforms.json + monitoring):
#   1. each pool has a Ready node with the right proc label
#   2. all Deployments Available in boutique-<key> and monitoring
#   3. frontend serves HTTP 200 (ephemeral in-cluster curl)
#   4. metrics flowing: GMP frontend ready + non-empty CPU series per namespace
#   5. Grafana healthy + the gmp data source health is OK
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "${REPO_ROOT}/scripts/lib.sh"

SELECTED="$(platforms_selected)"
fail=0
red() { printf '\033[31m%s\033[0m\n' "$1"; }
grn() { printf '\033[32m%s\033[0m\n' "$1"; }
sec() { printf '\n=== %s ===\n' "$1"; }

# retry <timeout_s> <interval_s> <desc> <cmd...>
retry() {
  local t=$1 i=$2 desc=$3
  shift 3
  local end=$((SECONDS + t))
  until "$@"; do
    if [ "$SECONDS" -ge "$end" ]; then
      red "TIMEOUT after ${t}s: ${desc}"
      return 1
    fi
    sleep "$i"
  done
}

sec "1. Ready nodes per selected pool"
for p in $SELECTED; do
  if kubectl wait --for=condition=Ready node -l "proc=${p}" --timeout=180s >/dev/null 2>&1; then
    grn "node proc=${p} Ready"
  else
    red "no Ready node for proc=${p}"
    fail=1
  fi
done

sec "2. Deployments Available"
for p in $SELECTED; do
  ns="boutique-${p}"
  if kubectl wait --for=condition=Available deploy --all -n "$ns" --timeout=300s >/dev/null 2>&1; then
    grn "${ns}: all deployments Available"
  else
    red "${ns}: deployments not Available"
    fail=1
  fi
done
if kubectl wait --for=condition=Available deploy --all -n monitoring --timeout=180s >/dev/null 2>&1; then
  grn "monitoring: all deployments Available"
else
  red "monitoring: deployments not Available"
  fail=1
fi

sec "3. Frontend serves HTTP 200"
http200() {
  local ns=$1 out
  out="$(kubectl run "hc-curl-$$" -n "$ns" --rm -i --restart=Never --quiet \
    --image=curlimages/curl:8.10.1 --command -- \
    curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "http://frontend.${ns}.svc:80" 2>/dev/null)"
  echo "$out" | grep -q 200
}
for p in $SELECTED; do
  ns="boutique-${p}"
  if retry 120 10 "frontend 200 in ${ns}" http200 "$ns"; then
    grn "${ns}: frontend HTTP 200"
  else
    red "${ns}: frontend not serving 200"
    fail=1
  fi
done

sec "4. Metrics flowing (GMP)"
metrics_ready() {
  curl -fsS http://localhost:9090/-/ready >/dev/null 2>&1 || return 1
  for p in $SELECTED; do
    local has
    has="$(curl -fsG http://localhost:9090/api/v1/query \
      --data-urlencode "query=sum(rate(container_cpu_usage_seconds_total{namespace=\"boutique-${p}\",container!=\"\",container!=\"POD\"}[2m]))" 2>/dev/null \
      | python3 -c "import json,sys;print(1 if json.load(sys.stdin)['data']['result'] else 0)" 2>/dev/null)"
    [ "$has" = "1" ] || return 1
  done
}
kubectl -n monitoring port-forward svc/frontend 9090:9090 >/tmp/hc-pf-frontend.log 2>&1 &
PF1=$!
sleep 4
if retry 180 10 "metrics present for all namespaces" metrics_ready; then
  grn "metrics flowing for: ${SELECTED}"
else
  red "metrics not flowing"
  fail=1
fi
kill $PF1 2>/dev/null || true

sec "5. Grafana + data source health"
grafana_ready() {
  curl -fsS http://localhost:3000/api/health 2>/dev/null | grep -q '"database": *"ok"' || return 1
  curl -fsS -u admin:admin http://localhost:3000/api/datasources/uid/gmp/health 2>/dev/null | grep -q '"status":"OK"' || return 1
}
kubectl -n monitoring port-forward svc/grafana 3000:3000 >/tmp/hc-pf-grafana.log 2>&1 &
PF2=$!
sleep 4
if retry 120 8 "grafana + datasource healthy" grafana_ready; then
  grn "grafana healthy; gmp data source OK"
else
  red "grafana / data source not healthy"
  fail=1
fi
kill $PF2 2>/dev/null || true

sec "result"
if [ "$fail" = "0" ]; then
  grn "HEALTHY — stack is ready to take load (${SELECTED})"
else
  red "UNHEALTHY — see failures above"
fi
exit "$fail"
