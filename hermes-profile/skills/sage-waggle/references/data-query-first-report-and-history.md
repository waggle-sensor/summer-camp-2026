# Finding when a sensor/measurement FIRST reported (and history probing)

Task class: "when did sensor X first start reporting on node Y?" or bounding the
time range of any measurement — without downloading years of data.

## Key insight: use `head:1`, not a manual binary search

The Sage data API (`POST https://data.sagecontinuum.org/api/v1/query`) supports:
- `head:N` — earliest N values PER SERIES
- `tail:N` — latest N values per series
- `start` / `end` — absolute (`2020-01-01T00:00:00Z`) or relative (`-24h`, `-8760h`)
- `filter` — key/value patterns: `vsn`, `name`, `sensor`, `plugin`, ...

`head:1` over a wide window returns just the earliest record(s) — the server does
the search; you do NOT stream the whole range. This is the efficient equivalent of
a binary search and is usually <1s. Example (earliest over ~5 years):

    curl -s -X POST https://data.sagecontinuum.org/api/v1/query \
      -H "Content-Type: application/json" \
      -d '{"start":"2020-01-01T00:00:00Z","end":"2026-07-09T00:00:00Z",
           "filter":{"vsn":"W08B","name":"env.raingauge.rint"},"head":1}'

Then CONFIRM the lower half is empty (true bisection check):

    # window from epoch-start to the found date should return 0 rows
    curl ... -d '{"start":"2020-01-01T00:00:00Z","end":"<foundDate>T00:00:00Z",
                  "filter":{"vsn":"W08B","name":"env.raingauge.rint"},"head":1}'

If `head:1` ever times out on a giant window, fall back to manual bisection:
probe a mid-point window, present→go earlier, absent→go later, halve each step.

`head:N` returns one row per SERIES, so results are NOT globally time-sorted when
multiple jobs/plugins produced the stream. Pull `head:3` across each candidate
`name`, grep the timestamps, and `sort | head` to get the true earliest.

## PITFALL: a sensor's data name is NOT always its hardware name

`filter:{sensor:"wxt536"}` returned NOTHING for W08B even though the WXT536 is
deployed. The WXT536 (Vaisala weather transmitter) surfaces in the stream as the
`env.raingauge.*` measurements (`env.raingauge.rint`, `.event_acc`, `.total_acc`,
plus `env.pressure`) published by `plugin-raingauge` — with NO `sensor` field in
the meta at all; it's tagged by `plugin`, not `sensor`.

Workflow to find the RIGHT thing to query before searching history:
1. `filter:{vsn:Y}` + `tail:1` over `-24h`, grep distinct `"sensor"` and `"name"`
   values to see what the node actually publishes now.
2. If the hardware-name sensor tag is absent, map the device to its measurement
   names (raingauge → `env.raingauge.*`, BME680 → `env.temperature/…`, etc.) and
   search by `name` instead of `sensor`.
3. One device can feed several measurement names; different streams may have been
   enabled at different times, so first-report can differ per measurement. Ask /
   confirm which stream the user means (rain vs wind vs temp) if it's ambiguous.
4. `tail:1` over `-24h` shows only what's reporting NOW. A stream can be absent
   recently but exist historically — before concluding "no such data," probe the
   full history by `name` with `head:1` per candidate name AND per year.

### WXT536 has MULTIPLE streams with DIFFERENT tags AND different start dates
The same physical WXT536 on one node surfaces as two unrelated-looking families:
- **Rain/pressure**: `env.raingauge.rint`, `env.raingauge.event_acc`,
  `env.raingauge.total_acc`, `env.pressure` — plugin `plugin-raingauge`,
  NO `sensor` field. (On W08B: first reported **2022-07-25**.)
- **Wind (+ temp/RH)**: `wxt.wind.speed`, `wxt.wind.direction` — these DO carry
  `sensor:"vaisala-wxt536"`, `zone:"core"`, plugin `.../waggle-wxt536:*`, and a
  `missing:"-9999.9"` meta field. (On W08B: first reported **2024-09-25** — ~2
  years AFTER the rain stream.)
So "when did the WXT536 first report?" is ambiguous: rain and wind can differ by
years. Always confirm which measurement the user wants and search that name.
To discover wind names when unsure: probe common spellings by `name`+`head:1`
over the full range: `wxt.wind.speed`, `wxt.wind.direction`, `env.wind.speed`,
`env.wind_speed`, etc. — the ones returning rows are real.

## "Real data" vs. bench/pre-deployment data

Users often want the first REAL (pole-mounted) reading, not early bench/test data.
`head:1` gives first-APPEARANCE; judge real-vs-bench by inspecting the boundary:
- plausible values from the first record (realistic ranges, not flatline/garbage),
- dense, continuous cadence from day one (e.g. a record every ~30 s; a full day
  hitting your `head:N` cap = continuous reporting, consistent with live deploy),
- meta may show an older `job`/`plugin` tag early (e.g. `job:"sage",
  plugin:"plugin-raingauge:0.4.1"`) that later switches to
  `job:"Pluginctl", plugin:"waggle/plugin-raingauge:0.4.1"` — that's an
  infra/job-runner change over time, NOT a sensor change (same `node` id).
Caveat to state: cadence+plausibility is inference, not a deployment log. If the
user has the actual install date, compare against it to confirm.

## Worked result (W08B / WXT536, 2026-07)
First `env.raingauge.rint` on W08B: 2022-07-25 00:00:14 UTC (value 0.05 mm), dense
30 s cadence from day one → looks like real deployment data. Nothing before it
(2020→2022-07-24 returned 0 rows).
First `wxt.wind.speed` on W08B: 2024-09-25 (nothing in 2022/2023). Confirms the
rain and wind streams of the same WXT536 started ~2 years apart.

## MISSING-VALUE SENTINELS (must filter before stats/plots)
Sage streams embed sentinels that will wreck means/graphs if not dropped:
- `-130.11` → BME680 sensor not present/attached (env.temperature etc.).
- `-9999.9` → WXT536 "missing"; the value is even declared in `meta.missing`.
Robust filter: drop `v < -100` (or read `meta.missing` and drop exact matches).

## Graphing a long, INTERMITTENT history cheaply (no bulk download)
Sage env streams are ~1–6 Hz → a single day can be ~500k rows; months are millions.
Do NOT pull it all for a graph. Two pitfalls + the working recipe:
- PITFALL: a per-MONTH query with `head:200000` silently TRUNCATES (caps at 200k,
  biased to start-of-month) → wrong daily coverage. Per-DAY queries are NOT capped
  the same way (a day returned 507k rows), but downloading every day is slow
  (~12 s/day × hundreds of days).
- PITFALL: streams are intermittent — many days have 0 rows (plugin off / node
  down). Show these as GAPS, never interpolate across them.
Recipe (see scripts/sample_wind_history.py):
1. Map active days: one `head:1` probe per calendar day (fast, ~1 req/day) →
   list of days that have data; group into contiguous ranges to see the gaps.
2. Daily stats via EVEN sampling: for each active day, hit ~8 short 3-min windows
   spread across the day (00,03,…21h) with `head:40` each, thread-pool the
   requests. ~80k points total across hundreds of days, unbiased (NOT `head:N`
   from midnight, which biases to start-of-day). Compute daily min/mean/max.
3. Plot mean line + min–max band, inserting None breaks where gap >2 days so the
   line/band don't bridge offline periods.
Caveat to state to the user: 8×/day sampling can slightly under-catch a day's true
peak gust vs. using every reading; offer full-resolution for a named window.

matplotlib on PEP-668 hosts: `python3 -m venv /tmp/venv && /tmp/venv/bin/pip
install matplotlib` (don't `--break-system-packages`). Or ship a self-contained
`<canvas>` HTML (no deps) — see scripts/sample_wind_history.py output shape.
