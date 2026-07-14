# Auth API — node manifests & nodes (`auth.sagecontinuum.org`)

Hosted by **[waggle-auth-app](https://github.com/waggle-sensor/waggle-auth-app)** (Django / DRF). Read-only catalog endpoints below are **public** (`IsAuthenticatedOrReadOnly`). LoRaWAN writes, user profiles, and some CRUD routes need auth.

**When to use:** look up a node's VSN, GPS, phase/project, compute boards, and sensors (including camera snapshot URIs on the rich manifest). Prefer **per-VSN** URLs over the full list (full manifests ≈ **2MB+**).

---

## Primary endpoints (camp default)

| Method | URL | Auth | What it returns |
|--------|-----|------|-----------------|
| `GET` | `https://auth.sagecontinuum.org/manifests/` | None | **All** node manifests (~290). Trailing slash on the collection URL. Optional `?project=<name>` (case-insensitive). |
| `GET` | `https://auth.sagecontinuum.org/manifests/<vsn>` | None | **One** rich manifest (slash optional: `/manifests/H00F` or `/manifests/H00F/`). |
| `GET` | `https://auth.sagecontinuum.org/api/v-beta/nodes/` | None | **All** nodes in a flatter beta shape (~290). Filter: `?phase=`, `?project__name=` (comma = OR). |
| `GET` | `https://auth.sagecontinuum.org/api/v-beta/nodes/<vsn>` | None | **One** node in the beta shape (slash optional). |

```bash
# Prefer single-node fetches
curl -sL "https://auth.sagecontinuum.org/manifests/H00F"
curl -sL "https://auth.sagecontinuum.org/api/v-beta/nodes/H00F"

# Optional filters
curl -sL "https://auth.sagecontinuum.org/manifests/?project=SGT"
curl -sL "https://auth.sagecontinuum.org/api/v-beta/nodes/?phase=Deployed&project__name=SAGE"
```

Lookup field for both single-node routes is **`vsn`** (e.g. `H00F`, `W030`), not UUID / MAC.

---

## Manifests vs `api/v-beta/nodes` — which to use

Both list the same fleet (~290 nodes). Pick based on depth:

| Need | Prefer |
|------|--------|
| Camera / sensor **URI**, zone, nested hardware datasheet, tags, LoRaWAN connections, resources | **`/manifests/<vsn>`** (rich) |
| Site / partner / focus / node **type** / modem fields / commission dates / lighter payload | **`/api/v-beta/nodes/<vsn>`** |
| Inventory of every node once | Either list URL — cache; do not re-download mid-loop |

### `/manifests/<vsn>` shape (rich)

Top-level fields: `vsn`, `name` (node id / MAC-style), `phase`, `project`, `address`, `gps_lat`, `gps_lon`, `modem`, `tags`, `computes[]`, `sensors[]`, `resources[]`, `lorawanconnections[]`.

**`computes[]`** example fields: `name`, `is_active`, `serial_no`, `zone`, nested `hardware` (`hardware`, `hw_model`, `capabilities` like `gpu`/`arm64`, RAM flags, datasheet).

**`sensors[]`** example fields: `name`, `is_active`, `scope`, `labels`, `serial_no`, **`uri`** (e.g. Hanwha/Reolink snapshot URL on-node LAN), nested `hardware` (model, manufacturer, capabilities, description, datasheet).

### `/api/v-beta/nodes/<vsn>` shape (flatter)

Top-level: `id`, `vsn`, `name`, `project`, `focus`, `partner`, `type` (e.g. `Blade` / `WSN`), `site_id`, `gps_lat`/`gps_lon`/`gps_alt`, `address`, `location`, `phase`, `commissioned_at`, `registered_at`, `modem_sim` / `modem_model` / `modem_carrier`, `computes[]`, `sensors[]`.

**`computes[]` / `sensors[]`** are **flattened** (no nested `hardware` object, no sensor `uri`): `name`, `is_active`, `hw_model`, `manufacturer`, `capabilities` (+ `serial_no` on computes).

Verified sample (Thor blade `H00F`): manifest returns PTZ sensor with LAN snapshot `uri` and nested Hanwha hardware; beta nodes returns the same camera as a flat sensor without `uri`.

---

## Other useful public routes (same app)

| Method | URL | Notes |
|--------|-----|-------|
| `GET` | `https://auth.sagecontinuum.org/computes/` | All compute boards: `node` (VSN), `name`, `hardware`, `serial_no`, `zone`. |
| `GET` | `https://auth.sagecontinuum.org/sensors/` | Sensor **hardware catalog** (+ `vsns` listing nodes that host each type). Filter: `?project=`, `?phase=`. Lookup by `hardware` slug: `/sensors/<hardware>/`. |
| `GET` | `https://auth.sagecontinuum.org/node-builds/` | Build/BOM-ish records: `vsn`, `type`, `project`, camera slots (`top_camera`, …), modem flags. Lookup: `/node-builds/<vsn>/`. |

---

## Auth-required / sensitive (know they exist)

Do **not** treat these as anonymous camp APIs. Source: [waggle-auth-app](https://github.com/waggle-sensor/waggle-auth-app).

| URL pattern | Notes |
|-------------|-------|
| `/lorawandevices/`, `/lorawanconnections/`, `/lorawankeys/`, `/sensorhardwares/` | Need credentials; connections keyed by `<node_vsn>/<deveui>`. |
| `/users/`, `/users/<username>`, `/users/<username>/access`, `/projects/`, `/token` | Account / portal token machinery. |
| `/nodes/<vsn>/users`, `/nodes/<vsn>/authorized_keys` | Node SSH access listings (public-key material). Avoid dumping large key lists into chat unless the user asked. |

Portal tokens: `https://portal.sagecontinuum.org/account/access` → `Authorization: Bearer <token>`.

---

## Agent usage notes

1. Resolve “what cameras / GPS / hardware does VSN X have?” → `GET /manifests/<vsn>` first.
2. Resolve “site / partner / blade type / focus?” → `GET /api/v-beta/nodes/<vsn>`.
3. Never pull `/manifests/` full list for a one-node question.
4. Trailing slash: collection `/manifests/` needs it; single-VSN works with or without.
5. Implementation reference: `manifests/urls.py` + `ManifestViewSet` / `NodesViewSet` in the auth-app repo.
