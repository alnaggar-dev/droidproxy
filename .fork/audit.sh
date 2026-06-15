#!/usr/bin/env bash
# .fork/audit.sh — periodic fork-health check (see Fork Maintenance in your CLAUDE.md/AGENTS.md).
#
#   ./.fork/audit.sh [--deep] [upstream-ref]
#
# Default upstream-ref: the ref RECORDED in .fork/UPSTREAM (what you actually port
# from), falling back to upstream/main only when none is recorded. Hardcoding
# upstream/main here made the bare call die (`not a commit`) on every fork whose
# upstream default branch is develop/master/… — a large share of real targets.
#
# --deep forces the full patch-id scan (section 5) even on a huge unported backlog;
# without it the scan is skipped past FORK_AUDIT_PATCHID_MAX commits (default 200).
#
# A commit-by-commit fork never replays your patches, so nothing naturally tells you
# a customization has gone stale. This surfaces these things and decides nothing:
#   0. fork delta: how many existing upstream files you edit -> conflict surface
#   0b. merge=ours divergence: what each pin currently hides vs the ported upstream
#   1. registry anchors (Touches/Symbols paths) that no longer exist -> orphaned
#   2. files your fork's own commits changed that no entry registers  -> unregistered
#      (still-tracked files are actionable; paths since gone upstream-and-here are
#       listed once as historical, never as work)
#   3. each entry's Status: + a DROP CANDIDATES list             -> retirement view
#   4. upstream commits since .fork/UPSTREAM you have NOT ported    -> your backlog
#   5. patch-id matches: customizations upstream may have reimplemented
# Scope: the base is the .fork/UPSTREAM pointer (the last ported upstream commit),
# falling back to merge-base(HEAD, upstream) on a fork that hasn't ported yet. 0
# looks at edits since that base; 2 looks at your own (non-port) commits in
# base..HEAD; 4 looks at upstream commits after the pointer.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Shared parsing/matching helpers (split_field, symbol_path, glob_match,
# registry_paths, …) — one copy for all scripts, see .fork/lib.sh.
# shellcheck source=/dev/null
. .fork/lib.sh

# --deep: force the full patch-id scan regardless of backlog size (see section 5).
deep=0
if [ "${1:-}" = "--deep" ]; then
	deep=1
	shift
fi
upstream="${1:-}"
if [ -z "$upstream" ]; then
	upstream="$(upstream_pointer_ref)"
	[ -n "$upstream" ] || upstream="upstream/main"
fi
git rev-parse --verify --quiet "${upstream}^{commit}" >/dev/null ||
	{
		echo "error: not a commit: $upstream (add the upstream remote and fetch? or pass the ref explicitly)" >&2
		exit 2
	}
# Base = the last ported upstream commit (.fork/UPSTREAM), or merge-base as a fallback
# on a not-yet-ported fork. A NON-EMPTY pointer that does not resolve is a HARD ERROR
# (upstream_base exits 3) — we propagate it rather than audit against a lie.
base="$(upstream_base "$upstream")" || exit $?

# --- pointer consistency (is the pointer telling the truth?) -----------------
# The pointer REPLACES merge ancestry, so its honesty is load-bearing. Surface (decide
# nothing) when it looks wrong: not an ancestor of the target upstream (a force-push or
# the wrong line), a retarget (you passed a different --upstream than was recorded),
# the NEWEST reachable port trailer disagreeing with the pointer file, a NON-port commit
# that changed the pointer SHA, or an out-of-line port history (a later port UNRELATED to
# an earlier one; a strictly-backward move is already refused at port time, so only an
# unrelated port surfaces here).
changes=".fork/CHANGES.md"
printf '== fork audit vs %s (base %s) ==\n' "$upstream" "$(git rev-parse --short "$base")"
kv="$(kit_version)"
if [ -n "$kv" ]; then
	printf 'kit: fork-flow v%s  (run the kit installer --check to compare, --update to refresh)\n' "$kv"
else
	printf 'kit: fork-flow unversioned  (re-run the kit installer to stamp .fork/VERSION + adopt managed blocks)\n'
fi

ptr="$(upstream_pointer)"
ptr_ref="$(upstream_pointer_ref)"
printf '\n== pointer consistency (.fork/UPSTREAM honesty) ==\n'
if [ -z "$ptr" ]; then
	printf '  (no pointer set yet — base is merge-base(HEAD, %s))\n' "$upstream"
else
	printf '  pointer: %s (recorded ref: %s)\n' "$(git rev-parse --short "$ptr")" "${ptr_ref:-none}"
	if [ -n "$ptr_ref" ] && [ "$ptr_ref" != "$upstream" ]; then
		printf '  RETARGET: recorded ref %s != audited ref %s (backlog/below may mislead)\n' "$ptr_ref" "$upstream"
	fi
	if git merge-base --is-ancestor "$ptr" "$upstream" 2>/dev/null; then
		printf '  OK: pointer is an ancestor of %s\n' "$upstream"
	else
		printf '  WARNING: pointer is NOT an ancestor of %s — force-push or wrong branch?\n' "$upstream"
	fi
	# Newest IN-EFFECT port trailer (anywhere reachable from HEAD, not just HEAD) vs the
	# pointer file. After a port you usually add custom commits, so HEAD is typically NOT a
	# port; checking only HEAD would let an ordinary commit advance .fork/UPSTREAM to a
	# bogus SHA unseen. A `port.sh revert` (Fork-Flow-Unport) rewinds the pointer, so the
	# reverted port's trailer is STALE and must be skipped. Walk newest-first: an Unport(X)
	# cancels the next OLDER Port(X) we meet (re-port, being newer, is seen first and wins);
	# the first port/init trailer NOT so cancelled is in effect and must name the pointer.
	newest_port=""
	newest_tr=""
	pending="" # SHAs of unports awaiting their (older) matching port, newline-separated
	while IFS= read -r sha; do
		[ -z "$sha" ] && continue
		ut="$(unport_trailer_sha "$sha")"
		if [ -n "$ut" ]; then
			ut="$(git rev-parse "$ut" 2>/dev/null || printf '%s' "$ut")"
			pending="${pending:+$pending
}$ut"
			continue
		fi
		pt="$(port_trailer_sha "$sha")"
		[ -z "$pt" ] && continue
		pt="$(git rev-parse "$pt" 2>/dev/null || printf '%s' "$pt")"
		if printf '%s\n' "$pending" | grep -Fxq "$pt"; then
			# this port was reverted by a (newer) unport — drop one pending and skip it
			pending="$(printf '%s\n' "$pending" | grep -vFx "$pt" || true)"
			continue
		fi
		newest_port="$sha"
		newest_tr="$pt"
		break
	done < <(git log --format='%H' HEAD 2>/dev/null || true)
	if [ -z "$newest_port" ]; then
		printf '  WARNING: pointer is set but NO reachable IN-EFFECT %s trailer — hand-edited?\n' "$PORT_TRAILER"
	elif [ "$(git rev-parse "$newest_tr" 2>/dev/null)" != "$(git rev-parse "$ptr" 2>/dev/null)" ]; then
		printf '  WARNING: newest port trailer (%s in %s) != pointer file (%s) — .fork/UPSTREAM edited after the last port?\n' "$(git rev-parse --short "$newest_tr")" "$(git rev-parse --short "$newest_port")" "$(git rev-parse --short "$ptr")"
	fi
	# Consecutive ports should stay on the same upstream line. A strictly-backward move
	# is already refused at port time (port.sh assert_forward), so here we flag only a
	# port UNRELATED to the previous one (neither is an ancestor of the other) — e.g.
	# hand-edited history or a cross-branch port. Report the first such inversion only.
	# An INIT trailer (`port.sh init`, incl. a sanctioned `init --force` re-target after
	# an upstream force-push) STARTS a new port sequence on purpose: reset the
	# comparison line there instead of flagging the jump as inconsistent.
	prev=""
	while IFS= read -r sha; do
		[ -z "$sha" ] && continue
		tr="$(port_trailer_sha "$sha")"
		[ -z "$tr" ] && continue
		if is_port_init_commit "$sha"; then
			prev="$tr"
			continue
		fi
		if [ -n "$prev" ] && ! git merge-base --is-ancestor "$tr" "$prev" 2>/dev/null &&
			! git merge-base --is-ancestor "$prev" "$tr" 2>/dev/null; then
			printf '  WARNING: port order looks inconsistent near %s (unrelated to previous port)\n' "$(git rev-parse --short "$tr")"
			break
		fi
		prev="$tr"
	done < <(git log --no-merges --reverse --format='%H' "$ptr..HEAD" 2>/dev/null || true)
	# Tampering: a NON-port, NON-unport commit that actually CHANGED the pointer SHA. The
	# pointer may only move inside a Fork-Flow-Port[-Init] commit (forward) or a
	# Fork-Flow-Unport commit (a `port.sh revert`, backward); compare each pointer-touching
	# commit's SHA before/after so the kit-install commit (adds a comments-only pointer) and
	# comment-only header edits are NOT flagged — only a real SHA change carried by no trailer.
	edited=""
	while IFS= read -r sha; do
		[ -z "$sha" ] && continue
		{ is_upstream_port_commit "$sha" || is_upstream_unport_commit "$sha"; } && continue
		bsha="$(git show "$sha^:.fork/UPSTREAM" 2>/dev/null | awk 'NF && $1!~/^#/{print $1; exit}')" || true
		asha="$(git show "$sha:.fork/UPSTREAM" 2>/dev/null | awk 'NF && $1!~/^#/{print $1; exit}')" || true
		[ "$bsha" = "$asha" ] && continue
		edited="${edited:+$edited
}$sha"
	done < <(git log --format='%H' -- .fork/UPSTREAM 2>/dev/null || true)
	if [ -n "$edited" ]; then
		printf '  WARNING: .fork/UPSTREAM SHA changed by NON-port commit(s) (no %s trailer):\n' "$PORT_TRAILER"
		printf '%s\n' "$edited" | while IFS= read -r e; do
			[ -z "$e" ] && continue
			printf '    %s  %s\n' "$(git rev-parse --short "$e")" "$(git log -1 --format=%s "$e")"
		done
	fi
fi

# registry_paths (every Touches token + each Symbols name@path, de-duplicated)
# now lives in .fork/lib.sh; pass it "$changes" so this script has one source of
# truth for the registry path (also consumed by the Status section below).

# 0. fork delta (your conflict surface) ---------------------------------------
# Edits to files that already existed at the merge-base are what CAUSE future
# conflicts; brand-new files you own are nearly free. Watch this number shrink.
printf '\n== fork delta (edits to existing upstream files = your conflict surface) ==\n'
delta="$(git diff --diff-filter=M --shortstat "$base..HEAD" 2>/dev/null || true)"
if [ -n "$delta" ]; then
	printf '  %s\n' "${delta#"${delta%%[![:space:]]*}"}"
else
	printf '  (no modified upstream files — all your changes are additions; lowest-conflict footprint)\n'
fi

# 0b. merge=ours divergence ----------------------------------------------------
# A merge=ours pin works SILENTLY: every ported upstream change to the path is
# discarded with no conflict and no trace (a flag file missing new upstream flags
# while their backend code DID port — observed in the wild). brief.sh flags a pin
# only when you brief that specific commit; nothing reported the accumulated gap
# afterwards. This is that report: the diff between each pinned path's current
# copy and the last PORTED upstream tree. It includes your own intended edits —
# it is the number to WATCH, not to zero; what matters is that it only grows for
# reasons you can name.
printf '\n== merge=ours divergence (what each pin hides vs the ported upstream) ==\n'
mo_any=0
while IFS= read -r p; do
	[ -z "$p" ] && continue
	mo_any=1
	mo_stat="$(git diff --shortstat "$base" -- "$p" 2>/dev/null || true)"
	if [ -n "$mo_stat" ]; then
		printf '  %s:%s\n' "$p" "$mo_stat"
		printf '    inspect: git diff %s -- %s\n' "$(git rev-parse --short "$base")" "$p"
	else
		printf '  %s: in sync with the ported upstream\n' "$p"
	fi
done < <(merge_ours_paths)
[ "$mo_any" -eq 0 ] && printf '  (no merge=ours overrides declared)\n'

# 1. orphaned anchors ---------------------------------------------------------
printf '\n== orphaned anchors (registry path no longer tracked) ==\n'
orphan=0
while IFS= read -r p; do
	[ -z "$p" ] && continue
	git ls-files --error-unmatch -- "$p" >/dev/null 2>&1 ||
		{
			printf '  MISSING: %s\n' "$p"
			orphan=1
		}
done < <(registry_paths "$changes")
[ "$orphan" -eq 0 ] && printf '  (all anchors still present)\n'

# 2. unregistered changes -----------------------------------------------------
# Files changed by YOUR commits in "$base..HEAD" that no registry anchor covers.
# The walk itself — skip PORT/UNPORT commits by their strict trailers (a port carries
# upstream's files, not your customizations; a stray staged pointer is NOT a port),
# exclude toolkit paths, match the rest glob-aware — lives in lib.sh as
# fork_unregistered_files, SHARED with brief.sh's unregistered-changes warning so the
# two scans can never disagree. No reliance on the `custom:` prefix; the commit-msg
# hook stays a reminder.
printf '\n== files your fork changed but NOT in any Touches/Symbols (registry gaps) ==\n'
# Partition the scan: only a file still IN the tree is actionable ("register or
# delete"). A path your history touched that upstream has since renamed/deleted
# accretes here FOREVER otherwise (neither registrable nor deletable — pure noise
# that trains the eye to skim this section past the real gap sitting next to it).
# Middle case: gone from YOUR tree but still alive upstream = your fork DELETED an
# upstream file — that deletion is itself a customization; register or restore it.
unreg=0
deleted_ours=""
ghosts=""
while IFS= read -r f; do
	[ -z "$f" ] && continue
	if git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
		printf '  UNREGISTERED: %s\n' "$f"
		unreg=1
	elif git cat-file -e "$upstream:$f" 2>/dev/null; then
		deleted_ours="${deleted_ours:+$deleted_ours
}$f"
	else
		ghosts="${ghosts:+$ghosts
}$f"
	fi
done <<EOF
$(fork_unregistered_files "$base" "$changes")
EOF
if [ -n "$deleted_ours" ]; then
	unreg=1
	printf '%s\n' "$deleted_ours" | while IFS= read -r f; do
		[ -n "$f" ] && printf '  UNREGISTERED (deleted by your fork; still exists upstream): %s\n' "$f"
	done
fi
[ "$unreg" -eq 0 ] && printf '  (every changed file is registered)\n'
[ "$unreg" -ne 0 ] && printf '  -> register these with the fork-change skill, or delete/restore them\n'
if [ -n "$ghosts" ]; then
	printf '  historical only — gone from your tree AND upstream (renamed/deleted since; nothing to do):\n'
	printf '%s\n' "$ghosts" | while IFS= read -r f; do
		[ -n "$f" ] && printf '    %s\n' "$f"
	done
fi

# 3. status + drop candidates -------------------------------------------------
printf '\n== customization status (retire superseded / upstreamed ones) ==\n'
drops=""
emit_status() { # reads $sheading/$sstatus; prints status line; appends to $drops
	local norm
	[ -z "$sheading" ] && return 0
	printf '  [%s] %s\n' "${sstatus:-carry?}" "$sheading"
	sany=1
	# Match WHOLE status tokens, not substrings: a glob like *upstreamed* wrongly
	# caught "not-upstreamed" / "to-be-upstreamed" (the OPPOSITE of a drop). Normalize
	# in awk (no `tr` — keeps the git/awk/grep-only invariant): lower-case, collapse
	# every run of non-alphanumeric/non-hyphen to one space (so "upstreamed." and
	# "superseded, see #123" still tokenize), keep hyphens so "proposed-upstream" stays
	# one token, and pad with spaces so each pattern matches a complete token.
	norm="$(printf '%s' "$sstatus" | awk '{s=tolower($0); gsub(/[^a-z0-9-]+/," ",s); print " " s " "}')"
	case "$norm" in
	*" superseded "* | *" upstreamed "* | *" proposed-upstream "* | *" applied-upstream "*)
		drops="${drops:+$drops
}$sheading"
		;;
	esac
}
if [ ! -f "$changes" ]; then
	printf '  (no %s)\n' "$changes"
else
	sheading=""
	sstatus=""
	sany=0
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
		"## "*)
			emit_status
			sheading="${line#"## "}"
			sstatus=""
			;;
		[Ss]tatus:*)
			sstatus="${line#*:}"
			sstatus="${sstatus# }"
			;;
		esac
	done <"$changes"
	emit_status
	[ "$sany" -eq 0 ] && printf '  (no entries)\n'
fi
if [ -n "$drops" ]; then
	printf '\n== DROP CANDIDATES (Status says on the way out — delete to shrink the fork) ==\n'
	printf '%s\n' "$drops" | while IFS= read -r d; do [ -n "$d" ] && printf '  DROP: %s\n' "$d"; done
fi

# 4. unported upstream backlog ------------------------------------------------
# Upstream commits AFTER the .fork/UPSTREAM pointer that you have not ported yet — your
# integration backlog along upstream's FIRST-PARENT line, oldest first (the order
# upstream-port applies them). Merges are INCLUDED: the driver ports each as a unit
# (cherry-pick -m 1), so they count toward the backlog. With no pointer set, base is the
# merge-base, so this still lists upstream's commits since you diverged.
printf '\n== unported upstream commits (base..%s — your port backlog, oldest first) ==\n' "$upstream"
backlog="$(git log --first-parent --reverse --format='  %h  %s' "$base..$upstream" 2>/dev/null || true)"
if [ -n "$backlog" ]; then
	printf '%s\n' "$backlog"
	n="$(printf '%s\n' "$backlog" | grep -c .)"
	printf '  -> %s commit(s) to port via the upstream-port skill\n' "$n"
else
	printf '  (up to date — nothing upstream past the pointer)\n'
fi

# 5. maybe reimplemented upstream (patch-id) ----------------------------------
# The old merge flow had a range-diff hint for "did upstream re-implement my change?"
# A commit-by-commit fork has no merge ancestry for range-diff, but git patch-id still
# matches an equivalent diff regardless of SHA/parentage. We compute the patch-id of
# every UPSTREAM commit in base..upstream, then flag any of YOUR non-port commits whose
# patch-id collides — a strong "upstream now ships this; consider retiring it" signal.
# CAVEAT: patch-id matches only a near-identical diff; a re-expressed customization
# will NOT match, so a clean result here does NOT prove upstream lacks your feature.
printf '\n== possibly reimplemented upstream (patch-id matches; caveated) ==\n'
# The scan is O(backlog) — one `git show | git patch-id` per unported upstream commit —
# so on a fork that fell far behind it dominates audit's runtime while its signal
# (exact-diff matches against a wall of unported commits) drowns. Cap it: past
# FORK_AUDIT_PATCHID_MAX commits (default 200) print a skip notice instead; --deep
# forces the full scan. Catch up first (port.sh range, tag by tag), then audit deep.
pid_max="${FORK_AUDIT_PATCHID_MAX:-200}"
pid_n="$(git rev-list --no-merges --count "$base..$upstream" 2>/dev/null || echo 0)"
if [ "$deep" -eq 0 ] && [ "$pid_n" -gt "$pid_max" ]; then
	printf '  (skipped: %s unported upstream commits exceed the cap of %s — run\n' "$pid_n" "$pid_max"
	printf '   ./.fork/audit.sh --deep %s for the full scan, or catch up first with port.sh range)\n' "$upstream"
	exit 0
fi
# Map of upstream patch-id -> short sha+subject, built once.
up_ids="$(
	git log --no-merges --format='%H' "$base..$upstream" 2>/dev/null | while IFS= read -r sha; do
		[ -z "$sha" ] && continue
		pid="$(git show "$sha" 2>/dev/null | git patch-id --stable 2>/dev/null | awk '{print $1}')"
		if [ -n "$pid" ]; then printf '%s %s %s\n' "$pid" "$(git rev-parse --short "$sha")" "$(git log -1 --format=%s "$sha")"; fi
	done
)"
hits=0
if [ -n "$up_ids" ]; then
	while IFS= read -r sha; do
		[ -z "$sha" ] && continue
		is_upstream_port_commit "$sha" && continue # skip ports: those ARE upstream's commits
		mypid="$(git show "$sha" 2>/dev/null | git patch-id --stable 2>/dev/null | awk '{print $1}')"
		[ -z "$mypid" ] && continue
		match="$(printf '%s\n' "$up_ids" | awk -v id="$mypid" '$1==id {sub(/^[^ ]+ /,""); print; exit}')"
		if [ -n "$match" ]; then
			printf '  %s "%s"  ==  upstream %s\n' "$(git rev-parse --short "$sha")" "$(git log -1 --format=%s "$sha")" "$match"
			hits=1
		fi
	done < <(git log --no-merges --format='%H' "$base..HEAD" 2>/dev/null || true)
fi
[ "$hits" -eq 0 ] && printf '  (no exact patch-id matches — NOTE: a re-expressed change will not match)\n'

exit 0
