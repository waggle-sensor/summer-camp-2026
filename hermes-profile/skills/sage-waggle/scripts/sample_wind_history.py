#!/usr/bin/env python3
"""Sample a long, intermittent Sage measurement history into daily min/mean/max
WITHOUT bulk-downloading it. Generic over vsn/measurement.

Two-phase, cheap:
  1) map active days: one head:1 probe per calendar day (skips empty days)
  2) daily stats: 8 short even windows/day (head:40), thread-pooled

Drops missing sentinels (-9999.9 WXT536, -130.11 BME680, anything < -100).
Prints /tmp/<vsn>_<safe-name>_daily.json = [{date,mean,min,max,n}, ...].

Usage:  python3 sample_wind_history.py W08B wxt.wind.speed 2024-09-01 2026-07-10
Then graph: mean line + min-max band, break the line where gap>2 days (real gaps).
"""
import json, sys, urllib.request, datetime as dt
from concurrent.futures import ThreadPoolExecutor, as_completed

API = "https://data.sagecontinuum.org/api/v1/query"
MISSING = (-9999.9, -130.11)
HOURS = [0, 3, 6, 9, 12, 15, 18, 21]  # even daily sampling (NOT head-from-midnight)


def _post(body, timeout=30):
    req = urllib.request.Request(API, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode()


def has_day(vsn, name, day):
    s = day.isoformat() + "T00:00:00Z"
    e = (day + dt.timedelta(days=1)).isoformat() + "T00:00:00Z"
    try:
        return bool(_post({"start": s, "end": e,
                           "filter": {"vsn": vsn, "name": name}, "head": 1}).strip())
    except Exception:
        return None


def _valid(v):
    return isinstance(v, (int, float)) and v > -100 and all(abs(v - m) > 0.01 for m in MISSING)


def day_stats(vsn, name, day):
    vals = []
    for h in HOURS:
        base = dt.datetime.fromisoformat(day + "T00:00:00") + dt.timedelta(hours=h)
        s = base.strftime("%Y-%m-%dT%H:%M:%SZ")
        e = (base + dt.timedelta(minutes=3)).strftime("%Y-%m-%dT%H:%M:%SZ")
        try:
            for raw in _post({"start": s, "end": e,
                              "filter": {"vsn": vsn, "name": name}, "head": 40}, 25).split("\n"):
                if not raw.strip():
                    continue
                try:
                    v = json.loads(raw).get("value")
                except Exception:
                    continue
                if _valid(v):
                    vals.append(v)
        except Exception:
            pass
    if not vals:
        return None
    return {"date": day, "mean": round(sum(vals) / len(vals), 3),
            "min": round(min(vals), 3), "max": round(max(vals), 3), "n": len(vals)}


def main():
    vsn, name, start, end = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    d, e = dt.date.fromisoformat(start), dt.date.fromisoformat(end)
    days = []
    while d < e:
        days.append(d)
        d += dt.timedelta(days=1)
    active = [x.isoformat() for x in days if has_day(vsn, name, x)]
    print(f"active days: {len(active)}/{len(days)}")
    results = {}
    with ThreadPoolExecutor(max_workers=16) as ex:
        futs = {ex.submit(day_stats, vsn, name, a): a for a in active}
        for f in as_completed(futs):
            r = f.result()
            if r:
                results[r["date"]] = r
    series = [results[k] for k in sorted(results)]
    out = f"/tmp/{vsn}_{name.replace('.', '_')}_daily.json"
    json.dump(series, open(out, "w"))
    if series:
        tot = sum(s["n"] for s in series)
        print(f"first {series[0]['date']}  last {series[-1]['date']}  "
              f"overall_mean {sum(s['mean']*s['n'] for s in series)/tot:.2f}  "
              f"peak {max(s['max'] for s in series):.1f}")
    print("wrote", out)


if __name__ == "__main__":
    main()
