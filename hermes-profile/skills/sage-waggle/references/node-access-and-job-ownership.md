# Node SSH access, ssh-agent recovery, and SES job ownership

Operational gotchas hit repeatedly when deploying/stopping SES jobs on Sage
nodes from the Flint host. All verified 2026-07-11 (W06C / Grand Teton work).

## SES jobs are OWNER-GATED — you cannot stop another user's job

`sesctl` authorizes write actions against the job **owner**, not just a valid
token. Verified against gojian's job 5317 with a valid beckman token:

- `sesctl ... rm -s <id>`  (suspend) → `400 "user \"beckman\" is not the owner of job \"<id>\""`
- `sesctl ... rm -s --override --force <id>` → `400 "User beckman does not have permission to override to the job"`
  (the `--override` flag itself needs an elevated/admin permission a normal
  token lacks).
- `sesctl ... stat -j <id>` → **works** (you can READ any job, see its Owner).

Consequence: to stop someone else's job, the **owner** must run
`rm -s <id>` then `rm <id>` with THEIR token, or a Sage admin does it. Do NOT
try to route around this — killing the pod on the node (`kubectl delete pod`)
does NOT work either: SES respawns it on the next cron tick (a `* * * * *` job
is back in <60s) because the cloud-side job still exists. Only suspending/
removing the SES job actually stops it.

Even with verbal permission from the owner, the clean path is: owner stops
their job → you launch yours. Don't unilaterally escalate on another user's
long-running production job.

## Node SSH: gateway paths + the ssh-agent trap

Two working access patterns (pick per node):
- Node shell via gateway: `ssh waggle@waggle-dev-node-<vsn>` (e.g.
  `waggle-dev-node-w06c`) — the Peter-Beckman gateway. NO `.sage` suffix.
- `USER@node-<VSN>.sage` — routes through the `vpn.sagecontinuum.org`
  ProxyJump (per ~/.ssh/config `Host *.sage`).

Both authenticate with `~/.ssh/sage_key`, which is **passphrase-protected**.

THE TRAP (cost ~20 min this session): after a power failure / reboot the
ssh-agent dies. Then EVERY node hop falls through to password auth and fails
with `Permission denied (publickey,password)` at `vpn.sagecontinuum.org` or
the gateway. Symptom in a fresh shell: `ssh-add -l` →
`Error connecting to agent: No such file or directory`.

Why it's sneaky: each Hermes `terminal` call is a FRESH shell that does NOT
inherit the SSH_AUTH_SOCK from Pete's interactive session. Even after Pete
re-runs `ssh-add`, your tool shell can't see his agent until you point at it.

Recovery:
1. Pete must run `ssh-add ~/.ssh/sage_key` himself and enter the passphrase —
   you CANNOT (it prompts interactively; you don't hold the passphrase).
2. Find his agent socket and use it inline in every command:
   ```bash
   # newest socket with exactly 1 identity = his fresh add
   for s in $(find /tmp/ssh-* -name 'agent.*' 2>/dev/null); do
     echo "$s -> $(SSH_AUTH_SOCK=$s ssh-add -l 2>/dev/null | grep -c .)"
   done
   export SSH_AUTH_SOCK=/tmp/ssh-XXXX/agent.<pid>   # then ssh works
   ```
   Verify the loaded key fingerprint matches sage_key
   (`ssh-add -l` → ED25519 …HBf9aEQ…). Prefix subsequent node commands with the
   same `export SSH_AUTH_SOCK=...` (a fresh shell each call forgets it).
   Avoid `>> ~/.bashrc` to persist it — trips the dotfile-overwrite guard; just
   re-export inline.

## W06C k3s facts

- kubectl needs sudo on the node: `sudo kubectl get pods -A`.
- Control-plane node label: `<mac>.ws-nxcore` (Ready); `.ws-nxagent` is the
  inactive secondary (NotReady is normal, not a fault).
- One-shot SES pods are INVISIBLE between cron ticks — they fire ~30-60s then
  get GC'd. To read a one-shot's startup log, run a watch loop that polls
  `kubectl get pods -n ses | grep <plugin>` every ~3s and dumps logs the
  instant the pod appears and has logged (see the log-capture loop pattern
  used for birdnet-5680/5681). The data API is the durable proof of publishing;
  pod logs are the only place to see startup detail like geo-filter resolution.
