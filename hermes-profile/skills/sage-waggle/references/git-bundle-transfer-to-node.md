# Getting a NEW private repo onto a node with no GitHub creds

## Symptom

On the node, a fresh clone of a NEW private GitHub repo fails:
```
git clone https://github.com/flint-pete/sage-bioclip2.git
# fatal: could not read Username for 'https://github.com': No such device or address
```
...even though the node CAN `git fetch` an ALREADY-cloned private repo
(`~/AI-projects/sage-yolo2` fetches fine). There is no `gh` and no visible
credential helper on the node — existing clones work off a credential cached at
their original clone time, which a brand-new repo doesn't have.

## Don't debug node-side GitHub auth — transfer via git bundle over ssh

You already have working ssh both ways, so ship the repo directly. A git bundle is
a single file carrying full history + all refs/tags; clone from it, then re-point
origin at GitHub so future `git fetch`/`pull` work (fetch on an existing clone is
fine).

```bash
# on the machine that HAS the repo (e.g. the DGX/dev box):
cd ~/AI-projects/<repo>
git bundle create /tmp/<repo>.bundle --all
scp /tmp/<repo>.bundle USER@node-<VSN>.sage:/tmp/

# on the node:
cd ~/AI-projects
rm -rf <repo>                                   # clear any partial clone
git clone /tmp/<repo>.bundle <repo>
cd <repo>
git checkout master
git remote set-url origin https://github.com/<owner>/<repo>.git   # future pulls
```

Verify: `git log --oneline -1` (matches the source HEAD), `cat VERSION`, key files
present. Then build on the node as usual (native Thor build + k3s side-load).

## Why not just make the repo public first / push differently

You can, but the bundle path is credential-free, works regardless of visibility,
and doesn't force a visibility decision just to deploy. Use it for any new private
repo you need on a node. For repos already cloned on the node, plain
`git pull` works.
