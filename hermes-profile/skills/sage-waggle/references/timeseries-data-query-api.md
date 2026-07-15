# Timeseries data query API (`data.sagecontinuum.org`)

Public endpoint for **scalar / event timeseries** that Sage nodes and plugins publish via `plugin.publish()` → Beehive. No auth required for typical public science data.

**Docs:** [Access and use data](https://sagecontinuum.org/docs/tutorials/accessing-data) · client: [sagecontinuum/sage-data-client](https://github.com/sagecontinuum/sage-data-client)

---

## Endpoint

| | |
|--|--|
| **URL** | `POST https://data.sagecontinuum.org/api/v1/query` |
| **Auth** | None (public) |
| **Body** | JSON: `start` (required), optional `end` / `head` / `tail`, `filter` object |
| **Response** | **NDJSON** — one JSON object per line (not a JSON array) |

`start` / `end` accept relative windows (`-30m`, `-1h`, `-7d`) or absolute timestamps.

Common **filter** keys (pattern match; regex / wildcards allowed):

| Filter | Meaning | Example |
|--------|---------|---------|
| `plugin` | Source plugin image / name | `".*plugin-iio.*"` |
| `name` | Measurement topic | `"env.temperature"`, `"env.count.*"` |
| `vsn` | Node short ID | `"H00F"`, `"W030"` |
| `sensor` | Hardware / sensor id | `"bme680"` |

Large files (images, audio) are **not** in this timeseries DB — only metadata/pointers. Blobs live on object storage (see upload/provenance skill refs).

---

## Example — all recent samples from `plugin-iio`

### curl

```bash
curl https://data.sagecontinuum.org/api/v1/query \
  -d '{"start":"-30m","filter":{"plugin":".*plugin-iio.*"}}'
```

(`curl -d` sends POST. Add `-s` to silence progress.)

### Python (`sage_data_client`)

```python
import sage_data_client

df = sage_data_client.query(
    start="-30m",
    filter={
        "plugin": ".*plugin-iio.*",
    },
)
# DataFrame columns typically include: timestamp, name, value, and meta
# (vsn, node, plugin, sensor, …)
```

Install: `pip install sage-data-client`

---

## More query shapes

```bash
# By node + measurement
curl -s -X POST https://data.sagecontinuum.org/api/v1/query -d '{
  "start": "-1h",
  "filter": {"vsn": "H00F", "name": "env.count.*"}
}'

# Limit to last N samples per series
curl -s -X POST https://data.sagecontinuum.org/api/v1/query -d '{
  "start": "-1h",
  "tail": 5,
  "filter": {"name": "env.temperature", "sensor": "bme680"}
}'
```

```python
import sage_data_client

df = sage_data_client.query(
    start="-1h",
    filter={"name": "env.temperature", "vsn": "W030"},
)
```

Without `sage_data_client`, use skill script `scripts/query-data.py` (urllib → same HTTP API).

---

## Agent tips

1. Prefer a **narrow** `filter` (`plugin` and/or `vsn` + `name`) — wide fleet queries are huge.
2. Plugin names in Beehive often include registry path/version → use a regex like `".*plugin-iio.*"` rather than an exact string.
3. Empty result ≠ node dead: check window (`start`), filter spelling, and whether the plugin actually `publish()`ed (uploads alone do not create timeseries rows).
4. Parse responses as **NDJSON**, line by line.
