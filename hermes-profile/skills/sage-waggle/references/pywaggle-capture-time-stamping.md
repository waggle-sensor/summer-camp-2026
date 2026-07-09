# pywaggle capture-time filename/record stamping (override the default)

How to make an uploaded object's name prefix + record timestamp reflect CAPTURE
time instead of UPLOAD time. Verified against current pywaggle source
(`src/waggle/plugin/plugin.py`, main branch) 2026-07.

## The mechanism: pywaggle only DEFAULTS the timestamp

`Plugin.upload_file` signature and body:

```python
def upload_file(self, path, meta={}, timestamp=None, keep=False):
    timestamp = timestamp or get_timestamp()   # <-- the hinge
    ...
    # object name = f"{timestamp}-{Path(path).name}"
    # self.__publish("upload", <objname>, meta, timestamp)   # record ts too
```

The `timestamp or get_timestamp()` short-circuit is everything:

- Pass NOTHING (`timestamp=None`) → pywaggle calls `get_timestamp()` =
  `time.time_ns()` **at upload time**. This is the upstream/default behavior and
  is why a delayed upload drifts (object name = upload instant, not capture).
- Pass an EXPLICIT `timestamp=` → the `or` short-circuits and pywaggle uses YOUR
  value verbatim for BOTH the object-name prefix `f"{timestamp}-{name}"` AND the
  published "upload" record's timestamp.

So switching to capture-time is ONE argument — you do NOT bypass or reimplement
pywaggle's naming:

```python
capture_ts = time.time_ns()          # at the shutter, node clock
# ...acquire frame, build basename e.g. v2-<vsn>-<camera>.jpg...
plugin.upload_file(path, meta=meta, timestamp=capture_ts)
# -> object name  <capture_ts>-v2-<vsn>-<camera>.jpg  (prefix = capture time)
```

## Constraints (from pywaggle __publish / valid_meta)

- `timestamp` MUST be an **int in NANOSECONDS ≥ 2000-01-01** (`MIN_TIMESTAMP_NS`)
  or `__publish` raises. Use `time.time_ns()` — never seconds.
- The message `name="upload"` is RESERVED; plugins can't publish it directly.
- `meta` must be a FLAT dict of str→str. A second time (e.g. upload_timestamp)
  must be stringified: `meta["upload_timestamp"]=str(get_timestamp())`. pywaggle
  has exactly ONE native timestamp slot — a two-timestamp scheme lives in meta.
- Server enriches vsn/node/host/job/task/plugin/zone/lat-lon server-side off
  app_id; the plugin only sends name/value/timestamp/meta.

## Local (non-upload) naming

If a producer writes files to a local cache WITHOUT pywaggle (never uploads),
build the full name yourself — `f"{capture_ts_ns}-v2-{vsn}-{camera}.jpg"` — so
the on-disk name matches what the upload path would produce. Both paths converge
on the same capture-ts prefix; the only difference is who writes it (you for the
cache, pywaggle-fed-the-same-ts for uploads).

## Repo layout gotcha

pywaggle source lives under `src/waggle/plugin/plugin.py` (NOT
`waggle/plugin/plugin.py`) on the main branch — the bare path 404s on
raw.githubusercontent.com.
