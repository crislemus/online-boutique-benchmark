#!/usr/bin/env bash
# Publish the current benchmark run (docs/results/) to the durable results-history
# bucket for trend/regression analysis by the ops AI agent. Builds a manifest.json
# with provenance (commit, platforms, zone, run-id, trigger, actor) + headline
# metrics, then uploads the run folder to:
#   gs://<bucket>/runs/<pairA-vs-pairB>/<timestamp>__<commit>__<run-id>/
#
# Idempotent-ish (each run gets a unique path). Guarded: skips cleanly if gcloud
# or the bucket is unavailable, so the benchmark still works anywhere.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "${REPO_ROOT}/scripts/lib.sh"
RESULTS="${REPO_ROOT}/docs/results"
BUCKET="${RESULTS_BUCKET:-performance-analysis-2026-benchmark-results}"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "==> gcloud not available; skipping results publish"
  exit 0
fi
if [ ! -f "${RESULTS}/metrics-snapshot.json" ]; then
  echo "==> no metrics-snapshot.json; nothing to publish"
  exit 0
fi
if ! gcloud storage ls "gs://${BUCKET}" >/dev/null 2>&1; then
  echo "==> bucket gs://${BUCKET} not found; skipping (create via terraform/results-history)"
  exit 0
fi

# --- provenance ---
COMMIT="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
TS="$(date -u +%Y-%m-%dT%H%M%SZ)"
RUN_ID="${GITHUB_RUN_ID:-local-$(date -u +%s)}"
TRIGGER="$([ -n "${GITHUB_RUN_ID:-}" ] && echo ci || echo local)"
ACTOR="${GITHUB_ACTOR:-$(whoami)}"
ZONE="${ZONE:-us-central1-a}"
# Pair comes from the RESULT data (metrics-snapshot), not the current config —
# the snapshot records what was actually benchmarked, which is the source of truth.
PAIR="$(python3 -c "import json;print('-'.join(json.load(open('${RESULTS}/metrics-snapshot.json'))['platforms']))")"

# --- manifest.json (metadata + headline metrics for cheap regression reads) ---
COMMIT="$COMMIT" TS="$TS" RUN_ID="$RUN_ID" TRIGGER="$TRIGGER" ACTOR="$ACTOR" \
ZONE="$ZONE" RESULTS="$RESULTS" CONFIG_FILE="$CONFIG_FILE" python3 - <<'PY'
import json, os
R = os.environ["RESULTS"]
snap = json.load(open(f"{R}/metrics-snapshot.json"))
plats = snap["platforms"]

def loadgen(p):
    path = f"{R}/loadgen-{p}.log"
    if not os.path.exists(path):
        return {}
    agg = None
    for line in open(path):
        if line.strip().startswith("Aggregated"):
            agg = line
    if not agg:
        return {}
    t = [x for x in agg.replace("|", " ").split() if x]
    try:
        return {"avg_ms": float(t[3]), "median_ms": float(t[6]),
                "rps": float(t[-2]), "requests": float(t[1])}
    except (IndexError, ValueError):
        return {}

manifest = {
    "timestamp": os.environ["TS"],
    "commit": os.environ["COMMIT"],
    "run_id": os.environ["RUN_ID"],
    "trigger": os.environ["TRIGGER"],
    "actor": os.environ["ACTOR"],
    "zone": os.environ["ZONE"],
    "platforms": plats,
    "labels": snap.get("labels", {}),
    "metrics": {
        p: {
            "cpu_cores": snap["cpu"][p],
            "mem_bytes": snap["mem"][p],
            **loadgen(p),
        } for p in plats
    },
}
json.dump(manifest, open(f"{R}/manifest.json", "w"), indent=2)
print("manifest:", manifest["platforms"], "commit", manifest["commit"])
PY

# --- upload the run folder ---
KEY="runs/${PAIR}/${TS}__${COMMIT}__${RUN_ID}"
echo "==> Publishing to gs://${BUCKET}/${KEY}/"
# rsync the run contents directly under the run key (no extra nesting level).
gcloud storage rsync --recursive "${RESULTS}" "gs://${BUCKET}/${KEY}" >/dev/null
echo "==> Published. List runs for this pair:"
echo "    gcloud storage ls gs://${BUCKET}/runs/${PAIR}/"
