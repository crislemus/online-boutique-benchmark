# Benchmark summary — n2d vs c3d (AMD Milan vs AMD Genoa)

Identical Locust load (USERS=10, RATE=1) on both copies; CPU/memory averaged over a steady-state
window (Managed Service for Prometheus); latency/throughput from Locust. Captured on the
Workload-Identity-hardened GKE cluster `boutique-bench` in **`us-central1-b`** — the run was moved
off the default `us-central1-a` because the N2 family was stocked out there
(`ZONE_RESOURCE_POOL_EXHAUSTED`); n2d/c3d had capacity in `us-central1-b`.

| Metric (workload total) | n2d (AMD Milan) | c3d (AMD Genoa) | c3d vs n2d |
|---|---|---|---|
| **CPU cores consumed** | 0.0568 | 0.0368 | **~35% lower** |
| Memory working set | 345 MiB | 341 MiB | ~equal |
| Median latency | 12 ms | 8 ms | ~33% lower |
| Avg latency | 14 ms | 10 ms | ~29% lower |
| Throughput (req/s) | 2.0 | 2.4 | higher |
| Requests / failures | 1946 / 0% | 1879 / 0% | both clean |
| **CPU per request** (cores ÷ req/s) | 0.0284 | 0.0153 | **~46% lower** |

## Interpretation

At identical load, **c3d (AMD Genoa, Zen 4) consumed ~35% less CPU than n2d (AMD Milan, Zen 3)** —
and ~46% less CPU per request — with lower latency and higher throughput. This is the largest
generational gap seen across the pairs benchmarked, which is expected: Genoa is roughly two
generations newer than Milan, vs. the adjacent-generation Intel pairs (n2→c3, c3→c4) which showed
smaller deltas.

## Caveats (honest scope)
- PoC snapshot, single short run, light load. Treat the magnitude as **indicative**; average
  several runs for a firm figure.
- Run executed in `us-central1-b` (not the default `-a`) due to a transient capacity stockout —
  same machine types, so the processor comparison is unaffected.

## Artifacts
- `chart-cpu.png`, `chart-cpu-per-req.png`, `chart-latency.png`, `chart-memory.png`
- `metrics-snapshot.json`, `cpu_timeseries.csv`, `loadgen-n2d.log`, `loadgen-c3d.log`, `index.html`
