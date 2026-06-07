#!/usr/bin/env bash
# Drive identical synthetic load on both selected Online Boutique copies, soak,
# then capture comparative CPU/memory from Managed Service for Prometheus plus
# throughput/latency from the loadgenerator (Locust) logs. Platform-agnostic:
# the 2 platforms come from config/platforms.json.
#
# Output: docs/results/  (metrics-snapshot.json, cpu_timeseries.csv, loadgen-*.log,
#         summary.md, chart-*.png)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "${REPO_ROOT}/scripts/lib.sh"
cd "$REPO_ROOT" || exit 1
RESULTS="docs/results"
mkdir -p "$RESULTS"

SELECTED="$(platforms_selected)"
SOAK_SECONDS="${SOAK_SECONDS:-900}"   # ~15 min steady-state by default
echo "==> Benchmarking platforms: ${SELECTED} (identical Locust load, USERS=10 RATE=1)"

echo "==> Soaking for ${SOAK_SECONDS}s to reach steady state..."
sleep "$SOAK_SECONDS"

echo "==> Port-forwarding the GMP query frontend..."
kubectl -n monitoring port-forward svc/frontend 9090:9090 >/tmp/pf-frontend.log 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
sleep 5

RANGE="${SOAK_SECONDS}s"
echo "==> Querying comparative metrics over the last ${RANGE}..."
CONFIG_FILE="$CONFIG_FILE" RANGE="$RANGE" RESULTS="$RESULTS" python3 - <<'PY'
import csv, json, os, time, urllib.parse, urllib.request
cfg = json.load(open(os.environ["CONFIG_FILE"]))
plats = cfg["selected"]
labels = {p: cfg["catalog"][p]["label"] for p in plats}
RANGE = os.environ["RANGE"]; RESULTS = os.environ["RESULTS"]
BASE = "http://localhost:9090/api/v1"

def q_inst(expr):
    u = f"{BASE}/query?" + urllib.parse.urlencode({"query": expr})
    r = json.load(urllib.request.urlopen(u, timeout=15))["data"]["result"]
    return float(r[0]["value"][1]) if r else float("nan")

def q_range(expr, mins=15, step=30):
    end = int(time.time()); start = end - mins * 60
    u = f"{BASE}/query_range?" + urllib.parse.urlencode(
        {"query": expr, "start": start, "end": end, "step": step})
    return json.load(urllib.request.urlopen(u, timeout=15))["data"]["result"]

snap = {"platforms": plats, "labels": labels, "cpu": {}, "mem": {}}
rows = {}
for p in plats:
    ns = f"boutique-{p}"
    cpu_e = (f'avg_over_time((sum(rate(container_cpu_usage_seconds_total'
             f'{{namespace="{ns}",container!="",container!="POD"}}[2m])))[{RANGE}:])')
    mem_e = (f'avg_over_time((sum(container_memory_working_set_bytes'
             f'{{namespace="{ns}",container!="",container!="POD"}}))[{RANGE}:])')
    snap["cpu"][p] = q_inst(cpu_e)
    snap["mem"][p] = q_inst(mem_e)
    for ts, val in (q_range(f'sum(rate(container_cpu_usage_seconds_total'
                            f'{{namespace="{ns}",container!="",container!="POD"}}[2m]))', 15, 30) or [{}])[0].get("values", []):
        rows.setdefault(int(ts), {})[p] = val

json.dump(snap, open(f"{RESULTS}/metrics-snapshot.json", "w"), indent=2)
with open(f"{RESULTS}/cpu_timeseries.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(["timestamp"] + [f"{p}_cpu_cores" for p in plats])
    for ts in sorted(rows):
        w.writerow([ts] + [rows[ts].get(p, "") for p in plats])
print("snapshot:", {p: round(snap["cpu"][p], 4) for p in plats})
PY

echo "==> Capturing loadgenerator (Locust) stats..."
for p in $SELECTED; do
  kubectl logs -n "boutique-${p}" deploy/loadgenerator -c main --tail=60 \
    > "${RESULTS}/loadgen-${p}.log" 2>/dev/null || true
done

echo "==> Rendering summary + charts"
python3 "${REPO_ROOT}/scripts/make-charts.py" || true
python3 - "$RESULTS" <<'PY'
import json, sys
R = sys.argv[1]
s = json.load(open(f"{R}/metrics-snapshot.json"))
p = s["platforms"]
rows = "\n".join(
    f"| {k} ({s['labels'][k]}) | {s['cpu'][k]:.4f} | {s['mem'][k]/1048576:.0f} |"
    for k in p)
open(f"{R}/summary.md", "w").write(
    f"# Benchmark summary — {p[0]} vs {p[1]}\n\n"
    f"Identical Locust load (USERS=10, RATE=1) on both copies.\n\n"
    f"| Platform | CPU cores | Memory (MiB) |\n|---|---|---|\n{rows}\n\n"
    f"See chart-*.png and loadgen-*.log for latency/throughput.\n")
print(open(f"{R}/summary.md").read())
PY

echo "==> Building results navigator (index.html)"
python3 "${REPO_ROOT}/scripts/make-results-index.py" || true

echo "==> Publishing run to the durable results-history bucket"
"${REPO_ROOT}/scripts/publish-results.sh" || true
