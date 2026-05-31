#!/usr/bin/env python3
"""Render N2-vs-C3 comparison charts from captured benchmark evidence.

Reads:  docs/results/metrics-snapshot.json   (cpu_n2/cpu_c3/mem_n2/mem_c3)
        docs/results/loadgen-n2.log / loadgen-c3.log  (Locust 'Aggregated' line)
Writes: docs/results/chart-cpu.png, chart-cpu-per-req.png, chart-latency.png,
        chart-memory.png

Pure stdlib + matplotlib. Safe to run anywhere matplotlib is installed.
"""
import json
import os
import re
import sys

import matplotlib
matplotlib.use("Agg")  # headless
import matplotlib.pyplot as plt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(ROOT, "docs", "results")

N2_COLOR, C3_COLOR = "#5b8def", "#34a853"  # blue (prev-gen), green (new-gen)
LABELS = ["N2\n(prev-gen Intel)", "C3\n(Sapphire Rapids)"]


def parse_loadgen(path):
    """Return dict with reqs, avg, median, rps from the Locust Aggregated line."""
    if not os.path.exists(path):
        return None
    agg = None
    with open(path) as f:
        for line in f:
            if line.strip().startswith("Aggregated"):
                agg = line
    if not agg:
        return None
    toks = [t for t in agg.replace("|", " ").split() if t]
    # Aggregated reqs fails(%) avg min max med ... rps fails/s
    try:
        return {"reqs": float(toks[1]), "avg": float(toks[3]),
                "median": float(toks[6]), "rps": float(toks[-2])}
    except (IndexError, ValueError):
        return None


def bar(ax, values, title, ylabel, fmt="{:.3f}"):
    bars = ax.bar(LABELS, values, color=[N2_COLOR, C3_COLOR], width=0.55)
    ax.set_title(title, fontweight="bold")
    ax.set_ylabel(ylabel)
    ax.spines[["top", "right"]].set_visible(False)
    top = max(values) if max(values) else 1
    for b, v in zip(bars, values):
        ax.text(b.get_x() + b.get_width() / 2, v + top * 0.02, fmt.format(v),
                ha="center", va="bottom", fontweight="bold")
    ax.set_ylim(0, top * 1.18)


def save(fig, name):
    out = os.path.join(RESULTS, name)
    fig.tight_layout()
    fig.savefig(out, dpi=130)
    plt.close(fig)
    print("wrote", os.path.relpath(out, ROOT))


def pct(n2, c3):
    return f"C3 {(n2 - c3) / n2 * 100:.0f}% lower" if n2 else ""


def main():
    snap_path = os.path.join(RESULTS, "metrics-snapshot.json")
    if not os.path.exists(snap_path):
        print("no metrics-snapshot.json — run the benchmark first", file=sys.stderr)
        return 1
    s = json.load(open(snap_path))
    n2, c3 = parse_loadgen(os.path.join(RESULTS, "loadgen-n2.log")), \
        parse_loadgen(os.path.join(RESULTS, "loadgen-c3.log"))

    # 1) CPU cores
    fig, ax = plt.subplots(figsize=(6, 4.2))
    bar(ax, [s["cpu_n2"], s["cpu_c3"]],
        f"Workload CPU cores at identical load  ({pct(s['cpu_n2'], s['cpu_c3'])})",
        "CPU cores (lower = better)")
    save(fig, "chart-cpu.png")

    # 2) Memory MiB
    fig, ax = plt.subplots(figsize=(6, 4.2))
    bar(ax, [s["mem_n2"] / 1048576, s["mem_c3"] / 1048576],
        "Workload memory working set", "MiB", fmt="{:.0f}")
    save(fig, "chart-memory.png")

    # 3) CPU per request (efficiency headline) — needs loadgen rps
    if n2 and c3 and n2["rps"] and c3["rps"]:
        cpr = [s["cpu_n2"] / n2["rps"], s["cpu_c3"] / c3["rps"]]
        fig, ax = plt.subplots(figsize=(6, 4.2))
        bar(ax, cpr,
            f"CPU-seconds per request  ({pct(cpr[0], cpr[1])})",
            "core-seconds / request (lower = better)", fmt="{:.4f}")
        save(fig, "chart-cpu-per-req.png")

        # 4) Latency (avg + median grouped)
        fig, ax = plt.subplots(figsize=(6, 4.2))
        x = range(2)
        ax.bar([i - 0.2 for i in x], [n2["avg"], c3["avg"]], width=0.4,
               label="avg", color=[N2_COLOR, C3_COLOR])
        ax.bar([i + 0.2 for i in x], [n2["median"], c3["median"]], width=0.4,
               label="median", color=[N2_COLOR, C3_COLOR], alpha=0.55)
        ax.set_xticks(list(x))
        ax.set_xticklabels(LABELS)
        ax.set_ylabel("latency (ms, lower = better)")
        ax.set_title("Request latency", fontweight="bold")
        ax.spines[["top", "right"]].set_visible(False)
        ax.legend()
        save(fig, "chart-latency.png")
    else:
        print("loadgen logs missing rps — skipped CPU-per-req & latency charts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
