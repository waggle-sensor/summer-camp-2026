# Reolink Camera: Snapshot Fetch, Auth & EXIF Findings

Companion to `reolink-focus-control.md`. Covers grabbing a still image, the auth
model, and the empirical metadata finding. Camera used: Reolink RLC-811A
("hummingcam") at `CAMERA_IP:PORT`, reachable only from the node over the
wg-sage WireGuard tunnel (NOT from Flint/laptop directly).

## Grab a snapshot (HTTP CGI)

```
curl -s -o /tmp/snap.jpg \
  "http://CAMERA_IP:PORT/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=probe&user=<USER>&password=<PW>"
```
- `channel=0` = main sensor; `rs=<anything>` is a cache-buster.
- Returns a real ~1.7 MB 3840x2160 JPEG on success (first bytes `ff d8`).
- On auth failure returns **JSON** (~248 bytes), `code:1`, `error.rspCode:-7`,
  `detail:"login failed"`, with a decrementing `remain_times` lockout counter.
  `file snap.jpg` says "JSON text data" not "JPEG image data" → auth failed.

## Auth model (learned the hard way)

- Query-param auth works for READS/Snap **when the credentials are valid**.
- **Credentials can change out from under you.** After the camera was
  "fixed"/rebooted, the previously-working `sage`/`CAMERA_PASSWORD=GUEST` guest AND
  `admin`/`SageRoot=ADMIN` both returned `-7`. The actually-working admin login
  was `admin` / `SageRoot` (password had changed). ALWAYS confirm current creds
  with the owner before assuming; don't trust stale memory entries blindly.
- `rspCode -7 "login failed"` = bad username/password (credential rejection).
  Distinct from `-26 "ability error"` = valid login but insufficient permission
  (guest trying a control write; needs admin — see focus ref).
- **STOP retrying on -7.** `remain_times` counts down (10→9→8…) toward a lockout.
  A few probes are fine; loops are not.

## `-7` is NOT always a shell-encoding problem

Prior memory said `-7` = percent-encoding the `!` (`%21`). That IS one cause, but
this session `-7` was a genuine credential change. Ruled out shell mangling by:
writing the exact curl to a script file on the node and running `bash file.sh`
(no interactive interpolation) — the `!` reached curl verbatim and STILL got -7.
So: -7 → first suspect wrong/changed credentials, THEN encoding.

## SSH + password-with-`!` pitfalls (cost real time)

Passing `cmd ... password=CAMERA_PASSWORD=GUEST ...` through
`ssh node 'curl "...!..."'` risks the `!` being altered by bash history
expansion / nested-quote mangling. Robust patterns:
- Write the command/script to a local file, `scp` it to the node, run it there.
- Or do the whole request in Python on the node (`urllib.request`) built from
  plain string vars — no shell quoting of the password at all.
- Do NOT `%`-encode the `!` in the query string (that path gives its own -7).

## EMPIRICAL: this Reolink writes ZERO image metadata

Pulled a best-case camera-authored JPEG via `cmd=Snap` (admin) and scanned every
JPEG marker segment in the raw bytes. Result: **DQT → SOF0 → DHT → SOS only.**
No APP0/JFIF, no APP1/EXIF, no APP1/XMP, no COM comment. Pillow: "no EXIF IFD".
- So there is NOTHING to "preserve" from this camera — not via RTSP (OpenCV
  strips it) and not even via HTTP snapshot (the file is bare).
- Design consequence for plugins: **author your own EXIF/provenance**; treat
  camera-supplied EXIF as "preserve-if-present" (defensive — some Axis/Hikvision/
  ONVIF cams DO embed it), not as a given. Don't assume any camera metadata exists.

## No exiftool on the node

The Thor node has python3 but NOT exiftool/identify/exiv2. Inspect JPEG metadata
with a Python marker scan (walk `0xFF` segments up to SOS `0xDA`) and/or Pillow
`Image.getexif()` — don't rely on exiftool being installed.
