#!/usr/bin/env python3
"""Query Sage plugin.duration.{inference,loadmodel} for a node over a time
window and plot them (ns->ms), one series per plugin x phase.

Usage:
  # In a venv that has matplotlib:
  #   python3 -m venv ~/AI-projects/.plotvenv
  #   ~/AI-projects/.plotvenv/bin/pip install matplotlib
  #   ~/AI-projects/.plotvenv/bin/python query-and-plot-durations.py --vsn H00F --start -24h

Notes:
  - data.sagecontinuum.org/api/v1/query returns NDJSON (one obj per line).
  - Group series by meta.plugin (full ECR ref); same node runs several plugins.
  - Values are integer NANOSECONDS -> divide by 1e6 for ms.
  - loadmodel fires once per job (re)start; inference is per-cycle -> plot each
    series against its own sample index.
  - Range spans ~3 orders of magnitude (yolo ~22ms .. bioclip loadmodel ~10.4s)
    -> log-Y is the readable default; --linear also emits a linear-Y version.
"""
import argparse, json, urllib.request, os
from collections import defaultdict

API = "https://data.sagecontinuum.org/api/v1/query"

# 3 plugins x 2 phases = 6 distinct colors; solid=inference, dashed=loadmodel
STYLE = {
    "yolo|plugin.duration.inference":    ("#1f77b4", "-",  "yolo inference"),
    "yolo|plugin.duration.loadmodel":    ("#17becf", "--", "yolo loadmodel"),
    "birdnet|plugin.duration.inference": ("#2ca02c", "-",  "birdnet inference"),
    "birdnet|plugin.duration.loadmodel": ("#98df8a", "--", "birdnet loadmodel"),
    "bioclip|plugin.duration.inference": ("#d62728", "-",  "bioclip inference"),
    "bioclip|plugin.duration.loadmodel": ("#ff7f0e", "--", "bioclip loadmodel"),
}
SHORT = {"yolo-object-counter": "yolo", "birdnet-species": "birdnet",
         "bioclip-species-classifier": "bioclip"}


def short(meta_plugin):
    for k, v in SHORT.items():
        if k in meta_plugin:
            return v
    return meta_plugin


def query(name, vsn, start):
    body = {"start": start, "filter": {"vsn": vsn, "name": name}}
    req = urllib.request.Request(API, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=90) as r:
        return [json.loads(l) for l in r.read().decode().splitlines() if l.strip()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vsn", default="H00F")
    ap.add_argument("--start", default="-24h")
    ap.add_argument("--out-prefix", default="sage-plugin-durations")
    ap.add_argument("--linear", action="store_true", help="also emit linear-Y")
    args = ap.parse_args()

    data = {}  # "plugin|var" -> [ms,...]
    for var in ["plugin.duration.inference", "plugin.duration.loadmodel"]:
        recs = defaultdict(list)
        for r in query(var, args.vsn, args.start):
            p = short(r.get("meta", {}).get("plugin", "?"))
            recs[p].append((r["timestamp"], float(r["value"]) / 1e6))
        for p, vals in recs.items():
            vals.sort()
            data[f"{p}|{var}"] = [ms for _, ms in vals]

    for k in sorted(data):
        v = data[k]
        print(f"{k}: n={len(v)} min={min(v):.2f} max={max(v):.2f}")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    def draw(logy, path, title):
        fig, ax = plt.subplots(figsize=(13, 7))
        for k, (c, ls, lab) in STYLE.items():
            if k not in data:
                continue
            v = data[k]
            ax.plot(range(len(v)), v, color=c, linestyle=ls, linewidth=1.1,
                    marker=".", markersize=2.5, label=f"{lab} (n={len(v)})")
        ax.set_xlabel("Sample index (first -> last, per series)")
        ax.set_ylabel("plugin.duration (ms" + (", log" if logy else "") + ")")
        if logy:
            ax.set_yscale("log")
        ax.set_title(title)
        ax.grid(True, which="both", alpha=0.3)
        ax.legend(loc="upper right", fontsize=9, framealpha=0.9)
        fig.tight_layout()
        fig.savefig(path, dpi=130)
        plt.close(fig)
        print("wrote:", path)

    draw(True, f"{args.out_prefix}-logY.png",
         f"{args.vsn} plugin.duration inference & loadmodel ({args.start}) log-Y")
    if args.linear:
        draw(False, f"{args.out_prefix}-linearY.png",
             f"{args.vsn} plugin.duration inference & loadmodel ({args.start}) linear-Y")


if __name__ == "__main__":
    main()
