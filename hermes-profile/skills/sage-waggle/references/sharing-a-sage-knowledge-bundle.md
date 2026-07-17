# Packaging a shareable Sage/Hermes knowledge bundle ("brain transplant")

How to give students/collaborators a starter Hermes setup seeded with accumulated
Sage knowledge — WITHOUT leaking your credentials or 500MB of private sessions.

## The right unit: skills, not a raw ~/.hermes copy

- **Never hand over a profile export or raw `~/.hermes`.** It carries `.env` API
  keys, `auth.json` OAuth tokens, `state.db`/`sessions/` (all your private chats),
  and `memories/` (phone numbers, private emails, node creds). Wrong tool for
  sharing.
- **Skills are the designed sharing format.** Package the shareable skill(s) +
  supporting docs into a git repo, then recipients adopt via a skill tap:
  ```
  hermes skills tap add <org>/<repo>
  hermes skills install <skill-name>
  ```
  Direct `git clone` + `cp -r skills/<name> ~/.hermes/skills/` + `/reload-skills`
  also works.

## What to include

- The unique/authored skill(s) (e.g. `sage-waggle`) — NOT the stock bundled skills
  (recipients already have those on install).
- Relevant design docs under `docs/` (plain Markdown).
- A hand-curated, PII-free `MEMORY.starter.md` (general domain facts only — never a
  copy of your real MEMORY.md).
- A classroom-ready `README.md`: prerequisites, Sage access setup (portal account,
  `portal.sagecontinuum.org/account/access` token, node SSH, `hermes mcp add sage
  --url https://mcp.sagecontinuum.org/mcp`), install, a smoke test, and a guided
  first-task walkthrough.
- A `.gitignore` that guards secrets (`.env`, `auth.json`, `*token*.txt`, `secrets/`).

## Secret scrubbing (the critical, easy-to-underdo step)

- **Scan the WHOLE bundle, not just SKILL.md.** First pass on just SKILL.md looked
  clean; the reference files carried MORE copies of the same live camera password.
  Always sweep `references/`, `templates/`, `scripts/`, and `docs/` too.
- Patterns to grep: the actual camera password, specific camera IP, phone number,
  private email domain, `sage-token.txt` paths, `Bearer <literal>`, `user=sage&
  password=`, and cosmetic leaks like `ssh <you>@node-<VSN>.sage` comments.
- Replace with placeholders (`CAMERA_USER`/`CAMERA_PASSWORD`/`CAMERA_IP:PORT`/
  `<YOUR_SAGE_TOKEN_FILE>`) + a note "get real values from your instructor/node
  owner; never hard-code a credential in a skill or repo."
- **Copy-and-redact** into a staging dir so your working skill keeps its real creds
  for your own use; scrub only the shared copy.
- Re-sweep after scrubbing to confirm 0 real-secret hits before `git init`/push.

## Publish

- `gh repo create <name> --private --source=. --remote=origin --push` (private by
  default for testing; add collaborators with `gh repo add-collaborator`).
- Fill any `<org>` placeholders in the README install commands with the real repo
  path after you know it.
