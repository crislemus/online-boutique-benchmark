#!/usr/bin/env python3
"""Render a 2-way processor comparison from captured benchmark evidence.

Platform-agnostic: reads the selected platforms from the metrics snapshot
(produced by run-benchmark.sh), so it works for whichever 2 platforms were
chosen in config/platforms.json.

Reads:  docs/results/metrics-snapshot.json
          { "platforms": ["n2","c3"],
            "labels": {"n2":"Intel ...","c3":"Intel ..."},
            "cpu": {"n2":0.06,"c3":0.04}, "mem": {"n2":..,"c3":..} }
        docs/results/loadgen-<key>.log   (Locust 'Aggregated' line)
Writes: docs/results/chart-cpu.png, chart-cpu-per-req.png, chart-latency.png,
        chart-memory.png

Pure stdlib + matplotlib.
"""
import json
import os
import sys

import matplotlib
matplotlib.use("Agg")  # headless
import matplotlib.pyplot as plt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(ROOT, "docs", "results")
PALETTE = ["#5b8def", "#34a853", "#f9ab00", "#a142f4"]  # up to 4 platforms


def parse_loadgen(path):
    if not os.path.exists(path):
        return None
    agg = None
    with open(path) as f:
        for line in f:
            if line.strip().startswith("Aggregated"):
                agg = line
    if not agg:
        return None
    t = [x for x in agg.replace("|", " ").split() if x]
    try:
        return {"reqs": float(t[1]), "avg": float(t[3]), "median": float(t[6]),
                "rps": float(t[-2])}
    except (IndexError, ValueError):
        return None


def bars(ax, plats, values, title, ylabel, fmt="{:.3f}"):
    ticks = [f"{p}\n({LABELS.get(p, '')})" for p in plats]
    b = ax.bar(ticks, values, color=PALETTE[:len(plats)], width=0.55)
    ax.set_title(title, fontweight="bold")
    ax.set_ylabel(ylabel)
    ax.spines[["top", "right"]].set_visible(False)
    top = max(values) if max(values) else 1
    for bar, v in zip(b, values):
        ax.text(bar.get_x() + bar.get_width() / 2, v + top * 0.02, fmt.format(v),
                ha="center", va="bottom", fontweight="bold")
    ax.set_ylim(0, top * 1.18)


def save(fig, name):
    out = os.path.join(RESULTS, name)
    fig.tight_layout()
    fig.savefig(out, dpi=130)
    plt.close(fig)
    print("wrote", os.path.relpath(out, ROOT))


def delta(plats, vals):
    """Headline: lowest vs highest, lower-is-better."""
    lo_i = min(range(len(vals)), key=lambda i: vals[i])
    hi_i = max(range(len(vals)), key=lambda i: vals[i])
    if vals[hi_i] == 0:
        return ""
    pc = (vals[hi_i] - vals[lo_i]) / vals[hi_i] * 100
    return f"{plats[lo_i]} {pc:.0f}% lower"


def main():
    snap_path = os.path.join(RESULTS, "metrics-snapshot.json")
    if not os.path.exists(snap_path):
        print("no metrics-snapshot.json — run the benchmark first", file=sys.stderr)
        return 1
    s = json.load(open(snap_path))
    plats = s["platforms"]
    global LABELS
    LABELS = s.get("labels", {})
    lg = {p: parse_loadgen(os.path.join(RESULTS, f"loadgen-{p}.log")) for p in plats}

    # 1) CPU cores
    cpu = [s["cpu"][p] for p in plats]
    fig, ax = plt.subplots(figsize=(6, 4.2))
    bars(ax, plats, cpu, f"Workload CPU cores at identical load  ({delta(plats, cpu)})",
         "CPU cores (lower = better)")
    save(fig, "chart-cpu.png")

    # 2) Memory MiB
    mem = [s["mem"][p] / 1048576 for p in plats]
    fig, ax = plt.subplots(figsize=(6, 4.2))
    bars(ax, plats, mem, "Workload memory working set", "MiB", fmt="{:.0f}")
    save(fig, "chart-memory.png")

    # 3) CPU per request + 4) latency (need loadgen rps/latency)
    if all(lg[p] and lg[p]["rps"] for p in plats):
        cpr = [s["cpu"][p] / lg[p]["rps"] for p in plats]
        fig, ax = plt.subplots(figsize=(6, 4.2))
        bars(ax, plats, cpr, f"CPU-seconds per request  ({delta(plats, cpr)})",
             "core-seconds / request (lower = better)", fmt="{:.4f}")
        save(fig, "chart-cpu-per-req.png")

        fig, ax = plt.subplots(figsize=(6, 4.2))
        x = range(len(plats))
        ax.bar([i - 0.2 for i in x], [lg[p]["avg"] for p in plats], width=0.4,
               label="avg", color=PALETTE[:len(plats)])
        ax.bar([i + 0.2 for i in x], [lg[p]["median"] for p in plats], width=0.4,
               label="median", color=PALETTE[:len(plats)], alpha=0.55)
        ax.set_xticks(list(x))
        ax.set_xticklabels([f"{p}\n({LABELS.get(p, '')})" for p in plats])
        ax.set_ylabel("latency (ms, lower = better)")
        ax.set_title("Request latency", fontweight="bold")
        ax.spines[["top", "right"]].set_visible(False)
        ax.legend()
        save(fig, "chart-latency.png")
    else:
        print("loadgen logs missing rps — skipped CPU-per-req & latency charts")
    return 0


if __name__ == "__main__":
    LABELS = {}
    sys.exit(main())
