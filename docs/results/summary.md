# Benchmark summary — c3 vs c4 (Intel Sapphire Rapids vs Emerald Rapids)

Identical Locust load (USERS=10, RATE=1) on both copies; CPU/memory averaged over a ~10-min
steady-state window (Managed Service for Prometheus); latency/throughput from Locust. Captured on
the Workload-Identity-hardened GKE cluster (`boutique-bench`, `us-central1-a`); c4 on
hyperdisk-balanced, c3 on pd-balanced.

| Metric (workload total) | c3 (Sapphire Rapids) | c4 (Emerald Rapids) | c4 vs c3 |
|---|---|---|---|
| **CPU cores consumed** | 0.0415 | 0.0379 | **~9% lower** |
| Memory working set | 335 MiB | 335 MiB | ~equal |
| Median latency | 9 ms | 8 ms | ~lower |
| Avg latency | 11 ms | 9 ms | ~lower |
| Requests served / failures | 1663 / 0% | 1759 / 0% | both clean |

## Interpretation

At identical load, **c4 (newest-gen Intel Emerald Rapids) consumed ~9% less CPU than c3 (Sapphire
Rapids)** with slightly lower latency and equal memory — a modest, plausible generational gain
between two *adjacent, same-vendor* Intel families (a smaller delta than the cross-generation
n2→c3 jump, as expected).

## Caveats (honest scope)
- PoC snapshot, single ~10-min run, light load. The ~9% CPU delta is real in this sample but close
  enough to run-to-run noise that it should be read as **indicative**, not definitive — average
  several runs for a firm number.
- Locust throughput is user-driven (think-time), so instantaneous req/s is noisy; here the
  **CPU and latency** are the more reliable signals (the derived CPU-per-request chart is sensitive
  to that rps noise on such a small margin).

## Artifacts
- `chart-cpu.png`, `chart-memory.png`, `chart-latency.png`, `chart-cpu-per-req.png`
- `metrics-snapshot.json`, `cpu_timeseries.csv`, `loadgen-c3.log`, `loadgen-c4.log`
