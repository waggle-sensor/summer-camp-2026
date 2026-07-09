# Linking a downloaded object back to its event-log record + timestamp uniqueness

Verified against the live Sage data API (2026-07-03, 24h fleet-wide `upload`
records) and pywaggle `main` source. Use this when you need to (a) recover
provenance for a downloaded image/file, (b) reason about whether a timestamp is a
safe join key, or (c) diagnose coarse/duplicated upload timestamps.

Companion: `pywaggle-upload-naming-and-timestamps.md` (how objects are named and
what metadata is plugin-side vs server-injected). This file is the CONSUMER /
forensic side.

## What a bare downloaded JPG tells you (almost nothing)

`imagesampler` (and any plugin using `ImageSample.save()`) writes via
`cv2.imwrite()`, which encodes **raw pixels only — NO EXIF, NO XMP, NO comment**.
So from a downloaded `.jpg`:
- From the BYTES: only image dimensions/channels (JPEG SOF header) + generic
  JFIF. Zero application provenance (no timestamp/camera/GPS/make/model).
- From the FILENAME `1783082577307441180-sample.jpg`: the prefix is the
  nanosecond-epoch RECORD timestamp (same value as the event record's
  `timestamp`). This is the ONLY provenance the object itself carries.
- From the full OBJECT-STORE URL (if you kept it, not just the file):
  `https://storage.sagecontinuum.org/api/v1/data/<JOB>/<PLUGIN-VERSION>/<NODE_ID>/<TS>-<FILENAME>`
  — the path encodes job, plugin+version, node id, timestamp, filename. A bare
  file with no path has lost all of that except the timestamp prefix.

Design implication for any plugin you build: to make files self-describing,
embed provenance as EXIF/XMP (immutable capture facts) since cv2 writes none.

## The `upload` event record = where provenance lives

Every uploaded object has a companion `name="upload"` record. Live field set:
```json
{"timestamp":"...Z","name":"upload",
 "value":"https://storage.sagecontinuum.org/.../<TS>-<filename>",
 "meta":{"filename":"...","vsn":"H00F","node":"00004cbb...","host":"...agx-thor",
         "job":"...","task":"...","plugin":"registry.../...:VER","zone":"core"}}
```
Plugin-supplied custom keys seen in the wild: `camera, common_name, confidence,
detections, top_class, top_species`. (vsn/node/host/job/task/plugin/zone are
server-injected — see companion ref.)

## Reverse-lookup recipe: filename → event record (VERIFIED)

The filename timestamp prefix IS the record timestamp, so:
1. Split filename on first `-`: `1783082577307441180` + `sample.jpg`.
2. Convert prefix ns→UTC: `int(prefix)/1e9` → ISO time.
3. Query `name="upload"` in a tight window (±2 s absorbs sub-second slack):
   ```
   POST https://data.sagecontinuum.org/api/v1/query
   {"start":"<t-2s>","end":"<t+2s>","filter":{"name":"upload"}}   # add "vsn" if known
   ```
4. Match the record whose `value` ENDSWITH your object name.
Caveat: works only if the file still has its timestamp prefix (a renamed bare
file breaks the bridge).

## Timestamp uniqueness — ns ALONE is NOT a safe key (empirical)

Tested against 24h fleet-wide `upload` records (20,375 records, 58 nodes):
- `(vsn, ns)` → **760 same-node collisions + 695 cross-node** shared ns. NOT unique.
- `(vsn, ns, filename)` → **0 collisions** (unique in practice across the fleet).
- `(vsn, full-object-name)` i.e. `(vsn, "<ns>-<filename>")` → 0, even across
  different plugins.

Why same-node ns collisions happen:
1. **Batch uploads sharing one timestamp** — a plugin passes the same
   `timestamp=` to multiple `upload_file()` calls in one cycle (e.g. mobotix-scan
   emitting jpg+plot+csv+nc+raw at one ns; they differ only by filename).
2. **Coarse clocks / coarse stamping** — see next section.

Object-store survives on FULL-PATH uniqueness (job/plugin-ver/node/ns-filename),
not on ns. The uniqueness problem is purely for a DOWNLOADED bare file that lost
its path.

Rule of thumb: never key a file↔record link on ns alone. Use `vsn` +
per-artifact-varying filename. Even `(vsn, ns, filename)` is unique in PRACTICE,
not by CONSTRUCTION — a plugin that uses a CONSTANT filename (imagesampler's
`sample.jpg`) for multi-stream/same-second captures can self-collide. For
guaranteed uniqueness add a per-capture token: monotonic sequence, UUID, or the
content SHA (pywaggle already computes a sha1 for on-node staging but does not
surface it into the object name or record meta).

## Diagnosing coarse/duplicated timestamps (trailing-zero technique)

To find who is stamping at less-than-ns resolution: for each `upload` record,
count trailing zeros of the ns prefix (0 = full resolution; 9–10 = whole second,
verify with `ns % 1_000_000_000 == 0`). Group by `meta.vsn`, then by
`meta.plugin`.

Key diagnostic move — DON'T assume "coarse stamps ⇒ bad node clock." Check
whether OTHER plugins on the SAME node emit full-resolution ns in the same
window. If they do, the node clock is fine and the coarseness is a PLUGIN
provenance choice, not an OS/NTP fault. (2026-07-03: W096 showed whole-second
stamps; but imagesampler + 4 other plugins on W096 emitted full-res ns, so the
clock was fine — the whole-second stamps came solely from `file-forager`, which
stamps uploads with the source file's second-resolution mtime and reuses that
one second across multiple artifacts per cycle.)

Two upstream concerns to raise when you find this pattern:
- Uniqueness: coarse + reused timestamps produce same-(vsn, ns[, filename])
  collisions that break consumer file↔record linking. Recommend per-artifact
  unique tokens so `(vsn, ns, token)` is unique by construction.
- Semantic clarity: a source-file mtime masquerading as capture/upload time.
  Argues for the explicit two-timestamp convention (source vs capture vs upload)
  instead of overloading the single record timestamp.
