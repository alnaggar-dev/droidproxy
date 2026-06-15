# Upstream Port Journal

Short memory for the next port — not a diary. One entry per upstream commit ported onto custom/main (batch a run of trivial clean ports into one entry), appended in port order. See your agent memory (`CLAUDE.md` or `AGENTS.md`), Fork Maintenance section, for the format.

`port.sh` itself appends a SKELETON entry — inside the same port commit — for every conflicted port, every `range` catch-up, and every conflicted revert, with the conflict file list pre-filled and `(fill in)` placeholders for the decisions. Replace the placeholders with the real resolutions (the upstream-port skill says when); even unfilled, the skeleton preserves the one thing nothing else records: WHICH files needed a human decision. Clean single-commit ports get no automatic entry.

Each entry records: the upstream SHA(s) and subject ported, conflicts and how they were resolved, `rerere` replays checked, drift-check verdicts (`Symbols`/`Drift-if`), `merge=ours` decisions, the `verify.sh` result, and any `audit.sh` follow-ups (customizations retired or flagged). The `.fork/UPSTREAM` pointer is the authoritative record of how far you have ported; this journal is the *why*.

<!-- Example:
## 2026-05-29 — ported upstream def5678 "Rework input layout"

Applied: git cherry-pick -x --no-commit def5678; .fork/UPSTREAM -> def5678
Conflicts: RichInput.tsx (useLayout -> useDisplayMode), re-applied horizontal layout
rerere: package.json replay checked, still correct
Drift-check: useDisplayMode orientation kept -> safe
merge=ours: none in this commit
Audit: input-mode customization superseded by an upstream setting -> removed
Verify: ./.fork/verify.sh --registry passed; full verify.sh passed at end of run
-->

---

_No upstream ports yet._
