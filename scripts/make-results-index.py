#!/usr/bin/env python3
"""Generate docs/results/index.html — a simple navigator for a benchmark run.

Shows: execution date, platforms compared (+ labels), benchmark commit/version,
the CPU/memory/latency comparison table, the charts, and links to raw files.
Reads metrics-snapshot.json + loadgen-<key>.log; commit/date from git/env.

Pure stdlib. Safe to run locally or in CI (env overrides keep it deterministic):
  GIT_COMMIT, RUN_TIMESTAMP, CLUSTER, ZONE
"""
import datetime
import html
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(ROOT, "docs", "results")


def git_commit():
    if os.environ.get("GIT_COMMIT"):
        return os.environ["GIT_COMMIT"]
    try:
        return subprocess.check_output(
            ["git", "-C", ROOT, "rev-parse", "--short", "HEAD"],
            stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        return "unknown"


def run_ts():
    return os.environ.get("RUN_TIMESTAMP") or datetime.datetime.now().strftime("%Y-%m-%d %H:%M")


def parse_loadgen(p):
    path = os.path.join(RESULTS, f"loadgen-{p}.log")
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
        return {"reqs": t[1], "avg": t[3], "median": t[6], "rps": t[-2]}
    except IndexError:
        return {}


def main():
    snap_path = os.path.join(RESULTS, "metrics-snapshot.json")
    if not os.path.exists(snap_path):
        print("no metrics-snapshot.json — run the benchmark first", file=sys.stderr)
        return 1
    s = json.load(open(snap_path))
    plats = s["platforms"]
    labels = s.get("labels", {})
    lg = {p: parse_loadgen(p) for p in plats}
    commit, ts = git_commit(), run_ts()
    cluster = os.environ.get("CLUSTER", "boutique-bench")
    zone = os.environ.get("ZONE", "us-central1-a")

    def esc(x):
        return html.escape(str(x))

    rows = ""
    for p in plats:
        m = lg.get(p, {})
        rows += (
            f"<tr><td><b>{esc(p)}</b><br><span class=sub>{esc(labels.get(p, ''))}</span></td>"
            f"<td>{s['cpu'][p]:.4f}</td><td>{s['mem'][p] / 1048576:.0f}</td>"
            f"<td>{esc(m.get('median', '—'))}</td><td>{esc(m.get('avg', '—'))}</td>"
            f"<td>{esc(m.get('rps', '—'))}</td><td>{esc(m.get('reqs', '—'))}</td></tr>")

    # headline CPU delta (lower is better)
    delta = ""
    if len(plats) == 2:
        a, b = plats
        lo, hi = (a, b) if s["cpu"][a] <= s["cpu"][b] else (b, a)
        if s["cpu"][hi]:
            pct = (s["cpu"][hi] - s["cpu"][lo]) / s["cpu"][hi] * 100
            delta = f"<b>{esc(lo)}</b> used <b>{pct:.0f}% less CPU</b> than {esc(hi)} at identical load."

    charts = "".join(
        f'<figure><img src="{c}" alt="{c}"><figcaption>{c}</figcaption></figure>'
        for c in ("chart-cpu.png", "chart-cpu-per-req.png", "chart-latency.png", "chart-memory.png")
        if os.path.exists(os.path.join(RESULTS, c)))

    files = "".join(
        f'<li><a href="{f}">{f}</a></li>'
        for f in ("summary.md", "metrics-snapshot.json", "cpu_timeseries.csv",
                  *(f"loadgen-{p}.log" for p in plats))
        if os.path.exists(os.path.join(RESULTS, f)))

    doc = f"""<!doctype html>
<html lang=en><head><meta charset=utf-8>
<meta name=viewport content="width=device-width, initial-scale=1">
<title>Processor Benchmark Results — {esc(' vs '.join(plats))}</title>
<style>
  body{{font-family:system-ui,Segoe UI,Roboto,sans-serif;margin:2rem auto;max-width:960px;color:#1a1a1a;padding:0 1rem}}
  h1{{margin-bottom:.2rem}} .sub{{color:#666;font-size:.85em}}
  .meta{{background:#f4f6fb;border:1px solid #e0e4ee;border-radius:8px;padding:1rem;margin:1rem 0}}
  .meta b{{display:inline-block;min-width:150px}}
  .headline{{background:#eafbef;border:1px solid #b6e6c4;border-radius:8px;padding:.8rem 1rem;margin:1rem 0}}
  table{{border-collapse:collapse;width:100%;margin:1rem 0}}
  th,td{{border:1px solid #e0e4ee;padding:.5rem .7rem;text-align:right}}
  th:first-child,td:first-child{{text-align:left}} th{{background:#f4f6fb}}
  figure{{margin:0;display:inline-block;width:48%;vertical-align:top}} figure img{{width:100%;border:1px solid #eee;border-radius:6px}}
  figcaption{{color:#666;font-size:.8em;text-align:center}}
  footer{{color:#888;font-size:.8em;margin-top:2rem;border-top:1px solid #eee;padding-top:1rem}}
</style></head><body>
<h1>Online Boutique — Processor Benchmark</h1>
<div class=sub>2-way comparison · identical Locust load · Managed Service for Prometheus + Grafana</div>

<div class=meta>
  <div><b>Execution date</b> {esc(ts)}</div>
  <div><b>Platforms compared</b> {esc(', '.join(f'{p} ({labels.get(p, "")})' for p in plats))}</div>
  <div><b>Benchmark version</b> commit {esc(commit)}</div>
  <div><b>Cluster / zone</b> {esc(cluster)} / {esc(zone)}</div>
</div>

{f'<div class=headline>{delta}</div>' if delta else ''}

<h2>Comparison</h2>
<table>
  <tr><th>Platform</th><th>CPU cores</th><th>Memory (MiB)</th>
      <th>Median lat (ms)</th><th>Avg lat (ms)</th><th>req/s</th><th>Requests</th></tr>
  {rows}
</table>
<div class=sub>Lower CPU at identical load = more efficient. Latency/throughput from Locust.</div>

<h2>Charts</h2>
{charts or '<p class=sub>No charts found.</p>'}

<h2>Raw files</h2>
<ul>{files}</ul>

<footer>
  Generated by scripts/make-results-index.py · PoC snapshot (single short run) — treat deltas as
  indicative. Methodology &amp; caveats in <a href="summary.md">summary.md</a>.
</footer>
</body></html>
"""
    out = os.path.join(RESULTS, "index.html")
    open(out, "w").write(doc)
    print("wrote", os.path.relpath(out, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
