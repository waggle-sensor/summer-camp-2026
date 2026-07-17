# Reolink native still capture (cmd=Snap) + auth-failure & lockout behavior

Companion to `reolink-focus-control.md`. That ref covers auth/focus/zoom; THIS
one covers grabbing a still image (the "native-still" acquisition path for
image plugins, design 2.3 in image-sampler2). Read this BEFORE live-probing a
Reolink for snapshots — it already encodes the failure modes so you don't burn
login attempts rediscovering them.

## Snapshot endpoint

```
http://CAMERA_IP:PORT/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=<cachebuster>&user=admin&password=CAMERA_PASSWORD
```

- On SUCCESS the body is the **raw JPEG bytes** (starts `FF D8`, ends `FF D9`).
  Save the bytes UNTOUCHED — no decode/re-encode — to preserve any camera
  metadata (Reolink RLC-811A authors NONE; body is a bare JFIF JPEG, no EXIF).
- `rs` is a cache-buster (any changing int, e.g. epoch-ms); Reolink expects it.
- `channel=0` = main channel.
- Same query-param auth rules as focus control: **do NOT percent-encode
  password-legal punctuation** (`!@#...` sent raw → the camera compares
  literally; `%21` → `-7 login failed`). Only escape truly URL-breaking chars
  (space, `&`, `#`, `?`, `+`, `%`). Wrap the URL in single quotes in shell.
- Snapshot/still reads work with the **admin** account (control ops are
  admin-only; reads are broader, but on H00F only admin creds were valid).

## CRITICAL: failure returns JSON, not an image

On ANY error (bad password, wrong channel, etc.) the camera returns a small
**JSON error blob**, HTTP 200, NOT a JPEG. Example (login failure):

```json
[{"cmd":"Snap","code":1,"error":{
    "auth_warning_info":{"remain_times":9,"unlock_time":0},
    "detail":"login failed","rspCode":-7}}]
```

Therefore any snapshot client MUST validate the body is a real JPEG
(`data[:2]==b"\xff\xd8" and data[-2:]==b"\xff\xd9"`) before saving. Saving the
raw response blindly writes a `.jpg` that is actually JSON. (image-sampler2's
`acquire.looks_like_jpeg()` does exactly this check and fails fast.)

## CRITICAL: `remain_times` login lockout — do NOT hammer

Every failed login DECREMENTS `remain_times` (starts at 10). When it hits 0 the
account LOCKS for `unlock_time` seconds. Practical rules:

- If you get `rspCode:-7 "login failed"`, **STOP**. Do NOT retry with guessed
  passwords — each guess costs a `remain_times` and risks locking the admin
  account (which also blocks focus/PTZ/enc control until it unlocks).
- A stale stored password is the usual cause. Get the CURRENT credential from
  the user or a secrets source before trying again; don't iterate.
- The response tells you your budget: check `error.auth_warning_info.remain_times`
  on the first failure and treat a low number as a hard stop.

## Credential hygiene (verified pattern)

Camera passwords must never land in argv / shell history / committed files:

- Pass the password to a remote host via **stdin**, not the command line:
  `printf '%s' "$PW" | ssh host 'read -r P; export CAMERA_PASSWORD=$P; ...'`
  (a here-string/env-prefix on the ssh command puts it in the remote argv).
- In plugin code, read creds from **env vars only** (`CAMERA_USER` /
  `CAMERA_PASSWORD`), never as CLI flags. Address (host/port/channel) can be
  flags with env fallbacks; secrets are env-only.
- **Redact the password when logging the URL** — build a redactor that rebuilds
  the query string by hand (`urlencode` will re-encode the `***` placeholder to
  `%2A%2A%2A`; build `k=***` manually instead).

## H00F hummingcam specifics

- URL: `http://CAMERA_IP:PORT` (port 80 mapped to 10000). Reachable from the
  NODE, not from Flint — run captures on-node (`ssh USER@node-<VSN>.sage`,
  `export XDG_RUNTIME_DIR=/run/user/$(id -u)`).
- Only `admin` creds work. `cmd=Snap` returns a bare 4K JPEG with no metadata.
