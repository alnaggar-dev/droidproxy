---
name: drop-change
description: Retire a fork customization cleanly — revert its commit(s), delete its .fork/CHANGES.md entry in the same commit, and prove nothing else broke. Run it on audit's DROP CANDIDATES, when upstream merged your PR, or when you no longer want a change.
---

You are on a personal fork. This is the RETIREMENT step — the mirror of `fork-change`: that skill registers a customization, this one removes it so the fork's delta shrinks (the cheapest customization is one you can delete). Follow the Fork Maintenance section of your agent memory (CLAUDE.md or AGENTS.md), Retiring a customization.

Refuse to start if the working tree is dirty, or if a port/unport is in progress (`./.fork/port.sh status`).

Derive the upstream ref ONCE, first — every history command below uses `$UP`, and hardcoding `upstream/main` dies (`bad revision`) on any fork whose upstream default branch is develop/master/…:

```bash
UP="$(awk '!/^[[:space:]]*#/ && NF {print $2; exit}' .fork/UPSTREAM)"; [ -n "$UP" ] || UP="upstream/main"
git rev-parse --verify --quiet "${UP}^{commit}" >/dev/null || echo "STOP: $UP does not resolve — git fetch upstream first"
```

Pick the customization:
- If the user names a slug, use that `## custom: <slug>` entry in `.fork/CHANGES.md`.
- Otherwise run `./.fork/audit.sh` and take its DROP CANDIDATES (`Status:` of `superseded`, `upstreamed`, `applied-upstream`, or a `proposed-upstream` whose PR the author has since merged — check with `gh pr list`). If there are several, list them and ask which one.
- Refuse with a clear message if no candidate is found — tell the user to name a slug or set a retirement `Status:` first.

Order matters when upstream ships the change (your merged PR, or a patch-id hit in audit):
- **Retire FIRST, then port.** Revert your version before porting the upstream commit that carries theirs — the port then applies clean (often as an empty, pointer-only port). Porting first makes upstream's commit conflict with its own twin, and you resolve a conflict that retirement would have dissolved.
- If the port already happened and you resolved toward upstream's version, there may be nothing left to revert — retirement degenerates to deleting the entry plus sweeping any fork-only leftovers (a helper, a test, an asset only your version used). Check each `Touches` path against upstream's copy: `git diff "$UP" -- <path>`.

Find the commits to revert:
- From the entry's `Touches`/`Symbols` paths: `git log --no-merges --reverse "$UP"..custom/main -- <paths>` — then EXCLUDE any commit whose message carries a `Fork-Flow-Port:` / `Fork-Flow-Port-Init:` / `Fork-Flow-Unport:` trailer (those are ports/unports, upstream's changes, not your customization). What remains is yours; confirm the set with the user before reverting — one customization can span more than one commit (the original plus later fixes).
- Detect a MIXED commit BEFORE touching the tree: for each candidate, `git diff-tree --no-commit-id --name-only -r <sha>` — every listed path must be covered by the entry's `Touches`/`Symbols` anchors or be `.fork/CHANGES.md` itself. Any path outside that set means the commit ALSO carries an unrelated customization (the "one squash commit per feature" rule was broken): do NOT revert it whole — stop and tell the user it needs a surgical revert (revert, then re-apply the unrelated part) before retiring.

Execute — one commit, like registration:
- `git revert --no-commit <sha>` for each, NEWEST first. On conflict, resolve toward the CURRENT code as if the customization never existed — later ports may have rewritten the area, so the goal is "gone from today's tree", not a byte-level undo of the old diff.
- DELETE the whole `## custom: <slug>` entry from `.fork/CHANGES.md` in the SAME commit. Delete, don't tombstone: a dead entry's `Verify` would fail the gate (the code it checks is gone), and its anchors would rot into audit noise. History lives in git.
- Commit everything together as `custom: retire <slug> — <one-line why>` (e.g. "upstream ships this since v2.3"). Same-commit means one `git revert` of THIS commit restores the customization, entry and all, if you change your mind.

Gate and close:
- The pre-commit gate fires on this commit AUTOMATICALLY — deleting the entry stages `.fork/CHANGES.md`, which is an integration-gate trigger — and runs `verify.sh --registry`: every REMAINING entry's Verify must still pass, so retiring one customization cannot silently break another that depended on the same code. The hook proves registry survival only; also run the FULL gate yourself: `./.fork/verify.sh` (full; `--registry` plus the repo's own checks if the full toolchain can't run — same fallback rule as fork-change). On an UNWIRED clone (fresh clone that never ran `./.fork/setup.sh`) no hook fires at all: wire it now (`./.fork/setup.sh` — it CHAINS any hook manager the project already uses, so the project's own hooks keep working; note husky-style managers re-point hooks on dependency installs, so re-run setup if verify/port warn), or at minimum run `./.fork/verify.sh --registry` by hand before committing.
- Re-run `./.fork/audit.sh`: expect no orphaned anchors and no new UNREGISTERED files. A leftover file audit flags means the revert missed something fork-only — delete it (or it is genuinely still wanted, in which case it is its own customization: register it with `fork-change`).
- If the retirement clears the way for a port (the upstream-ships-it case), run the `upstream-port` skill now — the backlog commit that motivated this should port clean.

Report: which customization, why retired, commits reverted, conflicts resolved, the CHANGES.md entry removed, verify and audit results, and whether a follow-up port is queued.
