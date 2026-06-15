#!/usr/bin/env bash
# .fork/port.sh — the upstream PORT driver (see Fork Maintenance in your CLAUDE.md/AGENTS.md).
#
#   ./.fork/port.sh init [--force] <sha> [upstream-ref]  set the pointer (--force: sanctioned re-target)
#   ./.fork/port.sh list [upstream-ref]                  the unported backlog, oldest first
#   ./.fork/port.sh next [upstream-ref]                  port the OLDEST unported commit
#   ./.fork/port.sh one <sha> [upstream-ref]             port a specific upstream commit (must be the next unported one)
#   ./.fork/port.sh range <sha|tag> [upstream-ref]       CATCH-UP: squash-port pointer..<sha> as ONE gated commit
#   ./.fork/port.sh revert [<sha>]                       un-port the NEWEST port (rewinds the pointer, gated)
#   ./.fork/port.sh continue                             finalize a paused port/unport after resolving conflicts
#   ./.fork/port.sh abort                                throw away an in-progress port/unport
#   ./.fork/port.sh status                               show in-progress state
#
# This is the one place the porting INVARIANTS are enforced as code, not skill prose:
#   - every port is a `git cherry-pick -x --no-commit` (a MERGE adds `-m 1`, replaying the
#     merge's first-parent diff — its whole net effect — as one commit); a clean port stays
#     a real commit the integration gate can see — a bare cherry-pick runs NO hook;
#   - the pointer advances in the SAME commit, recorded as `<sha> <ref>` in .fork/UPSTREAM;
#   - the commit carries a strict `Fork-Flow-Port: <full-sha>` trailer (the SOLE signal
#     audit/propose-upstream use to tell a port from your own work — a stray pointer in
#     an ordinary commit is NOT a port);
#   - the pointer only ever moves FORWARD (the new sha must have the old pointer as an
#     ancestor on the upstream line), so it can't silently rewind; `init --force` is the
#     ONE sanctioned reset (upstream force-push / retarget): it commits a fresh Init
#     trailer that audit treats as the start of a new port sequence — never hand-edit;
#   - ports are CONTIGUOUS: only the OLDEST unported commit may be ported (`one <sha>`
#     refuses a later one), so the pointer can't jump PAST unported ancestors and bury
#     them from the backlog/audit;
#   - upstream MERGE commits are ported as a UNIT via `cherry-pick -m 1` — their
#     first-parent diff carries all merged (farm) content AND any evil-merge resolution
#     that lives in no single commit, and the merge SHA stays on the first-parent line;
#   - a fork that fell releases BEHIND can squash-port per release tag with `range` —
#     one gated commit applying the whole pointer..<sha> diff (one conflict set per
#     file), trailered Fork-Flow-Port + Fork-Flow-Port-From; per-commit stays the default;
#     delete-involved paths (upstream deleted what you modified, and the mirrors) are
#     pulled out of the atomic git-apply and staged as synthetic conflicts so ONE such
#     path no longer aborts the whole span — they pause for review like any conflict;
#   - on conflict it STOPS and points you at conflict-context.sh, then `continue`;
#   - rerere may pre-fill a remembered resolution, but never silently: autoUpdate is
#     forced off and the pause banner flags replayed paths for review (list_conflicts);
#   - a CONFLICTED port (and every range/conflicted revert) appends a journal skeleton
#     to .fork/PORTS.md in the same commit — the conflict set is on record even when
#     nobody journals by hand;
#   - port/unport commits run with FORK_FLOW_PORT=1 in the environment so a CHAINED
#     project hook (formatters!) can skip rewriting them; if one rewrites anyway, the
#     committed tree differs from the staged snapshot and port.sh WARNS after the fact.
# The actual gate (verify.sh --registry) still runs in the pre-commit hook on the final
# commit; this driver just makes the mechanics correct and hard to get wrong.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# shellcheck source=/dev/null
. .fork/lib.sh

state="$(git rev-parse --git-path fork-flow-port 2>/dev/null)"
unport_state="$(git rev-parse --git-path fork-flow-unport 2>/dev/null)"
changes_file=".fork/UPSTREAM"

die() {
	printf 'port.sh: %s\n' "$*" >&2
	exit 1
}
note() { printf 'port.sh: %s\n' "$*" >&2; }

# rerere is active when rerere.enabled says so, or is unset while .git/rr-cache
# exists (git's own activation rule). Only then is `git rerere remaining`
# meaningful for splitting the conflict listing below.
rerere_active() {
	case "$(git config --get --type=bool rerere.enabled 2>/dev/null || true)" in
	true) return 0 ;;
	false) return 1 ;;
	esac
	[ -d "$(git rev-parse --git-path rr-cache)" ]
}

# Print the unmerged paths to stderr, separating the ones rerere ALREADY auto-
# resolved in the worktree (unmerged in the index but absent from `git rerere
# remaining`). A replayed file carries NO conflict markers, so a reflexive
# `git add` would sweep a remembered — possibly WRONG — resolution through
# unreviewed; the split forces eyes on exactly those paths. Every mutating
# command here runs with rerere.autoUpdate forced off, so a replayed path stays
# unmerged and this listing cannot miss one.
list_conflicts() {
	local p unmerged remaining eligible replayed=""
	# quotepath=false: `git rerere remaining` prints raw bytes while diff would
	# quote non-ASCII paths ("p\303\244.js"), breaking the membership test below
	# (a raw conflict would then masquerade as auto-resolved — verified by hand).
	unmerged="$(git -c core.quotepath=false diff --name-only --diff-filter=U)"
	# Only a full THREE-WAY content conflict (stages 1 AND 2 AND 3 in the index) can
	# have been replayed by rerere here. Delete-involved conflicts and add/add — incl.
	# the synthetic ones a `range` stages — are invisible to `git rerere remaining`,
	# so the bare unmerged-minus-remaining subtraction would mislabel them
	# AUTO-RESOLVED when nothing resolved anything (an add/add with no markers looked
	# exactly like a replay on a machine with global rerere.enabled=true — found by
	# test t54). Under-claiming is safe — a real replay then lists as a plain conflict
	# and still gets reviewed; over-claiming is the lie this banner must never tell.
	eligible="$(git -c core.quotepath=false ls-files -u | awk -F'\t' '
		$1 ~ / 1$/ {s1[$2]=1} $1 ~ / 2$/ {s2[$2]=1} $1 ~ / 3$/ {s3[$2]=1}
		END {for (f in s1) if ((f in s2) && (f in s3)) print f}')"
	remaining="$unmerged"
	if rerere_active; then
		remaining="$(git rerere remaining 2>/dev/null)" || remaining="$unmerged"
	fi
	while IFS= read -r p; do
		[ -z "$p" ] && continue
		if ! printf '%s\n' "$eligible" | grep -Fxq -- "$p"; then
			printf '  %s\n' "$p" >&2 # delete-involved: rerere can never have touched it
		elif printf '%s\n' "$remaining" | grep -Fxq -- "$p"; then
			printf '  %s\n' "$p" >&2
		else
			replayed="${replayed}  ${p}
"
		fi
	done <<EOF
$unmerged
EOF
	if [ -n "$replayed" ]; then
		{
			printf 'rerere AUTO-RESOLVED these from a PAST resolution (no conflict markers, left\n'
			printf 'unmerged on purpose) — REVIEW each one; a remembered fix can be wrong here:\n'
			printf '%s' "$replayed"
			printf 'Redo from scratch:  git rerere forget <file> && git checkout -m -- <file>\n'
		} >&2
	fi
}

ptr_ref_default() { upstream_pointer_ref; }

require_clean_tree() {
	if ! git diff --quiet || ! git diff --cached --quiet; then
		die "working tree is dirty — commit or stash first (a port must start clean)"
	fi
}

# Gate-wiring detection (a fresh clone has no hooks until ./.fork/setup.sh runs
# there) lives in lib.sh as hooks_gate_wired — shared with verify.sh's post-install
# unwire warning so the two can never disagree.

# Defense in depth: when the hooks are NOT wired, run the integration gate INLINE
# before the port/unport commit — otherwise a fresh clone would port UNGATED, the
# exact silent-customization-drop the kit exists to prevent. When the hooks ARE
# wired, the pre-commit hook runs the same check and this stays out of the way (no
# double run). Honors the hooks' FORK_SKIP_VERIFY escape.
inline_gate() { # <what: port|unport>
	[ -n "${FORK_SKIP_VERIFY:-}" ] && return 0
	hooks_gate_wired && return 0
	[ -x .fork/verify.sh ] || return 0
	note "hooks not wired in this clone — running the gate inline (wire them: ./.fork/setup.sh)"
	if ! ./.fork/verify.sh --registry; then
		die "gate FAILED — a customization may not have survived this $1.
       Fix it, then ./.fork/port.sh continue   (or abort). One-off bypass: FORK_SKIP_VERIFY=1"
	fi
}

# Per-clone wiring check, run at the start of every MUTATING subcommand (decides
# nothing — warns). git config is not carried by copied files, so on a fresh clone
# the hooks and the merge=ours driver are silently off: the inline gate keeps
# port.sh commits safe regardless, but manual commits/merges are ungated, and
# merge=ours paths would not hold during ports.
preflight() {
	if ! hooks_gate_wired; then
		note "WARNING: fork-flow hooks are not wired in this clone — port.sh runs its gate"
		note "         inline, but MANUAL commits/merges are ungated. Wire them once:"
		note "         ./.fork/setup.sh   (shipped with the fork; --check reports wiring)"
	fi
	if [ -n "$(merge_ours_paths)" ] && ! git config merge.ours.driver >/dev/null 2>&1; then
		note "WARNING: .gitattributes declares merge=ours paths but merge.ours.driver is not"
		note "         configured in this clone — those overrides will NOT hold during ports."
		note "         Fix: ./.fork/setup.sh   (or git config merge.ours.driver true)"
	fi
}

# Write "<sha> <ref>" to .fork/UPSTREAM, preserving the file's comment header.
write_pointer() { # <full-sha> <ref>
	local sha="$1" ref="$2" tmp
	tmp="$(mktemp)"
	# keep every comment/blank line from the existing header; drop the old SHA line
	if [ -f "$changes_file" ]; then
		awk 'NF==0 || $1 ~ /^#/ {print}' "$changes_file" >"$tmp"
	fi
	printf '%s %s\n' "$sha" "$ref" >>"$tmp"
	mv "$tmp" "$changes_file" || { rm -f "$tmp"; return 1; }
}

# Refuse to move the pointer backwards or sideways: the new commit must be a
# descendant of the current pointer (forward-only on the upstream line).
assert_forward() { # <new-sha>
	local newsha="$1" cur
	cur="$(upstream_pointer)"
	[ -z "$cur" ] && return 0
	[ "$cur" = "$newsha" ] && return 0
	if ! git merge-base --is-ancestor "$cur" "$newsha" 2>/dev/null; then
		die "refusing to move pointer to $newsha: current pointer $cur is not its ancestor
       (that would rewind or sidestep the pointer — port in order, or fix .fork/UPSTREAM)"
	fi
}

resolve_upstream_ref() { # [arg]
	local ref="${1:-}"
	if [ -z "$ref" ]; then ref="$(ptr_ref_default)"; fi
	if [ -z "$ref" ]; then ref="upstream/main"; fi
	git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null 2>&1 ||
		die "not a commit: $ref (fetch upstream, or pass the right ref)"
	printf '%s' "$ref"
}

backlog() { # <upstream-ref>
	local ref="$1" base
	base="$(upstream_base "$ref")" || exit $? # hard-fails (3) on a broken pointer
	git log --first-parent --reverse --format='%H' "$base..$ref"
}

cmd_status() {
	if [ -f "$state" ]; then
		printf 'A port is IN PROGRESS:\n'
		sed 's/^/  /' "$state"
		printf 'Resolve conflicts, then: ./.fork/port.sh continue   (or: ./.fork/port.sh abort)\n'
	elif [ -f "$unport_state" ]; then
		printf 'An UNPORT (revert) is IN PROGRESS:\n'
		sed 's/^/  /' "$unport_state"
		printf 'Resolve conflicts, then: ./.fork/port.sh continue   (or: ./.fork/port.sh abort)\n'
	else
		printf 'No port in progress. Pointer: %s (ref %s)\n' \
			"$(upstream_pointer || echo '(unset)')" "$(upstream_pointer_ref || echo '?')"
	fi
}

cmd_list() {
	local ref list n=0 sha
	ref="$(resolve_upstream_ref "${1:-}")"
	# Capture via command substitution (NOT process substitution): backlog's
	# upstream_base hard-fails (exit 3) on a corrupt pointer, and that must propagate
	# under set -e. A `done < <(backlog …)` would run backlog in a subshell whose exit
	# the parent never sees, so a broken pointer would print "(up to date)" — the exact
	# silent lie the pointer contract forbids (cmd_next already captures this way).
	list="$(backlog "$ref")"
	printf '== unported backlog (%s), oldest first ==\n' "$ref"
	while IFS= read -r sha; do
		[ -z "$sha" ] && continue
		printf '  %s  %s\n' "$(git rev-parse --short "$sha")" "$(git log -1 --format=%s "$sha")"
		n=$((n + 1))
	done <<EOF
$list
EOF
	[ "$n" -eq 0 ] && printf '  (up to date)\n'
	[ "$n" -gt 0 ] && printf '  -> %d to port; run ./.fork/port.sh next\n' "$n"
	return 0 # success regardless of backlog size (corrupt pointer already exited 3 above)
}

cmd_init() {
	local force=0
	if [ "${1:-}" = "--force" ]; then
		force=1
		shift
	fi
	local sha="${1:-}" ref="${2:-upstream/main}" old old_ref
	[ -n "$sha" ] || die "usage: ./.fork/port.sh init [--force] <upstream-sha> [upstream-ref]"
	[ -f "$state" ] && die "a port is in progress — finish it (continue/abort) first"
	[ -f "$unport_state" ] && die "an unport is in progress — finish it (continue/abort) first"
	old="$(upstream_pointer)"
	old_ref="$(upstream_pointer_ref)"
	if [ -n "$old" ] && [ "$force" -eq 0 ]; then
		die "pointer already set ($old); init is one-time only.
       To RE-TARGET after an upstream force-push or branch switch (the recorded pointer
       no longer sits on the line you port from), reset it explicitly — with the user's
       agreement, never silently:   ./.fork/port.sh init --force <sha> [ref]
       A forced re-init commits a fresh $INIT_TRAILER trailer, which audit treats
       as a sanctioned sequence reset; hand-editing .fork/UPSTREAM is flagged as tamper."
	fi
	require_clean_tree
	preflight
	git rev-parse --verify --quiet "${sha}^{commit}" >/dev/null 2>&1 || die "not a commit: $sha"
	sha="$(git rev-parse "$sha")"
	git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null 2>&1 || die "not a commit: $ref"
	# A forced re-init records WHY in the commit (the old pointer), and its Init trailer
	# is what audit's port-order check recognizes as the start of a new port sequence.
	local subject body
	if [ -n "$old" ]; then
		subject="fork-flow: re-initialize upstream pointer (forced)"
		body="Sanctioned pointer RESET (upstream force-push / retarget): the previous pointer
$old${old_ref:+ ($old_ref)} no longer sits on the line being ported. No code is
ported by this commit; audit treats this Init trailer as the start of a new port
sequence, and subsequent ports advance from here."
	else
		subject="fork-flow: initialize upstream pointer"
		body="Records the upstream commit this fork last corresponded to. No code is ported by
this commit; subsequent ports advance the pointer one upstream commit at a time."
	fi
	# init ports NO code, so it is NOT an integration — commit with --no-verify.
	# Staging .fork/UPSTREAM otherwise trips the pre-commit integration gate, which
	# would block init on an unrelated red/prose Verify even though nothing was ported.
	# Snapshot the pointer file first so a commit that still fails for another reason
	# (e.g. signing) rolls back cleanly, instead of leaving a staged-but-uncommitted
	# pointer that makes the retry die with "pointer already set".
	local snap had=0
	snap="$(mktemp)"
	if [ -f "$changes_file" ]; then
		cp "$changes_file" "$snap"
		had=1
	fi
	# Until the commit lands, restore the snapshot on ANY failure — not just a failed
	# `git commit`. write_pointer or `git add` failing (e.g. a stale .git/index.lock)
	# would otherwise abort under set -e with the pointer already staged/written, so the
	# retry dies with "pointer already set". Track rc explicitly so set -e never
	# short-circuits past the rollback.
	local rc=0
	write_pointer "$sha" "$ref" || rc=$?
	[ "$rc" = 0 ] && { git add "$changes_file" || rc=$?; }
	[ "$rc" = 0 ] && { git commit --no-verify -m "$subject

$body

$INIT_TRAILER: $sha" || rc=$?; }
	if [ "$rc" != 0 ]; then
		git reset -q -- "$changes_file" >/dev/null 2>&1 || true
		if [ "$had" -eq 1 ]; then cp "$snap" "$changes_file"; else rm -f "$changes_file"; fi
		rm -f "$snap"
		die "init failed (rc $rc) — pointer change rolled back; nothing committed"
	fi
	rm -f "$snap"
	if [ -n "$old" ]; then
		note "pointer RE-initialized at $sha (ref $ref; was $old)"
	else
		note "pointer initialized at $sha (ref $ref)"
	fi
}

# Stage the pointer + the applied tree and make the final port commit. Shared by a
# clean port and by `continue` after a manual resolve. With a non-empty <from-sha>
# (a `range` catch-up, see cmd_range) the commit message records the squashed span
# instead of one upstream commit and carries a Fork-Flow-Port-From trailer alongside
# the Fork-Flow-Port one (the strict port parser does not match -From, so audit and
# the hooks treat a range commit exactly like any other port).
finalize() { # <full-sha> <ref> [<from-sha>]
	local sha="$1" ref="$2" from="${3:-}" msg subject n conflicts="" jsub staged_tree
	# No unmerged paths may remain.
	if git ls-files --unmerged --error-unmatch -- . >/dev/null 2>&1; then
		list_conflicts
		die "unresolved conflicts remain (above) — resolve + 'git add', then ./.fork/port.sh continue"
	fi
	assert_forward "$sha"
	write_pointer "$sha" "$ref"
	git add "$changes_file"
	# Journal skeleton (.fork/PORTS.md): a CONFLICTED port and every `range` catch-up
	# get an entry in the SAME commit — the conflict set is on record even when nobody
	# journals by hand (re-porting after a revert otherwise redoes the registry surgery
	# from memory: rerere replays the code, nothing replays the decisions). The
	# "(fill in)" lines are the prompt; the upstream-port skill says to flesh them out.
	# Trivial clean ports are skipped — one noise line per port would drown the journal.
	# JOURNALED= guards a gate-failed retry from appending a duplicate entry.
	if [ -f "$state" ] && ! grep -q '^JOURNALED=1$' "$state"; then
		conflicts="$(awk '/^CONFLICT=/{print substr($0,10)}' "$state")"
		if [ -n "$from" ] || [ -n "$conflicts" ]; then
			if [ -n "$from" ]; then
				jsub="catch-up $(git rev-parse --short "$from")..$(git rev-parse --short "$sha") ($ref)"
			else
				jsub="ported $(git rev-parse --short "$sha") \"$(git log -1 --format=%s "$sha")\""
			fi
			{
				printf '\n## %s — %s\n' "$(date +%Y-%m-%d)" "$jsub"
				if [ -n "$conflicts" ]; then
					printf 'Conflicts:\n'
					printf '%s\n' "$conflicts" | while IFS= read -r c; do
						[ -n "$c" ] && printf '  - %s — resolution: (fill in)\n' "$c"
					done
				else
					printf 'Conflicts: none\n'
				fi
				printf 'Decisions: (fill in — drift verdicts, merge=ours notes, registry updates)\n'
			} >>.fork/PORTS.md
			git add .fork/PORTS.md
			printf 'JOURNALED=1\n' >>"$state"
		fi
	fi
	if [ -n "$from" ]; then
		n="$(git rev-list --first-parent --count "$from..$sha")"
		msg="$(printf 'port: catch-up %s..%s (%s)\n\nSquash-ports %s upstream first-parent commits as one unit (./.fork/port.sh range).\nPer-commit upstream history for this span: git log %s..%s\n\n%s: %s\n%s: %s\n' \
			"$(git rev-parse --short "$from")" "$(git rev-parse --short "$sha")" "$ref" \
			"$n" "$from" "$sha" "$PORT_TRAILER" "$sha" "$FROM_TRAILER" "$from")"
	else
		subject="$(git log -1 --format=%s "$sha")"
		msg="$(printf '%s\n\n%s\n\n(cherry picked from commit %s)\n%s: %s\n' \
			"$subject" "$(git log -1 --format=%b "$sha")" "$sha" "$PORT_TRAILER" "$sha")"
	fi
	# The pre-commit integration gate runs verify.sh --registry here (pointer is
	# staged); on an unwired clone inline_gate runs the SAME check right now instead.
	inline_gate port
	# FORK_FLOW_PORT=1 marks this commit for CHAINED project hooks: a formatter hook
	# (eslint --fix + git add, rubocop -a) that rewrites a port commit makes the ported
	# content stop matching upstream — projects can guard their hooks on this variable.
	# The write-tree snapshot detects exactly that rewrite, after the fact.
	staged_tree="$(git write-tree)"
	printf '%s' "$msg" | FORK_FLOW_PORT=1 git commit -F -
	rm -f "$state"
	warn_if_hook_rewrote "$staged_tree"
	note "ported $sha; pointer now $sha"
}

# A hook ran `git add` during the commit (chained formatters do): the committed tree
# no longer matches what port.sh staged, so the ported content differs from upstream —
# future conflicts get noisier and audit's patch-id hints degrade. Warn, never undo:
# the project's hook may be enforcing something it has every right to enforce.
warn_if_hook_rewrote() { # <staged-tree-oid>
	[ -n "$1" ] || return 0
	[ "$(git rev-parse 'HEAD^{tree}' 2>/dev/null)" = "$1" ] && return 0
	note "WARNING: a hook REWROTE this commit while it was being made (a chained"
	note "         formatter running eslint --fix / rubocop -a + git add?). The committed"
	note "         tree differs from what port.sh staged, so the ported content no longer"
	note "         matches upstream — future conflicts and audit's patch-id hints degrade."
	note "         See what the hook changed:  git diff $1 HEAD"
	note "         Port commits run with FORK_FLOW_PORT=1 set — have the project's hooks"
	note "         skip rewriting when it is present."
}

start_port() { # <full-sha> <ref>
	local sha="$1" ref="$2" parents rc oldest
	[ -f "$state" ] && die "a port is already in progress — continue/abort it first"
	[ "$sha" = "$(upstream_pointer)" ] && die "$sha is already the pointer — nothing to port"
	require_clean_tree
	preflight
	assert_forward "$sha"
	# Merge commits are ported as a UNIT (see cherry-pick below): a merge's first-parent
	# diff is its entire net effect on the mainline — every second-parent (farm) commit it
	# brought in PLUS any evil-merge resolution that exists in no single commit. Replaying
	# the merged commits one-by-one would miss that resolution; the merge SHA also stays on
	# the first-parent line, so the forward-only pointer never wedges.
	parents="$(git rev-list --parents -n1 "$sha" | awk '{print NF-1}')"
	# Contiguity: the pointer means "everything up to here is ported", so a port may not
	# SKIP commits — start_port applies only the OLDEST unported commit on the ref. This is
	# what stops `one <later-sha>` from advancing the pointer PAST unported ancestors (they
	# would vanish from the backlog though never applied). `next` always passes the oldest,
	# so this only ever bites an out-of-order `one`. (Backward SHAs already died above.)
	# awk NR==1, NEVER `head -1`: head closes the pipe after one line, `git log` takes
	# SIGPIPE once the backlog outgrows the pipe buffer (a few hundred real commits), and
	# set -e turns that into a silent exit 141 — the front door dying with zero output
	# exactly when the fork is most behind (found on a 251-commit real backlog). awk
	# drains stdin to EOF, so the writer always finishes.
	oldest="$(backlog "$ref" | awk 'NR==1')"
	if [ "$sha" != "$oldest" ]; then
		[ -z "$oldest" ] && die "$sha is not the next unported commit on $ref (nothing unported there — off-target?)"
		die "refusing to port $sha out of order: the next unported commit on $ref is
       $(git rev-parse --short "$oldest")  $(git log -1 --format=%s "$oldest")
       The pointer is contiguous — port in order with ./.fork/port.sh next (it picks this
       commit), or pass that SHA. To take a single upstream commit early WITHOUT advancing
       the pointer, cherry-pick it as a custom: change instead of porting it."
	fi
	# Record state BEFORE touching the tree so abort/continue always have it.
	printf 'SHA=%s\nREF=%s\n' "$sha" "$ref" >"$state"
	rc=0
	# A merge is replayed against its first parent (-m 1); a normal commit as-is. Both use
	# -x (record the source SHA) and --no-commit (finalize stages the pointer + gates).
	# rerere.autoUpdate (user/global config) would silently STAGE any remembered
	# resolution: the replayed file leaves the unmerged set unreviewed, and a fully-
	# remembered conflict set leaves --diff-filter=U EMPTY — the "no conflicts to
	# resolve" death branch below — the staged half-port and a deleted state file,
	# a wedge only hand cleanup can undo (verified against real git).
	# Force it off; the pause banner (list_conflicts) flags replayed paths instead.
	if [ "$parents" -gt 1 ]; then
		git -c rerere.autoUpdate=false cherry-pick -m 1 -x --no-commit "$sha" || rc=$?
	else
		git -c rerere.autoUpdate=false cherry-pick -x --no-commit "$sha" || rc=$?
	fi
	if [ "$rc" -ne 0 ]; then
		if git diff --name-only --diff-filter=U | grep -q .; then
			# Remember the conflict set so finalize can journal it (.fork/PORTS.md).
			git -c core.quotepath=false diff --name-only --diff-filter=U | awk '{print "CONFLICT=" $0}' >>"$state"
			printf '\nport.sh: CONFLICT porting %s. Files:\n' "$(git rev-parse --short "$sha")" >&2
			list_conflicts
			printf 'Inspect:  ./.fork/conflict-context.sh %s <file>\n' "$sha" >&2
			printf 'Resolve + git add, then: ./.fork/port.sh continue   (or abort)\n' >&2
			exit 1
		fi
		rm -f "$state"
		die "cherry-pick failed (rc=$rc) with no conflicts to resolve — see output above"
	fi
	# Clean apply: finalize now. If the cherry-pick was EMPTY (upstream change already
	# present in the fork), the tree is unchanged but the pointer file still advances, so
	# finalize commits a pointer-only "already present" port — the backlog still shrinks.
	finalize "$sha" "$ref"
}

# Stage the (already rewound) pointer and make the gated unport commit. Shared by a
# clean revert and by `continue` after a manual resolve. `git revert --no-commit` of the
# port commit ALREADY rewound + staged .fork/UPSTREAM (the port advanced it in that same
# commit), so unlike finalize() we do NOT write_pointer — we only record the Unport
# trailer so audit/commit-msg recognize the backward pointer move as legitimate.
finalize_unport() { # <un-ported-full-sha> <expected-previous-pointer>
	local sha="$1" expected="$2" expected_ref="$3" actual actual_ref staged staged_ref msg conflicts="" staged_tree
	if git ls-files --unmerged --error-unmatch -- . >/dev/null 2>&1; then
		list_conflicts
		die "unresolved conflicts remain (above) — resolve + 'git add', then ./.fork/port.sh continue"
	fi
	actual="$(upstream_pointer)"
	actual_ref="$(upstream_pointer_ref)"
	[ "$actual" = "$expected" ] && [ "$actual_ref" = "$expected_ref" ] || die "unport did not rewind .fork/UPSTREAM to $expected ${expected_ref:-<no-ref>} (found ${actual:-unset} ${actual_ref:-<no-ref>})
       restore the revert's pointer change, stage it, then run ./.fork/port.sh continue"
	git add "$changes_file"
	staged="$(git show ":$changes_file" 2>/dev/null | awk 'NF && $1 !~ /^#/ {print $1; exit}')"
	staged_ref="$(git show ":$changes_file" 2>/dev/null | awk 'NF && $1 !~ /^#/ {print $2; exit}')"
	[ "$staged" = "$expected" ] && [ "$staged_ref" = "$expected_ref" ] || die "staged .fork/UPSTREAM is $staged ${staged_ref:-<no-ref>}, expected $expected ${expected_ref:-<no-ref>}"
	msg="$(printf 'fork-flow: revert port of %s\n\nUndoes the port of upstream commit %s, rewinding .fork/UPSTREAM to the\nprevious pointer. Re-port it later with ./.fork/port.sh next.\n\n%s: %s\n' \
		"$(git rev-parse --short "$sha")" "$sha" "$UNPORT_TRAILER" "$sha")"
	# Journal a CONFLICTED unport like a conflicted port (see finalize) — the redo
	# decisions are exactly what a later re-port needs on record.
	if [ -f "$unport_state" ] && ! grep -q '^JOURNALED=1$' "$unport_state"; then
		conflicts="$(awk '/^CONFLICT=/{print substr($0,10)}' "$unport_state")"
		if [ -n "$conflicts" ]; then
			{
				printf '\n## %s — un-ported %s (port.sh revert)\n' "$(date +%Y-%m-%d)" "$(git rev-parse --short "$sha")"
				printf 'Conflicts:\n'
				printf '%s\n' "$conflicts" | while IFS= read -r c; do
					[ -n "$c" ] && printf '  - %s — resolution: (fill in)\n' "$c"
				done
				printf 'Decisions: (fill in — registry entries retargeted/restored by this revert)\n'
			} >>.fork/PORTS.md
			git add .fork/PORTS.md
			printf 'JOURNALED=1\n' >>"$unport_state"
		fi
	fi
	# The pre-commit integration gate runs verify.sh --registry here (pointer is staged):
	# undoing a port must not silently break a customization either.
	inline_gate unport
	# FORK_FLOW_PORT=1 + rewrite detection: same contract as finalize().
	staged_tree="$(git write-tree)"
	printf '%s' "$msg" | FORK_FLOW_PORT=1 git commit -F -
	rm -f "$unport_state"
	warn_if_hook_rewrote "$staged_tree"
	note "reverted port of $sha; pointer now $(upstream_pointer || echo '(unset)')"
}

# Un-port the NEWEST port: `git revert` the fork commit that advanced the pointer to its
# current value (which rewinds .fork/UPSTREAM automatically), then commit it gated with a
# Fork-Flow-Unport trailer. Reverts go newest-first — the mirror of port-oldest-first
# contiguity — so an explicit SHA must name the current pointer.
cmd_revert() { # [<upstream-sha>]
	local want="${1:-}" cur target tr sha prev prev_ref rc
	[ -f "$state" ] && die "a port is in progress — finish it (continue/abort) first"
	[ -f "$unport_state" ] && die "an unport is already in progress — continue/abort it first"
	require_clean_tree
	preflight
	cur="$(upstream_pointer)"
	[ -z "$cur" ] && die "no pointer set — nothing to revert"
	git rev-parse --verify --quiet "${cur}^{commit}" >/dev/null 2>&1 ||
		die "pointer $cur does not resolve — fix .fork/UPSTREAM before reverting"
	cur="$(git rev-parse "$cur")"
	# An explicit SHA is a safety assertion: you may only revert the NEWEST port, i.e. the
	# one the pointer names. Reverting an older port out of order would leave the pointer
	# ahead of the tree (audit's consistency check would then flag it).
	if [ -n "$want" ]; then
		git rev-parse --verify --quiet "${want}^{commit}" >/dev/null 2>&1 || die "not a commit: $want"
		want="$(git rev-parse "$want")"
		[ "$want" = "$cur" ] || die "can only revert the NEWEST port: the pointer is $(git rev-parse --short "$cur"), not $(git rev-parse --short "$want")
       (revert in reverse port order — newest first)"
	fi
	# Find the fork commit whose port trailer names the current pointer — the in-effect
	# newest port. Matching the TRAILER to the pointer (not merely "the newest port
	# commit") means a re-port wins over its reverted original, and a corrupt pointer that
	# names no reachable port is refused rather than reverting the wrong commit.
	target=""
	while IFS= read -r sha; do
		[ -z "$sha" ] && continue
		tr="$(port_trailer_sha "$sha")"
		[ -z "$tr" ] && continue
		if [ "$(git rev-parse "$tr" 2>/dev/null)" = "$cur" ]; then
			target="$sha"
			break
		fi
	done < <(git log --format='%H' HEAD 2>/dev/null || true)
	[ -z "$target" ] &&
		die "no reachable commit ports $(git rev-parse --short "$cur") — .fork/UPSTREAM may be hand-edited (expected a $PORT_TRAILER trailer)"
	# The pointer being the INIT pointer means nothing has been ported — there is no port
	# to revert (reverting init would just un-initialize the fork).
	if git log -1 --format='%B' "$target" 2>/dev/null | grep -q "^$INIT_TRAILER:"; then
		die "pointer is at the init commit (nothing ported) — port forward first, or undo init by hand"
	fi
	prev="$(git show "$target^:$changes_file" 2>/dev/null | awk 'NF && $1 !~ /^#/ {print $1; exit}')"
	prev_ref="$(git show "$target^:$changes_file" 2>/dev/null | awk 'NF && $1 !~ /^#/ {print $2; exit}')"
	[ -n "$prev" ] || die "port commit $(git rev-parse --short "$target") has no previous pointer to restore"
	note "reverting port $(git rev-parse --short "$target") (un-ports $(git rev-parse --short "$cur"))"
	# Record state BEFORE touching the tree so abort/continue always have it.
	printf 'UNPORT=%s\nPREV=%s\nPREV_REF=%s\n' "$cur" "$prev" "$prev_ref" >"$unport_state"
	rc=0
	# autoUpdate forced off for the same reasons as start_port's cherry-pick.
	git -c rerere.autoUpdate=false revert --no-commit "$target" || rc=$?
	if [ "$rc" -ne 0 ]; then
		if git diff --name-only --diff-filter=U | grep -q .; then
			# Remember the conflict set so finalize_unport can journal it (.fork/PORTS.md).
			git -c core.quotepath=false diff --name-only --diff-filter=U | awk '{print "CONFLICT=" $0}' >>"$unport_state"
			printf '\nport.sh: CONFLICT reverting %s. Files:\n' "$(git rev-parse --short "$target")" >&2
			list_conflicts
			printf 'Resolve + git add, then: ./.fork/port.sh continue   (or abort)\n' >&2
			exit 1
		fi
		git revert --abort >/dev/null 2>&1 || git reset -q --hard HEAD
		rm -f "$unport_state"
		die "revert failed (rc=$rc) with no conflicts to resolve — see output above"
	fi
	# Clean revert: .fork/UPSTREAM is already rewound + staged; finalize now (gated).
	finalize_unport "$cur" "$prev" "$prev_ref"
}

cmd_one() {
	local sha="${1:-}" ref
	[ -n "$sha" ] || die "usage: ./.fork/port.sh one <sha> [upstream-ref]"
	ref="$(resolve_upstream_ref "${2:-}")"
	git rev-parse --verify --quiet "${sha}^{commit}" >/dev/null 2>&1 || die "not a commit: $sha"
	sha="$(git rev-parse "$sha")"
	start_port "$sha" "$ref"
}

cmd_next() {
	local ref sha
	ref="$(resolve_upstream_ref "${1:-}")"
	[ -z "$(upstream_pointer)" ] && die "no pointer yet — run ./.fork/port.sh init <sha> [ref] first"
	# awk NR==1 (drains stdin), never `head -1` — see the SIGPIPE note in start_port.
	sha="$(backlog "$ref" | awk 'NR==1')"
	[ -z "$sha" ] && {
		note "nothing to port — up to date with $ref"
		return 0
	}
	note "porting $(git rev-parse --short "$sha"): $(git log -1 --format=%s "$sha")"
	start_port "$sha" "$ref"
}

# CATCH-UP: squash-port the WHOLE span pointer..<sha> as ONE gated commit. The
# per-commit loop stays the default (small, individually understood, individually
# revertible ports); range is the deliberate escape hatch for a fork that fell
# releases behind, where a hot file would otherwise re-conflict on every upstream
# touch of it. One three-way apply of the span's diff = ONE conflict set per file.
# Use it tag-by-tag (oldest release first), then return to `next`. Invariants kept:
# forward-only (assert_forward), contiguous by construction (the span STARTS at the
# pointer), pointer staged in the same commit (the gate fires), and `revert` undoes
# it like any port (the pointer rewinds to <from> automatically). NOTE: `git apply`
# fires NO merge drivers, so merge=ours paths are re-asserted from HEAD explicitly
# below; mergiraf does not assist here — conflicts surface as plain markers, which
# is the conservative side.
cmd_range() { # <sha|tag> [upstream-ref]
	local sha="${1:-}" ref cur rc p n
	[ -n "$sha" ] || die "usage: ./.fork/port.sh range <upstream-sha|tag> [upstream-ref]"
	[ -f "$state" ] && die "a port is already in progress — continue/abort it first"
	[ -f "$unport_state" ] && die "an unport is in progress — finish it (continue/abort) first"
	ref="$(resolve_upstream_ref "${2:-}")"
	git rev-parse --verify --quiet "${sha}^{commit}" >/dev/null 2>&1 || die "not a commit: $sha"
	sha="$(git rev-parse "${sha}^{commit}")"
	cur="$(upstream_pointer)"
	[ -n "$cur" ] || die "no pointer yet — run ./.fork/port.sh init <sha> [ref] first"
	git rev-parse --verify --quiet "${cur}^{commit}" >/dev/null 2>&1 ||
		die "pointer $cur does not resolve — fix .fork/UPSTREAM first"
	cur="$(git rev-parse "$cur")"
	[ "$sha" = "$cur" ] && die "$sha is already the pointer — nothing to port"
	require_clean_tree
	preflight
	assert_forward "$sha"
	# The span's END must sit on the line you port from, or the next backlog would lie.
	git merge-base --is-ancestor "$sha" "$ref" 2>/dev/null ||
		die "$sha is not an ancestor of $ref — pass the ref this tag/sha belongs to"
	n="$(git rev-list --first-parent --count "$cur..$sha")"
	note "squash-porting $n upstream commits: $(git rev-parse --short "$cur")..$(git rev-parse --short "$sha")"
	# Record state BEFORE touching the tree so abort/continue always have it.
	printf 'SHA=%s\nREF=%s\nFROM=%s\n' "$sha" "$ref" "$cur" >"$state"
	if git diff --quiet "$cur" "$sha"; then
		finalize "$sha" "$ref" "$cur" # span is a no-op (already present): pointer-only port
		return 0
	fi
	rc=0
	# git-apply is ATOMIC and cannot represent delete-involved conflicts: ONE path that
	# upstream deleted but the fork modified used to abort the WHOLE span (months of
	# drift virtually guarantee one — found on a real 194-commit catch-up). Pre-classify
	# the span against the fork's tree and pull those paths OUT of the patch:
	#   upstream deleted, fork modified  -> synthetic modify/delete conflict (pause)
	#   upstream modified, fork deleted  -> synthetic delete/modify conflict (pause;
	#                                       upstream's version left in the worktree,
	#                                       exactly like a real merge would)
	#   deleted on both sides            -> nothing to port (converged)
	#   added on both sides, same blob   -> nothing to port (converged)
	#   added on both sides, different   -> synthetic add/add conflict (pause)
	# A synthetic conflict is staged below via update-index (stage1=base, stage2=ours,
	# stage3=theirs as applicable) so it pauses for review EXACTLY like an apply
	# conflict: resolve with `git add` (keep/adapt) or `git rm` (accept the deletion).
	# Upstream RENAMES stay in the patch — apply 3-ways your edits into the new path.
	local head_files interesting cls p base_b ours_b theirs_b zeros synth=""
	local excl=()
	head_files="$(git -c core.quotepath=false ls-files)"
	# One ls-files + one diff, joined in awk — no per-path git calls on a huge span.
	interesting="$(
		{
			printf '%s\n' "$head_files" | awk '{print "H\t" $0}'
			git -c core.quotepath=false diff --name-status "$cur" "$sha"
		} | awk -F'\t' '
			$1=="H" {h[$2]=1; next}
			$1=="D" {print (($2 in h) ? "DH" : "DD") "\t" $2; next}
			$1=="M" {if (!($2 in h)) print "MD\t" $2; next}
			$1=="A" {if ($2 in h) print "AH\t" $2; next}
		'
	)"
	while IFS=$'\t' read -r cls p; do
		[ -z "$p" ] && continue
		case "$cls" in
		DD) # deleted upstream AND in the fork — converged; nothing to apply
			excl+=(":(exclude,literal)$p")
			note "already deleted in your fork (converged): $p"
			;;
		DH) # upstream deleted; fork still has it — conflict only if the fork CHANGED it
			base_b="$(git rev-parse --verify --quiet "$cur:$p" 2>/dev/null || true)"
			ours_b="$(git rev-parse --verify --quiet "HEAD:$p" 2>/dev/null || true)"
			if [ -n "$base_b" ] && [ "$base_b" = "$ours_b" ]; then
				continue # fork never touched it: the patch deletes it cleanly
			fi
			excl+=(":(exclude,literal)$p")
			synth="${synth:+$synth
}MD	$p"
			;;
		MD) # upstream modified; fork deleted it
			excl+=(":(exclude,literal)$p")
			synth="${synth:+$synth
}DM	$p"
			;;
		AH) # upstream added; fork already has a file there
			ours_b="$(git rev-parse --verify --quiet "HEAD:$p" 2>/dev/null || true)"
			theirs_b="$(git rev-parse --verify --quiet "$sha:$p" 2>/dev/null || true)"
			excl+=(":(exclude,literal)$p")
			if [ -n "$ours_b" ] && [ "$ours_b" = "$theirs_b" ]; then
				note "already present in your fork (identical): $p"
				continue
			fi
			synth="${synth:+$synth
}AA	$p"
			;;
		esac
	done <<EOF
$interesting
EOF
	# ONE three-way apply of the whole span. --index stages clean paths so the conflict
	# set is exactly the unmerged ones; --full-index records the blob ids --3way needs.
	# Apply's BUILT-IN rerere pass is disabled: when rerere already knows a conflict's
	# resolution it dies on its own index.lock (rc=128, conflict stages wiped — a
	# deterministic wedge, found by test). The explicit `git rerere` in the conflict
	# branch below provides the same record/replay without the collision. Apply's
	# per-file chatter ("Applied patch to X cleanly", hundreds of lines on a real span)
	# used to bury the one line that mattered — capture it; surface only what matters.
	local apply_log
	apply_log="$(mktemp)"
	git diff --binary --full-index "$cur" "$sha" -- . ${excl[@]+"${excl[@]}"} |
		git -c rerere.enabled=false apply --3way --index >"$apply_log" 2>&1 || rc=$?
	# merge=ours overrides: git-apply fired no merge driver, so re-assert ours.
	while IFS= read -r p; do
		[ -z "$p" ] && continue
		if git ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
			if git checkout HEAD -- "$p" 2>/dev/null; then note "kept ours (merge=ours): $p"; fi
		fi
	done < <(merge_ours_paths)
	# Stage the synthetic delete/add conflicts (after the merge=ours re-assert, so an
	# ours-pinned path still pauses here like it would in a per-commit port — merge
	# drivers never fire on delete conflicts either).
	if [ -n "$synth" ]; then
		zeros="$(git rev-parse HEAD | awk '{gsub(/./,"0"); print}')" # oid-length zeros
		while IFS=$'\t' read -r cls p; do
			[ -z "$p" ] && continue
			base_b="$(git ls-tree "$cur" -- "$p" | awk 'NR==1{print $1, $3}')"
			ours_b="$(git ls-tree HEAD -- "$p" | awk 'NR==1{print $1, $3}')"
			theirs_b="$(git ls-tree "$sha" -- "$p" | awk 'NR==1{print $1, $3}')"
			{
				printf '0 %s\t%s\n' "$zeros" "$p" # drop any stage-0 entry first
				case "$cls" in
				MD)
					printf '%s 1\t%s\n' "$base_b" "$p"
					printf '%s 2\t%s\n' "$ours_b" "$p"
					;;
				DM)
					printf '%s 1\t%s\n' "$base_b" "$p"
					printf '%s 3\t%s\n' "$theirs_b" "$p"
					;;
				AA)
					printf '%s 2\t%s\n' "$ours_b" "$p"
					printf '%s 3\t%s\n' "$theirs_b" "$p"
					;;
				esac
			} | git update-index --index-info
			case "$cls" in
			MD) note "CONFLICT (modify/delete): upstream deleted $p — your modified copy is in the worktree" ;;
			DM)
				mkdir -p "$(dirname "$p")" 2>/dev/null || true
				git cat-file blob "$sha:$p" >"$p" 2>/dev/null || true
				note "CONFLICT (delete/modify): you deleted $p; upstream modified it — their version left in the worktree"
				;;
			AA) note "CONFLICT (add/add): $p added on both sides with different content — your version is in the worktree" ;;
			esac
		done <<EOF
$synth
EOF
	fi
	# Pause on ANY unmerged path — an apply conflict or a synthetic one above (a span
	# whose only conflicts are delete-involved applies CLEANLY, so rc alone cannot
	# decide; the unmerged set is what is real).
	if git diff --name-only --diff-filter=U | grep -q .; then
		# Record the conflict with rerere and replay any REMEMBERED resolution into
		# the worktree (autoUpdate forced off: a replayed path must stay unmerged so
		# the banner below can flag it for review, and `continue`'s no-unmerged check
		# cannot be satisfied by an unreviewed replay).
		git -c rerere.autoUpdate=false rerere || true
		# Remember the conflict set so finalize can journal it (.fork/PORTS.md).
		git -c core.quotepath=false diff --name-only --diff-filter=U | awk '{print "CONFLICT=" $0}' >>"$state"
		printf '\nport.sh: CONFLICTS in range %s..%s. Files:\n' "$(git rev-parse --short "$cur")" "$(git rev-parse --short "$sha")" >&2
		list_conflicts
		printf 'Inspect:  ./.fork/conflict-context.sh %s..%s <file>\n' "$cur" "$sha" >&2
		printf 'Resolve + git add, then: ./.fork/port.sh continue   (or abort)\n' >&2
		printf '(per-file git-apply details: %s)\n' "$apply_log" >&2
		exit 1
	fi
	if [ "$rc" -ne 0 ]; then
		# Hard failure with nothing to resolve: show the log MINUS the per-file noise,
		# so the actual error is the first thing visible instead of line 800.
		grep -Ev '^(Applied patch to|Falling back|Performed three-way|U )' "$apply_log" >&2 || true
		rm -f "$apply_log"
		git reset -q --hard HEAD
		rm -f "$state"
		die "range apply failed (rc=$rc) with no conflicts to resolve — see the error above.
       Delete-involved and add/add conflicts are handled (they pause); what is left is
       usually a blob missing locally (git fetch upstream, then retry) or an exotic
       rename — if it persists, port that stretch per-commit: ./.fork/port.sh next"
	fi
	rm -f "$apply_log"
	finalize "$sha" "$ref" "$cur"
}

cmd_continue() {
	# An unport (revert) in progress takes precedence — `git revert` already rewound the
	# pointer, so we only need to finalize the gated commit.
	if [ -f "$unport_state" ]; then
		local usha prev prev_ref
		usha="$(awk -F= '/^UNPORT=/{print $2}' "$unport_state")"
		prev="$(awk -F= '/^PREV=/{print $2}' "$unport_state")"
		prev_ref="$(awk -F= '/^PREV_REF=/{print $2}' "$unport_state")"
		[ -n "$usha" ] || die "unport state file is corrupt (no SHA) — ./.fork/port.sh abort and retry"
		[ -n "$prev" ] || die "unport state file is corrupt (no previous pointer) — ./.fork/port.sh abort and retry"
		finalize_unport "$usha" "$prev" "$prev_ref"
		return
	fi
	[ -f "$state" ] || die "no port in progress"
	local sha ref from
	sha="$(awk -F= '/^SHA=/{print $2}' "$state")"
	ref="$(awk -F= '/^REF=/{print $2}' "$state")"
	from="$(awk -F= '/^FROM=/{print $2}' "$state")"
	[ -n "$sha" ] || die "state file is corrupt (no SHA) — ./.fork/port.sh abort and retry"
	finalize "$sha" "$ref" "$from"
}

cmd_abort() {
	# An unport uses `git revert`, which DOES leave a sequencer/REVERT_HEAD (unlike a
	# --no-commit cherry-pick), so `git revert --abort` is the clean undo here.
	if [ -f "$unport_state" ]; then
		git revert --abort >/dev/null 2>&1 || git reset -q --hard HEAD
		git reset -q --merge >/dev/null 2>&1 || true
		rm -f "$unport_state"
		note "unport aborted; tree restored to HEAD"
		return
	fi
	[ -f "$state" ] || die "no port in progress"
	# `cherry-pick --no-commit` leaves no sequencer, so --abort won't work; hard-reset
	# the worktree/index back to HEAD and drop the state.
	git reset -q --hard HEAD
	git reset -q --merge >/dev/null 2>&1 || true
	rm -f "$state"
	note "port aborted; tree restored to HEAD"
}

case "${1:-}" in
init)
	shift
	cmd_init "$@"
	;;
list)
	shift
	cmd_list "$@"
	;;
next)
	shift
	cmd_next "$@"
	;;
one)
	shift
	cmd_one "$@"
	;;
range)
	shift
	cmd_range "$@"
	;;
revert)
	shift
	cmd_revert "$@"
	;;
continue) cmd_continue ;;
abort) cmd_abort ;;
status) cmd_status ;;
"" | -h | --help)
	sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
	;;
*) die "unknown subcommand: $1 (try ./.fork/port.sh --help)" ;;
esac
