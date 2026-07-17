#!/usr/bin/env python3
"""
Quick Sage data query — works without sage-data-client installed.
Uses the public REST API directly via urllib.

Usage: python3 query-data.py [--start -1h] [--name env.temperature] [--vsn W030] [--tail 10]
"""
import argparse
import json
import urllib.request


def query_sage_data(start="-1h", name=None, vsn=None, sensor=None, tail=5):
    url = "https://data.sagecontinuum.org/api/v1/query"
    body = {"start": start, "tail": tail}
    if name:
        body["filter"] = {"name": name}
        if vsn:
            body["filter"]["vsn"] = vsn
        if sensor:
            body["filter"]["sensor"] = sensor

    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=30) as resp:
        lines = resp.read().decode().strip().split("\n")
        return [json.loads(line) for line in lines if line.strip()]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Query Sage data API")
    parser.add_argument("--start", default="-1h")
    parser.add_argument("--name", default=None, help="Measurement name filter")
    parser.add_argument("--vsn", default=None, help="Node VSN filter (e.g. W030)")
    parser.add_argument("--sensor", default=None, help="Sensor hardware filter")
    parser.add_argument("--tail", type=int, default=5)
    args = parser.parse_args()

    records = query_sage_data(args.start, args.name, args.vsn, args.sensor, args.tail)
    for r in records:
        ts = r.get("timestamp", "?")
        name = r.get("name", "?")
        val = r.get("value", "?")
        meta = r.get("meta", {})
        vsn = meta.get("vsn", "?")
        print(f"{ts}  {vsn:>5s}  {name:30s}  {val}")
