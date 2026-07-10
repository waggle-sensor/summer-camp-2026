# Reolink Camera Focus Control via HTTP API

CLI commands to control zoom and focus on Reolink cameras with motorized lenses.
Uses the Reolink HTTP API. Some cameras require token-based auth (see below).

> **Read this reference BEFORE live-probing the camera.** When a focus/zoom
> command fails, consult the "admin account" and "password encoding" notes here
> first — do not iterate blindly through payload-shape variants against the live
> device. This doc already encodes the answers to the common `-26`/`-7` errors;
> live-probing rediscovers them slowly.
>
> **Tooling note for token flows:** the two-step login (`VAR=$(curl ... Login
> ...)`) can get mangled by output filters when written through file/patch
> tools. If a `TOKEN=$(...)` line comes out corrupted, do the whole login →
> token → command flow in a small **Python** script (urllib) instead of shell —
> it sidesteps the problem entirely. See `reolink-set-focus.sh` for the
> shell-safe version (it splits the curl output into a variable first).

## CREDENTIALS: never guess, never fabricate (hard rule)

The Reolink login has a **lockout counter**: a failed login returns
`rspCode: -7 "login failed"` with `auth_warning_info.remain_times` decrementing
toward an account lock. Every wrong password burns one attempt. Therefore:

- **Do NOT invent, guess, or "try" a password.** If you do not have the real
  admin credential in hand (from the user or a verified node-side secret), STOP
  and ask. A plausible-looking made-up password is a fabrication and it costs a
  lockout attempt — the worst possible way to fail.
- The agent does **not** hold the H00F admin password by default; it is not in
  memory (redacted). Source it from the user or a node secret each time.
- Pass the password via **stdin**, not argv, so it stays out of shell history /
  process args: `printf '%s' "$PW" | ssh node '... read -r P; export
  CAMERA_PASSWORD=$P; ...'`. Redact it in any logged URL (`password=***`).
- The RLC-811A snapshot endpoint is `cmd=Snap` (query-param auth, same as the
  focus API below). A **valid** admin login returns a bare 4K JPEG
  (~1.2 MB, 3840x2160, SOI ffd8 / EOI ffd9) with **no** APP0/APP1/COM segments —
  the camera authors zero metadata, so any provenance must be injected downstream.
  An **invalid** login returns a small JSON error blob, not a JPEG — validate the
  body is a JPEG (SOI/EOI) before saving, so an auth failure never lands on disk.

## Authentication

**Short session** (credentials in URL) — works on some models:
```
http://CAMERA_IP:PORT/api.cgi?cmd=GetZoomFocus&user=admin&password=PASSWORD
```

> **Do NOT percent-encode the password in the query string.** Reolink compares
> the password value literally as it arrives. If you URL-encode punctuation
> (e.g. `!` -> `%21`), the camera sees the literal `%21` and rejects login with
> `rspCode: -7 "login failed"`. Send `!`, etc. raw (wrap the whole URL in
> single quotes so the shell doesn't mangle `!`/`&`). Only escape truly
> URL-breaking chars: space, `&`, `#`, `?`, `+`, `%`.

**Token auth** (required when short session returns "please login first"):
```bash
# Step 1: Get token
curl -s -k "http://CAMERA_IP:PORT/api.cgi?cmd=Login" \
  -d '[{"cmd":"Login","param":{"User":{"userName":"admin","password":"PASSWORD"}}}]'
# Returns: {"value":{"Token":{"leaseTime":3600,"name":"TOKEN_STRING"}}}

# Step 2: Use token in subsequent calls
curl -s -k "http://CAMERA_IP:PORT/api.cgi?cmd=GetZoomFocus&token=TOKEN_STRING" \
  -d '[{"cmd":"GetZoomFocus","action":0,"param":{"channel":0}}]'
```

Token expires after `leaseTime` seconds (typically 3600 = 1 hour).

**Tested**: The RLC-811A on a port-mapped HTTP endpoint (port 80 → 10000)
required token auth — short session returned `rspCode: -6` ("please login
first"). Always try short session first, fall back to token auth.

## Get Current Zoom/Focus Position

```bash
curl -s -k "http://CAMERA_IP:PORT/api.cgi?cmd=GetZoomFocus&token=TOKEN" \
  -d '[{"cmd":"GetZoomFocus","action":0,"param":{"channel":0}}]'
```

## IMPORTANT: Control commands require an ADMIN account

Focus/zoom/PTZ and config writes are **admin-only**. A **guest**-level user can
`GetZoomFocus`, `GetAbility`, `GetUser`, etc. (all reads) but **every write
returns `rspCode: -26 "ability error"`** — regardless of payload shape, `op`
value, or a valid token. This is a *permission* gate, not a payload bug, and it
is the #1 cause of `-26` here.

`GetAbility` shows `permit: 4` for `ptzCtrl`/`supportFocus`/`disableAutoFocus`,
but `permit` is the *admin* capability — it does **not** grant a guest execute
rights. Check the account level with `GetUser`:

```bash
curl -s "http://CAMERA_IP:PORT/api.cgi?cmd=GetUser&token=TOKEN" \
  -d '[{"cmd":"GetUser","action":0,"param":{}}]'
# level: "admin"  -> can control focus
# level: "guest"  -> reads only; StartZoomFocus returns -26 "ability error"
```

**Verified on the H00F hummingcam (RLC-811A):** the `sage` account is *guest*
(reads worked, all focus writes returned `-26`). Logging in as the `admin`
account made the identical `StartZoomFocus FocusPos` return `code: 0`,
`rspCode: 200`, and the lens physically moved (3065 -> 3100 -> 3120, confirmed by
read-back). **Use the admin account for any focus/zoom/PTZ operation.**

## Set Focus to a Specific Position

```bash
curl -s -k "http://CAMERA_IP:PORT/api.cgi?cmd=StartZoomFocus&token=TOKEN" \
  -d '[{"cmd":"StartZoomFocus","action":0,"param":{"ZoomFocus":{"channel":0,"pos":3060,"op":"FocusPos"}}}]'
```

### StartZoomFocus `op` Values

| op | Description |
|---|---|
| `FocusPos` | Move focus to absolute position (pos=VALUE) |
| `ZoomPos` | Move zoom to absolute position (pos=VALUE) |
| `FocusDec` | Step focus backward |
| `FocusInc` | Step focus forward |
| `ZoomDec` | Step zoom out |
| `ZoomInc` | Step zoom in |

## Disable/Enable Autofocus

```bash
# Disable autofocus (switch to manual focus)
curl -s -k "http://CAMERA_IP:PORT/api.cgi?cmd=SetAutoFocus&token=TOKEN" \
  -d '[{"cmd":"SetAutoFocus","action":0,"param":{"AutoFocus":{"channel":0,"disable":1}}}]'

# Re-enable autofocus
curl -s -k "http://CAMERA_IP:PORT/api.cgi?cmd=SetAutoFocus&token=TOKEN" \
  -d '[{"cmd":"SetAutoFocus","action":0,"param":{"AutoFocus":{"channel":0,"disable":0}}}]'
```

Read the current autofocus state (confirm a disable actually stuck):
```bash
curl -s -k "http://CAMERA_IP:PORT/api.cgi?cmd=GetAutoFocus&token=TOKEN" \
  -d '[{"cmd":"GetAutoFocus","action":0,"param":{"channel":0}}]'
# -> {"value":{"AutoFocus":{"channel":0,"disable":1,"afType":0}}}  (disable:1 = manual)
```

## Enable/Disable Microphone Audio

If audio streams are silent (no background noise at all), the camera mic
may be disabled. Check and enable via the encoding settings:

```bash
# Check audio status (look for "audio": 0 or 1)
curl -s "http://CAMERA_IP:PORT/api.cgi?cmd=GetEnc&user=USER&password=PASS" \
  -d '[{"cmd":"GetEnc","action":0,"param":{"channel":0}}]'

# Enable audio
curl -s "http://CAMERA_IP:PORT/api.cgi?cmd=SetEnc&user=USER&password=PASS" \
  -d '[{"cmd":"SetEnc","action":0,"param":{"Enc":{"channel":0,"audio":1}}}]'
```

## Workflow: Lock Focus at a Specific Value

1. Login **as the admin account** to get a token (control is admin-only — see
   the "Control commands require an ADMIN account" section above).
2. Read current position: `GetZoomFocus` to see the pos range for your model,
   and validate your target against it (fail-fast on out-of-range).
3. **Disable autofocus: `SetAutoFocus disable:1`** — do this BEFORE setting the
   position so the value LOCKS (see the drift warning below).
4. Set focus: `StartZoomFocus` with `op: "FocusPos"` and desired `pos`.
5. Read back with `GetZoomFocus` to confirm the lens settled near the target.

> **You MUST disable autofocus first to make the value hold.** VERIFIED on the
> RLC-811A (2026-06-29): with autofocus ON, `StartZoomFocus FocusPos` moves the
> lens but the camera re-hunts and the value DRIFTS BACK within seconds
> (observed 3120 -> 3065). With `SetAutoFocus disable:1` sent first, the focus
> LOCKS: `GetAutoFocus` confirms `disable:1` persists, the lens lands exactly on
> target (reads 3080 right after set), then settles ~23 counts low from lens
> back-lash (to ~3057) and HOLDS steady across repeated reads. So: disable-AF is
> the default for "lock focus"; skip it only for a one-time nudge.
>
> Note: `SetAutoFocus` is itself admin-only (returns `-26` as guest), so both
> the disable-AF and the focus-set need the admin account. Do NOT try to fix a
> `-26` by disabling AF as a guest — that also `-26`s. The real gate is admin
> auth; the AF-disable is about making the value STICK, not about the `-26`.
>
> **Back-lash offset:** commanded vs resting focus differs by ~20-25 counts on
> this lens (mechanical, not a bug). Fine for locking a fixed shot; if exact
> positioning matters, command slightly high to compensate.

## Check Available Ports

```bash
curl -s "http://CAMERA_IP:PORT/api.cgi?cmd=GetNetPort&user=USER&password=PASS" \
  -d '[{"cmd":"GetNetPort","action":0,"param":{"channel":0}}]'
```

Returns httpPort, httpsPort, rtspPort (typically 554), rtmpPort, mediaPort,
onvifPort with enable flags.

## Successful Response

```json
[{"cmd":"StartZoomFocus","code":0,"value":{"rspCode":200}}]
```

## Ready-to-use script

A hardened script lives at
`~/AI-projects/sage-yolo/scripts/reolink-set-focus.sh`:

```
./reolink-set-focus.sh [--keep-autofocus] <camera-url> <username> <password> <focus-value>
# e.g. (must be the ADMIN account; do not commit the real password):
./reolink-set-focus.sh http://CAMERA_IP:PORT admin '<ADMIN_PASSWORD>' 3100
```

Flow: reads the live focus range and validates the target (fail-fast if out of
range), logs in for a token, **disables autofocus so the value LOCKS** (default;
`--keep-autofocus` skips this for a one-time nudge), then issues
`StartZoomFocus op=FocusPos`. It sends the password without percent-encoding
password-legal punctuation (see the auth note above). Requires the admin
account — a guest yields `-26 "ability error"`. Exit codes: 0 ok, 1 usage,
2 unreachable, 3 login-failed, 4 out-of-range, 5 focus rejected,
6 disable-autofocus rejected.

## Notes

- The `pos` value is an integer; valid range depends on camera model
- Use `-k` flag with curl for cameras using self-signed HTTPS certificates
- Channel 0 = main channel; for NVR setups, increment for additional cameras
- Source: Reolink Camera HTTP API User Guide v8 (section 3.7.12–3.7.13)
