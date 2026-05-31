# Benchmark results — Online Boutique on N2 vs C3

**Setup:** two identical copies of Online Boutique (v0.10.5), one pinned to each node pool,
each driven by its own Locust loadgenerator with identical config (`USERS=10, RATE=1`).
Metrics from Managed Service for Prometheus (kubelet/cAdvisor); latency/throughput from Locust.
Captured 2026-05-31 on GKE `boutique-bench`, `us-central1-a`. PoC snapshot (~10–15 min soak).

| Metric (workload total) | N2 (Cascade/Ice Lake) | C3 (Sapphire Rapids) | C3 vs N2 |
|---|---|---|---|
| **CPU cores consumed** (10 m avg) | 0.0650 | 0.0477 | **~27% lower** |
| Memory working set | 335.4 MiB | 331.9 MiB | ~1% lower (≈ equal) |
| Throughput (Locust, cum. avg) | 2.30 req/s | 2.80 req/s | ~22% higher |
| Median latency | 13 ms | 10 ms | ~23% lower |
| Avg / Max latency | 16 ms / 488 ms | 12 ms / 580 ms | lower avg |
| Failures | 0% | 0% | — |
| **CPU per request** (cores ÷ req/s) | 0.0283 | 0.0170 | **~40% lower** |

## Interpretation

At the same offered load, **C3 (new-gen Sapphire Rapids) served more requests at lower latency
while consuming meaningfully less CPU** than N2 (previous-gen). Normalized as CPU-seconds per
request — the cleanest processor-efficiency measure — **C3 is ~40% more efficient** for this
workload. Memory footprint is essentially identical (expected: same app/images).

## Evidence files
- `metrics-snapshot.json` — averaged CPU/memory values (raw).
- `cpu_timeseries.csv` — per-30s CPU cores for both pools over the capture window.
- `loadgen-n2.log`, `loadgen-c3.log` — Locust aggregates (throughput, latency, failures).
- Live dashboard: `dashboards/boutique-benchmark.json` (Grafana → `make dashboards`).

## Caveats (honest scope)
- PoC snapshot, single run, light load; not a publication-grade benchmark. For rigor: multiple
  runs, longer soak, a dedicated isolated `system` pool, and identical pinned image digests.
- Locust throughput is user-driven (think-time), so req/s is approximate; CPU-per-request is the
  more reliable comparison than raw throughput.
- Numbers fluctuate run-to-run; the **direction** (C3 more efficient) was consistent across
  windows sampled.
