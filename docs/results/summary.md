# Benchmark results — Online Boutique on N2 vs C3

**Setup:** two identical copies of Online Boutique (v0.10.5), one pinned to each node pool, each
driven by its own Locust loadgenerator with identical config (`USERS=10, RATE=1`). Metrics from
Managed Service for Prometheus (kubelet/cAdvisor); latency/throughput from Locust. Captured
2026-05-31 on GKE `boutique-bench`, `us-central1-a`, on the **Workload-Identity-hardened** cluster
(dedicated `gke-node-sa`; Grafana reads via the `gmp-reader` GSA). PoC snapshot (~10 min soak).

| Metric (workload total) | N2 (Cascade/Ice Lake) | C3 (Sapphire Rapids) | C3 vs N2 |
|---|---|---|---|
| **CPU cores consumed** (10 m avg) | 0.0614 | 0.0467 | **~24% lower** |
| Memory working set | 334 MiB | 330 MiB | ~1% lower (≈ equal) |
| Throughput (Locust, cum. avg) | 2.6 req/s | 2.4 req/s | comparable |
| Median latency | 13 ms | 9 ms | ~31% lower |
| Avg latency | 15 ms | 11 ms | ~27% lower |
| Requests served / failures | 1543 / 0% | 1466 / 0% | both clean |
| **CPU per request** (cores ÷ req/s) | 0.0236 | 0.0195 | **~17% lower** |

## Interpretation

At the same offered load, **C3 (new-gen Sapphire Rapids) consumed ~24% less CPU and served
requests at notably lower latency** than N2 (previous-gen), with equal memory and zero errors.
Normalized as CPU-seconds per request — the cleanest processor-efficiency measure — **C3 is ~17%
more efficient** for this workload. The result direction matched Iteration 1 (run-to-run the CPU
delta sampled ~17–27%).

## Charts (matplotlib)
- `chart-cpu.png` — workload CPU cores, N2 vs C3.
- `chart-cpu-per-req.png` — CPU-seconds per request (the efficiency headline).
- `chart-latency.png` — avg/median request latency.
- `chart-memory.png` — memory working set.

## Raw evidence
- `metrics-snapshot.json` — averaged CPU/memory values.
- `cpu_timeseries.csv` — per-30s CPU cores for both pools over the capture window.
- `loadgen-n2.log`, `loadgen-c3.log` — Locust aggregates.
- Live dashboard: `dashboards/boutique-benchmark.json` (Grafana → `make dashboards`).

## Caveats (honest scope)
- PoC snapshot, single run, light load; not publication-grade. For rigor: multiple averaged runs,
  longer soak, a dedicated isolated `system` pool, a fixed-RPS load tool (k6/Fortio), and identical
  pinned image digests.
- Locust throughput is user-driven (think-time), so req/s is approximate; CPU-per-request is the
  more reliable comparison than raw throughput.
- The **direction** (C3 more efficient, lower latency) was consistent across all windows sampled.
