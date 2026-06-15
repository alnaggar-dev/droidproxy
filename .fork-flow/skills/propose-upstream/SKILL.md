---
name: propose-upstream
description: Send a fork customization to the original author as a clean PR branch — cherry-pick it onto upstream's code without dragging in your other fork changes.
---

You are working on a personal fork. Follow the Fork Maintenance section of your agent memory (CLAUDE.md or AGENTS.md), Proposing a change upstream. This skill promotes a change that already lives on custom/main into a clean pull-request branch off the upstream mirror, so the author sees only that one change on top of their own code — never the rest of your fork.

Refuse to start if the working tree is dirty.

FIRST, derive the upstream base ref ONCE — while still on custom/main, before anything else. Every command below uses `$UP`, and it cannot be re-derived later: after the strip, `.fork/` no longer exists on the PR branch. Hardcoding `upstream/main` here once staged a PR that DELETED the maintainer's own files on a fork whose upstream default branch was `develop` (every `git cat-file -e upstream/main:…` failed for the wrong reason), so this derivation is load-bearing:

  ```bash
  UP="$(awk '!/^[[:space:]]*#/ && NF {print $2; exit}' .fork/UPSTREAM)"   # the ref the fork ports from
  [ -n "$UP" ] || UP="upstream/main"                                      # nothing recorded yet — fall back
  git rev-parse --verify --quiet "${UP}^{commit}" >/dev/null && echo "UP=$UP" || echo "STOP: $UP does not resolve"
  ```

  This must print `UP=upstream/<branch>`. If it prints `STOP`, do NOT continue — fetch upstream (`git fetch --no-tags upstream`), or ask the user which upstream branch PRs target, and re-derive. Run every later command in this same shell so `$UP` stays set.

Hard rule: NEVER merge custom/main (or a branch built on it) into a PR branch. That would carry every fork customization into the author's history. Promotion is always a cherry-pick of only the relevant commits onto the clean upstream mirror (`$UP`) — there is no local clean `main` in this workflow.

Verify the change isn't already upstream before starting: `git fetch upstream`, then refuse only if the entry's `Status` is `superseded`, `upstreamed`, or `applied-upstream` (upstream already has it — nothing to propose). `Status: proposed-upstream` is expected and allowed: it intentionally makes `./.fork/audit.sh` list the entry as a DROP CANDIDATE, so that listing is NOT a reason to stop.

Pick the change:
- If the user names a slug, use that entry in .fork/CHANGES.md.
- Otherwise read .fork/CHANGES.md and take entries with `Status: proposed-upstream`; if there are several, list them and ask which one (one PR branch per customization).
- Refuse with a clear message if no candidate is found — tell the user to mark the entry `Status: proposed-upstream` first, or name a slug.

Find the commits:
- From the chosen entry's `Touches`/`Symbols` paths, find the fork commit(s) that implemented it — scope to your own commits only: `git log --no-merges --reverse "$UP"..custom/main -- <paths>` (`--reverse` gives cherry-pick order; `"$UP"..custom/main` excludes upstream's own history). This range also contains upstream PORT commits (the upstream-port skill / port.sh applies upstream commits onto custom/main) and `port.sh revert` (unport) commits — exclude any whose message carries a `Fork-Flow-Port:` / `Fork-Flow-Port-Init:` trailer (a port) or a `Fork-Flow-Unport:` trailer (an undone port); those are upstream's changes or port-undos, not your customization. (Those trailers are the single, reliable markers — don't rely on a stray `.fork/UPSTREAM` edit.) A pathspec does not follow renames (`--follow` can't take multiple paths), so if a file was renamed since the customization landed, widen the paths or inspect history by hand. Confirm the set with the user before copying — one customization can span more than one commit.
- These commits must be the customization ONLY. Detect a MIXED commit BEFORE branching: for each candidate, `git diff-tree --no-commit-id --name-only -r <sha>` — every listed path must be covered by the entry's `Touches`/`Symbols` anchors or be `.fork/CHANGES.md` itself. Any other path means unrelated fork changes ride along: do not cherry-pick it whole — stop and tell the user it needs splitting first (the change wasn't kept to "the smallest reasonable change").

Build the PR branch:
- Branch off clean upstream: `git checkout -b pr/<slug> "$UP"` (`$UP` from the derivation at the top; if the project's PRs target a different branch than the one the fork ports from, ask the user and set `UP` to that instead). If `pr/<slug>` already exists, you are iterating on an in-flight PR after review feedback — reset it onto fresh upstream instead (`git checkout -B pr/<slug> "$UP"`) and plan to re-push with `--force-with-lease` (below).
- Cherry-pick the commit(s) in order with `git cherry-pick --no-commit <sha>` (run it once per SHA, in order) so you can clean the tree BEFORE committing (avoids a messy amend later) and land one clean upstream-appropriate PR commit — unless the user explicitly wants the individual commits preserved. On conflict, resolve toward upstream's current code (the author wants the change re-expressed on THEIR latest code, not your fork's surroundings); never resolve by pulling in other fork files. Expect `.fork/CHANGES.md` to CONFLICT as "deleted by us" on EVERY pick — a fork-change commit always carries the registry and the PR branch has no `.fork/`; that conflict is normal and is resolved by the strip below (which keeps the file deleted), never by re-adding it.
- Before committing, strip ALL fork-flow bookkeeping from the staged tree AND the worktree — it is fork-only, not the author's concern. One loop handles both kinds of path correctly: a net-new path is removed outright; a path that DOES exist upstream (the memory file, `.gitattributes`) is reset to upstream's copy — never `git rm` those, which would delete the whole file from the PR (you cannot surgically drop just the appended memory section; resetting to upstream's version is the contract):

  ```bash
  for p in .fork .fork-flow .claude/skills .pi/skills .omp/skills .agents/skills .factory/skills .github/workflows/fork-flow-gate.yml CLAUDE.md AGENTS.md .gitattributes; do
    if git cat-file -e "$UP:$p" 2>/dev/null; then
      git restore --staged --worktree --source "$UP" -- "$p"
    else
      git rm -r -q --cached --ignore-unmatch -- "$p" && rm -rf -- "$p"
    fi
  done
  ```

  The `rm -rf` clears worktree leftovers a later `git add -A` would re-leak; those files live safely on custom/main and reappear when you switch back. Note the two branches: a path the AUTHOR also ships (their own CLAUDE.md/AGENTS.md/.gitattributes) is restored to THEIR copy, never `git rm`'d — this is why `$UP` resolving was checked up front: with a bad ref every `cat-file -e` fails and the loop deletes the author's own files from the PR.
- POSTCONDITION — run exactly this, and proceed ONLY on the literal `POSTCONDITION OK` line:

  ```bash
  git rev-parse --verify --quiet "${UP}^{commit}" >/dev/null \
    && leak="$(git diff --cached "$UP" --name-only -- .fork .fork-flow .claude .pi .omp/skills .agents/skills .factory/skills .github/workflows/fork-flow-gate.yml CLAUDE.md AGENTS.md .gitattributes)" \
    && { [ -z "$leak" ] && echo "POSTCONDITION OK" || printf 'STILL LEAKING:\n%s\n' "$leak"; } \
    || echo "POSTCONDITION BROKEN: $UP does not resolve — DO NOT COMMIT OR PUSH"
  ```

  Empty output alone is NOT success: a bad ref makes the diff die (rc 128) and print nothing — that silence is exactly how a broken ref once shipped a maintainer-file-deleting PR. `STILL LEAKING` lines are bookkeeping still headed into the PR — strip and re-check. Then commit the cleaned change with an upstream-appropriate message: do NOT reuse the `custom:` prefix, and do NOT mention `.fork/CHANGES.md`, the registry, or fork bookkeeping — that wording is meaningless to the author. Describe the change as the author's project would.

Verify, push, and open the PR:
- Build/test the change in isolation on the PR branch so the author gets something that stands on its own.
- `git push -u origin pr/<slug>` (first push). If you are updating an in-flight PR branch that already exists on the remote, use `git push --force-with-lease origin pr/<slug>` instead — the open PR updates in place, no new PR needed.
- Draft the PR title and body for the AUTHOR's project (not your fork): a clear title and a body covering what changed, why, and how it was verified. Use upstream-appropriate wording — no `custom:` prefix, no `.fork/CHANGES.md`/registry mentions. Show the draft to the user before opening.
- Open the PR against upstream with the GitHub CLI. Write the body to a temp file (multiline-safe), then: `gh pr create --repo <upstream-owner>/<repo> --base <base-branch> --head <origin-owner>:pr/<slug> --title "<title>" --body-file <body-file>`. Derive `<upstream-owner>/<repo>` and `<base-branch>` from the `upstream` remote, and `<origin-owner>` from the `origin` remote — the `<origin-owner>:` head prefix is required because the branch lives in your fork, not upstream. Print the PR URL that `gh` returns.

Close the loop on custom/main:
- Switch back: `git switch custom/main` (you are on `pr/<slug>` after the push). The skill must end on `custom/main`, never leave the user on the PR branch.
- Make sure the entry in .fork/CHANGES.md is marked `Status: proposed-upstream` (set it if missing) so ./.fork/audit.sh keeps reminding you to retire the customization once the author accepts it. Commit this on custom/main, not on the PR branch.
- Remind the user: when the PR is merged upstream, retire the local customization with the **drop-change** skill BEFORE the next `upstream-port` reaches the merge commit (audit.sh lists it as a DROP CANDIDATE; reverting yours first lets the upstream commit that merged your PR port clean — the change then flows back in through upstream).

Report: which customization, the commits cherry-picked, the PR branch name and push result, any conflicts resolved during cherry-pick, bookkeeping paths excluded, isolated verification result, the opened PR's URL, and the Status/CHANGES.md update on custom/main.
