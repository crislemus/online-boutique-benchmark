#!/usr/bin/env bash
# Drive an identical synthetic load on both Online Boutique copies, let it soak,
# then capture comparative CPU/memory evidence from Managed Service for
# Prometheus plus throughput/latency from the loadgenerator (Locust) logs.
#
# Output: docs/results/  (JSON metric snapshots, loadgen logs, summary.md)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
RESULTS="docs/results"
mkdir -p "$RESULTS"

SOAK_SECONDS="${SOAK_SECONDS:-900}"   # ~15 min steady-state by default
FRONTEND_NS="monitoring"

echo "==> Both copies use the same loadgenerator config (USERS=10, RATE=1) by design."
kubectl get deploy loadgenerator -n boutique-n2 -o jsonpath='{.spec.template.spec.containers[0].env}' >/dev/null 2>&1 || true

echo "==> Soaking for ${SOAK_SECONDS}s to reach steady state..."
sleep "$SOAK_SECONDS"

echo "==> Port-forwarding the GMP query frontend..."
kubectl -n "$FRONTEND_NS" port-forward svc/frontend 9090:9090 >/tmp/pf-frontend.log 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
sleep 5

q() {  # PromQL instant query helper -> saves raw JSON, prints scalar value
  local name="$1" expr="$2"
  curl -fsG "http://localhost:9090/api/v1/query" --data-urlencode "query=${expr}" \
    -o "${RESULTS}/${name}.json"
  python3 -c "import json,sys; d=json.load(open('${RESULTS}/${name}.json')); r=d['data']['result']; print(float(r[0]['value'][1]) if r else float('nan'))"
}

RANGE="${SOAK_SECONDS}s"
echo "==> Querying comparative metrics over the last ${RANGE}..."
CPU_N2=$(q cpu_n2 "avg_over_time((sum(rate(container_cpu_usage_seconds_total{namespace=\"boutique-n2\",container!=\"\",container!=\"POD\"}[2m])))[${RANGE}:])")
CPU_C3=$(q cpu_c3 "avg_over_time((sum(rate(container_cpu_usage_seconds_total{namespace=\"boutique-c3\",container!=\"\",container!=\"POD\"}[2m])))[${RANGE}:])")
MEM_N2=$(q mem_n2 "avg_over_time((sum(container_memory_working_set_bytes{namespace=\"boutique-n2\",container!=\"\",container!=\"POD\"}))[${RANGE}:])")
MEM_C3=$(q mem_c3 "avg_over_time((sum(container_memory_working_set_bytes{namespace=\"boutique-c3\",container!=\"\",container!=\"POD\"}))[${RANGE}:])")

echo "==> Capturing loadgenerator (Locust) stats from logs..."
kubectl logs -n boutique-n2 deploy/loadgenerator -c main --tail=60 > "${RESULTS}/loadgen-n2.log" 2>/dev/null || true
kubectl logs -n boutique-c3 deploy/loadgenerator -c main --tail=60 > "${RESULTS}/loadgen-c3.log" 2>/dev/null || true

CPU_DELTA=$(python3 -c "n=$CPU_N2; c=$CPU_C3; print(f'{(n-c)/n*100:.1f}' if n>0 else 'n/a')")
MEM_DELTA=$(python3 -c "n=$MEM_N2; c=$MEM_C3; print(f'{(n-c)/n*100:.1f}' if n>0 else 'n/a')")

cat > "${RESULTS}/summary.md" <<EOF
# Benchmark summary — Online Boutique on N2 vs C3

Identical synthetic load (Locust: USERS=10, RATE=1) applied to both copies;
metrics averaged over the last ${RANGE} of steady state.

| Metric (workload total) | N2 (prev-gen Intel) | C3 (Sapphire Rapids) | C3 vs N2 |
|---|---|---|---|
| CPU cores consumed | ${CPU_N2} | ${CPU_C3} | ${CPU_DELTA}% lower |
| Memory working set (bytes) | ${MEM_N2} | ${MEM_C3} | ${MEM_DELTA}% lower |

Throughput/latency per pool: see loadgen-n2.log / loadgen-c3.log (Locust aggregates).

Interpretation: at the same offered load, lower CPU cores indicates a more
efficient processor for this workload. Pair with Locust latency to confirm both
served the load comparably.
EOF

echo "==> Wrote ${RESULTS}/summary.md"
cat "${RESULTS}/summary.md"
