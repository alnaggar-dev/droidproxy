#!/usr/bin/env bash
# .fork/lib.sh — shared helpers for the fork-flow scripts (see Fork Maintenance in your CLAUDE.md/AGENTS.md).
#
# This file is SOURCED, never executed. brief.sh, conflict-context.sh, audit.sh
# and verify.sh each `. .fork/lib.sh` (after they cd to the repo root) so the
# registry/merge=ours parsing and path-matching live in ONE place instead of
# being copy-pasted. Change the grammar here and every script follows.
#
# Depends only on git/awk/grep. Must stay bash 3.2 (macOS /bin/bash) safe:
#   - no associative arrays (bash 4+);
#   - keep every `case` INSIDE a function defined here. A `case` literally
#     written inside a $(...) mis-parses on 3.2 (it eats the pattern's ')'),
#     but a function that merely CONTAINS a `case` is safe to CALL inside $(...).
#     That is the whole reason matching is centralized as functions.

# Split a Touches/Symbols field on ';' and ',' ONLY (never whitespace, so a path
# may contain spaces) with globbing disabled (so '*'/'**' reach the caller
# verbatim). Emits one trimmed, non-empty token per line.
split_field() {
	local s="$1" tok glob_off=0
	case "$-" in *f*) glob_off=1 ;; *) set -f ;; esac
	local IFS=';,'
	for tok in $s; do
		tok="${tok#"${tok%%[![:space:]]*}"}" # trim leading whitespace
		tok="${tok%"${tok##*[![:space:]]}"}" # trim trailing whitespace
		[ -n "$tok" ] && printf '%s\n' "$tok"
	done
	[ "$glob_off" -eq 0 ] && set +f
}

# name@path -> path (text after the LAST '@'); prints nothing when there is no
# '@'. Uses parameter expansion, not `case`, so it is safe even inline. Always
# returns 0 so `x="$(symbol_path …)"` never trips `set -e` on a token with no '@'.
symbol_path() {
	local s="$1"
	if [ "${s#*@}" != "$s" ]; then printf '%s\n' "${s##*@}"; fi
	return 0
}

# Does anchor PATTERN ($1) match the single FILE ($2)? Literal equality first, so a
# real path that itself contains glob metacharacters (e.g. "app/[id].tsx") still
# matches; otherwise treat PATTERN as a shell glob ("src/icons/*.svg").
glob_match() {
	[ "$2" = "$1" ] && return 0
	# shellcheck disable=SC2254  # $1 is intentionally an unquoted glob pattern
	case "$2" in $1) return 0 ;; esac
	return 1
}

# Does glob PATTERN ($1) match ANY path in the newline-separated LIST ($2)?
glob_match_any() {
	local pattern="$1" f
	while IFS= read -r f; do
		[ -z "$f" ] && continue
		# shellcheck disable=SC2254  # $pattern is intentionally an unquoted glob
		case "$f" in $pattern) return 0 ;; esac
	done <<EOF
$2
EOF
	return 1
}

# Is FILE ($1) covered by ANY registry anchor in the newline-separated LIST ($2)?
# The inverse of glob_match_any: here the LIST holds glob PATTERNS (the registry's
# Touches/Symbols anchors) and FILE is one literal path. Glob matching is not
# symmetric — the pattern carries the '*' — so we test each anchor against the one
# file. A file counts as registered if it equals OR is glob-matched by an anchor,
# so a glob anchor like src/icons/*.svg covers src/icons/a.svg. Shared by audit.sh's
# unregistered scan and the commit-msg reminder so the two can never disagree.
path_registered() {
	local f="$1" reg="$2" p
	while IFS= read -r p; do
		[ -z "$p" ] && continue
		glob_match "$p" "$f" && return 0
	done <<EOF
$reg
EOF
	return 1
}

# Is PATH ($1) part of the fork-flow toolkit itself rather than the project's own
# code? These are excluded from the "unregistered customization" checks (audit.sh's
# scan and the commit-msg reminder). One list, shared by both, so what counts as a
# customization is defined in exactly one place.
toolkit_path() {
	case "$1" in
	.fork/* | .fork-flow/* | .claude/* | .pi/* | .omp/skills/* | .agents/skills/* | .factory/skills/* | .gitattributes | AGENTS.md | CLAUDE.md | .github/workflows/fork-flow-gate.yml) return 0 ;;
	# (.fork/* already covers .fork/UPSTREAM, .fork/CHANGES.md, etc. The single
	# .github entry is the kit's CI gate workflow — the fork's OWN workflows stay
	# registrable customizations.)
	esac
	return 1
}

# Is the integration gate wired in THIS clone? git config is per-clone state — neither
# `git clone` nor copied files carry it — so a fresh clone has NO hooks until
# ./.fork/setup.sh runs there. Checks the EFFECTIVE hooks dir (git resolves
# core.hooksPath) for a pre-commit that runs the kit's _merge-gate — covers both the
# core.hooksPath=.fork/hooks setup and per-hook symlinks into .git/hooks. Shared by
# port.sh (preflight + the inline-gate fallback) and verify.sh (the post-install
# unwire warning: a hook manager like husky re-points core.hooksPath from a `prepare`
# script during the very install a full verify runs). NOTE: this is a
# pre-commit-only SENTINEL — the supported wiring is one core.hooksPath setting, so a
# wired pre-commit implies the whole set; setup.sh --check is the stricter audit that
# verifies all three hooks individually (a hand-built partial wiring satisfies this
# sentinel but fails --check).
hooks_gate_wired() {
	local d
	d="$(git rev-parse --git-path hooks 2>/dev/null)"
	[ -n "$d" ] && [ -f "$d/pre-commit" ] && grep -qs '_merge-gate' "$d/pre-commit"
}

# The last upstream commit ported into this fork: the first non-comment, non-empty
# token of .fork/UPSTREAM (see that file). Prints nothing when the file is absent or
# holds only comments (a brand-new fork that has not ported yet). One SHA, trimmed.
upstream_pointer() {
	[ -f .fork/UPSTREAM ] || return 0
	awk 'NF && $1 !~ /^#/ { print $1; exit }' .fork/UPSTREAM
}

# The upstream REF the pointer was ported from (optional second token on the pointer
# line, e.g. "<sha> upstream/main"). Lets audit.sh warn when you pass a different
# --upstream than what was actually tracked (a retarget). Prints nothing if absent.
upstream_pointer_ref() {
	[ -f .fork/UPSTREAM ] || return 0
	awk 'NF && $1 !~ /^#/ { print $2; exit }' .fork/UPSTREAM
}

# The strict port trailer. EVERY port commit (and the one-time pointer-init commit)
# carries exactly one of these, naming the full upstream SHA it advances the pointer
# to. This is the SOLE signal that a commit is a port — NOT "it touches .fork/UPSTREAM"
# (an accidental `git add -A` could stage the pointer into an ordinary commit and, on
# the old OR-heuristic, make audit skip that commit's files and the commit-msg nag go
# quiet). A trailer cannot be injected by a stray add, so it has no such false
# positive. PORT_TRAILER is for a real ported commit; INIT_TRAILER for the first
# pointer bump on a fork that has never ported (nothing was cherry-picked).
PORT_TRAILER='Fork-Flow-Port'
INIT_TRAILER='Fork-Flow-Port-Init' # written by port.sh init; matched by is_port_init_commit below
# A `port.sh range` catch-up commit carries, ALONGSIDE its Fork-Flow-Port trailer, a
# Fork-Flow-Port-From trailer naming the OLD pointer (the squashed span's start).
# Write-only forensics: the strict port parser below does NOT match it (after
# "Fork-Flow-Port" it requires ":" or "-Init:"), so audit/hooks treat a range commit
# exactly like any other port, and `port.sh revert` rewinds via the pointer file as
# usual. Nothing parses this key; it exists for the human reading `git log`.
# shellcheck disable=SC2034  # written by port.sh, parsed by nobody (forensic trailer)
FROM_TRAILER='Fork-Flow-Port-From'

# Extract the SHA from a Fork-Flow-Port[-Init] trailer in commit-message TEXT on
# STDIN (the LAST such trailer wins, matching git-trailer semantics). Prints the SHA
# (a FULL 40- or 64-hex id only; an abbreviated/edited value is ignored so it can't
# masquerade as a port) or nothing. The stdin form lets the commit-msg hook parse the
# message FILE before a commit exists; port_trailer_sha wraps it for an existing commit.
port_trailer_sha_stream() {
	awk -v p="$PORT_TRAILER" '
		{ line=$0; sub(/^[[:space:]]+/,"",line)
		  if (line ~ "^" p "(-Init)?:") {
		    s=line; sub(/^[^:]*:[[:space:]]*/,"",s); sub(/[[:space:]]+$/,"",s)
		    if (s ~ /^[0-9a-fA-F]+$/ && (length(s)==40 || length(s)==64)) last=s
		    else last="" } }
		END { if (last!="") print last }'
}

# Extract the Fork-Flow-Port[-Init] SHA from commit $1's message. Always returns 0 so
# `x="$(port_trailer_sha …)"` never trips set -e.
port_trailer_sha() {
	git log -1 --format='%B' "$1" 2>/dev/null | port_trailer_sha_stream
	return 0
}

# The base commit for "what is mine vs upstream" in a commit-by-commit fork. Uses the
# .fork/UPSTREAM pointer (the last ported upstream commit). On a fork that has NOT
# ported yet (empty pointer) it falls back to merge-base(HEAD, $1) with a note. But a
# NON-EMPTY pointer that does NOT resolve to a commit is a HARD ERROR (exit 3): that
# means corruption — a bad SHA, a dropped object, or an upstream force-push that
# orphaned it — and silently falling back to merge-base would HIDE it (the old
# behavior). $1 is the upstream ref (default upstream/main).
upstream_base() {
	local upstream="${1:-upstream/main}" ptr
	ptr="$(upstream_pointer)"
	if [ -n "$ptr" ]; then
		if git rev-parse --verify --quiet "${ptr}^{commit}" >/dev/null 2>&1; then
			git rev-parse "$ptr"
			return 0
		fi
		printf 'error: .fork/UPSTREAM pointer %s does not resolve to a commit\n' "$ptr" >&2
		printf '       (bad SHA, missing object, or an upstream force-push orphaned it).\n' >&2
		printf '       fetch upstream, or fix .fork/UPSTREAM, before trusting audit/port output.\n' >&2
		return 3
	fi
	printf 'note: .fork/UPSTREAM not set yet — using merge-base(HEAD, %s) as base\n' "$upstream" >&2
	git merge-base HEAD "$upstream"
}

# Is commit $1 an upstream PORT commit (it integrates one upstream commit, or is the
# one-time pointer-init) rather than your own customization work? TRUE iff its message
# carries a strict Fork-Flow-Port[-Init] trailer — trailer-only, no "touches
# .fork/UPSTREAM" fallback (see PORT_TRAILER). Used by audit.sh's unregistered scan
# and propose-upstream so a ported upstream commit is never mistaken for a
# customization, and a stray pointer in an ordinary commit is never mistaken for a port.
is_upstream_port_commit() {
	[ -n "$(port_trailer_sha "$1")" ]
}

# Is commit $1 the one-time pointer INIT — or a sanctioned `port.sh init --force`
# re-target after an upstream force-push/branch switch? TRUE iff its message carries
# the Fork-Flow-Port-Init trailer specifically. port_trailer_sha matches Init too (an
# init IS a port for skip/anchoring purposes); this narrower test lets audit.sh treat
# an init as a SEQUENCE RESET in its port-order check — a forced re-init starts a new
# upstream line on purpose and must not be flagged as "unrelated to the previous port".
is_port_init_commit() {
	git log -1 --format='%B' "$1" 2>/dev/null | grep -Eq "^[[:space:]]*${INIT_TRAILER}:"
}

# The strict UNPORT trailer. A `port.sh revert` commit carries exactly one, naming the
# full upstream SHA whose port it undoes. `git revert` of the port commit already
# rewinds .fork/UPSTREAM (the port advanced it in that same commit), so this trailer is
# how audit.sh tells a legit pointer-rewind from a tamper, how it excludes a reverted
# port from the newest-trailer check, and how the commit-msg hook accepts a staged
# pointer that moved BACKWARD. Symmetric to PORT_TRAILER; there is no init variant.
UNPORT_TRAILER='Fork-Flow-Unport'

# Extract the SHA from a Fork-Flow-Unport trailer in commit-message TEXT on STDIN (the
# LAST such trailer wins; a FULL 40-/64-hex id only, like the port parser). Mirror of
# port_trailer_sha_stream; the stdin form lets the commit-msg hook parse the message
# FILE before a commit exists. The two trailers are disjoint (Fork-Flow-Port vs
# Fork-Flow-Unport), so neither parser matches the other.
unport_trailer_sha_stream() {
	awk -v p="$UNPORT_TRAILER" '
		{ line=$0; sub(/^[[:space:]]+/,"",line)
		  if (line ~ "^" p ":") {
		    s=line; sub(/^[^:]*:[[:space:]]*/,"",s); sub(/[[:space:]]+$/,"",s)
		    if (s ~ /^[0-9a-fA-F]+$/ && (length(s)==40 || length(s)==64)) last=s
		    else last="" } }
		END { if (last!="") print last }'
}

# Extract the Fork-Flow-Unport SHA from commit $1's message. Always returns 0 so
# `x="$(unport_trailer_sha …)"` never trips set -e.
unport_trailer_sha() {
	git log -1 --format='%B' "$1" 2>/dev/null | unport_trailer_sha_stream
	return 0
}

# Is commit $1 an UNPORT (a `port.sh revert`)? TRUE iff it carries a Fork-Flow-Unport
# trailer. audit.sh treats these as legit pointer movers (they rewind the pointer) and
# skips them in the unregistered scan, exactly like ports — an unport's diff is upstream
# churn it reverses, never your customization.
is_upstream_unport_commit() {
	[ -n "$(unport_trailer_sha "$1")" ]
}

# Parse registry text from STDIN → every anchor path (each Touches token + the path
# part of each Symbols name@path), one per line, de-duplicated. The stdin form lets
# a caller match against the registry as a COMMIT will ship it — e.g. pipe in
# `git show :.fork/CHANGES.md` (the index copy) instead of the working tree, so an
# edited-but-unstaged CHANGES.md can't mask a missing entry (see the commit-msg hook).
#
# ENTRY-AWARE: a Touches/Symbols line counts only INSIDE a "## " entry, exactly like
# verify.sh/brief.sh/conflict-context.sh. Otherwise this stream parser would treat a
# stray field (e.g. one left above the first heading by a bad edit) as registered
# while the gate sees it as belonging to no entry — the two would disagree.
registry_paths_stream() {
	local line tok in_entry=0
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
		"## "*) in_entry=1 ;;
		[Tt]ouches:*) if [ "$in_entry" = 1 ]; then split_field "${line#*:}"; fi ;;
		[Ss]ymbols:*) if [ "$in_entry" = 1 ]; then split_field "${line#*:}" | while IFS= read -r tok; do symbol_path "$tok"; done; fi ;;
		esac
	done | awk 'NF && !seen[$0]++'
}

# Validate registry grammar (file $1, default .fork/CHANGES.md). Prints each problem
# to stderr; returns 1 on any HARD error (gate must fail), else 0. It guards ONLY the
# silent-drop traps, deliberately tolerating the rest of the Markdown so a legitimate
# human-written registry is never rejected:
#   HARD ERROR (would silently drop/mis-attribute a Verify):
#     - a malformed level-2 heading "##" with no following space ("##custom: x") —
#       its Verify: would otherwise overwrite the PREVIOUS entry's, dropping it; and
#     - an EMPTY "## " heading (no slug after trimming): check_entry() early-returns
#       on an empty heading, so that entry's Verify would never run.
#   IGNORED (valid Markdown): the "# " title, level-3+ subheadings ("### Notes"),
#   prose, and anything inside a ``` / ~~~ fenced code block (so a documented
#   "Verify: <cmd>" example does not trip the lint).
#   WARNING ONLY (not a gate failure): a Touches/Verify/etc field before the first
#   "## " heading — the entry-aware parser already ignores it, so it cannot drop a
#   check; it is surfaced as a likely-misplaced line, nothing more.
registry_lint() {
	local changes="${1:-.fork/CHANGES.md}" line lineno=0 in_entry=0 in_fence=0 rc=0 slug
	[ -f "$changes" ] || return 0
	while IFS= read -r line || [ -n "$line" ]; do
		lineno=$((lineno + 1))
		case "$line" in
		'```'* | '~~~'*)
			[ "$in_fence" = 0 ] && in_fence=1 || in_fence=0
			continue
			;;
		esac
		[ "$in_fence" = 1 ] && continue
		case "$line" in
		"## "*)
			slug="${line#\#\# }"
			slug="${slug#"${slug%%[![:space:]]*}"}" # trim leading whitespace
			slug="${slug%"${slug##*[![:space:]]}"}" # trim trailing whitespace
			if [ -z "$slug" ]; then
				printf 'ERROR: %s:%d: empty entry heading (need "## <slug>")\n' "$changes" "$lineno" >&2
				rc=1
			else in_entry=1; fi
			;;
		"###"* | "# "* | "#") : ;; # level-1 title / level-3+ subheading — valid Markdown
		"##"*)
			printf 'ERROR: %s:%d: malformed entry heading (need "## <slug>"): %s\n' "$changes" "$lineno" "$line" >&2
			rc=1
			;;
		[Tt]ouches:* | [Ss]ymbols:* | [Vv]erify:* | [Dd]rift-if:* | [Ss]tatus:*)
			[ "$in_entry" = 0 ] && printf 'warning: %s:%d: "%s" field before any "## " heading — ignored\n' "$changes" "$lineno" "${line%%:*}" >&2
			;;
		esac
	done <"$changes"
	return "$rc"
}

# Every registry anchor path from the file $1 (default .fork/CHANGES.md, the working
# tree). Thin wrapper over registry_paths_stream so file and stdin callers share one
# parser. Prints nothing when the file is absent.
registry_paths() {
	local changes="${1:-.fork/CHANGES.md}"
	[ -f "$changes" ] || return 0
	registry_paths_stream <"$changes"
}

# Files changed by YOUR OWN commits in $1..HEAD that no registry anchor covers — the
# "unregistered customization" scan. Walks each non-merge commit, skips ports/unports
# (strict trailer detection — a stray staged pointer is NOT a port, see PORT_TRAILER),
# excludes toolkit paths, then keeps every file no Touches/Symbols anchor matches
# (glob-aware via path_registered). One file per line. Shared by audit.sh (section 2)
# and brief.sh (its unregistered-changes warning: a briefing can only flag risk for
# files the registry KNOWS about, so unregistered files mean its "(no entries match)"
# understates risk) — one implementation, so the two scans can never disagree.
# Loop bodies use if/continue (never a bare `[ … ] && cmd` tail) so a non-matching
# final iteration cannot fail the $( ) under the callers' set -e + pipefail.
# Always returns 0 so `x="$(fork_unregistered_files …)"` never trips set -e.
fork_unregistered_files() { # <base> [registry-file]
	local base="$1" changes="${2:-.fork/CHANGES.md}" reg mine f
	reg="$(registry_paths "$changes")"
	mine="$(
		git log --no-merges --format='%H' "$base..HEAD" 2>/dev/null | while IFS= read -r sha; do
			[ -z "$sha" ] && continue
			if is_upstream_port_commit "$sha" || is_upstream_unport_commit "$sha"; then continue; fi
			git diff-tree --no-commit-id --name-only -r "$sha"
		done | awk 'NF && !seen[$0]++'
	)"
	while IFS= read -r f; do
		[ -z "$f" ] && continue
		if toolkit_path "$f"; then continue; fi
		if path_registered "$f" "$reg"; then continue; fi
		printf '%s\n' "$f"
	done <<EOF
$mine
EOF
	return 0
}

# merge=ours PATTERNS declared in .gitattributes (the path/pattern field of every
# non-comment line that sets merge=ours). We parse the DECLARED pattern — not the
# files that currently resolve to merge=ours — on purpose: the backstop
# (guard_merge_ours) must still flag a pattern whose file was deleted/renamed, which
# a `git check-attr` over tracked files could never report. The path is field 1,
# EXCEPT that git lets a path with spaces be double-quoted ("space name.txt"
# merge=ours); awk's whitespace split would truncate that to `"space`, so unquote it.
# An unclosed quote is malformed: emit the remainder verbatim so guard_merge_ours
# fails loudly on it instead of it silently vanishing. Globs pass through verbatim.
# Prints nothing when there is no .gitattributes.
merge_ours_paths() {
	[ -f .gitattributes ] || return 0
	awk '
    $0 ~ /^[[:space:]]*#/ { next }
    /merge=ours/ {
      line=$0; sub(/^[[:space:]]+/,"",line)
      if (substr(line,1,1)=="\"") {
        rest=substr(line,2); q=index(rest,"\"")
        if (q>0) print substr(rest,1,q-1); else print rest
      } else {
        n=index(line," "); t=index(line,"\t")
        if (t>0 && (t<n || n==0)) n=t
        if (n>0) print substr(line,1,n-1); else print line
      }
    }' .gitattributes
}

# The fork-flow kit version installed in this fork: the integer in .fork/VERSION
# (comment lines ignored). Prints nothing on a pre-VERSION install. install.sh writes
# this file; audit.sh surfaces it so the operator can tell when a fork is on an old
# kit. Decides nothing — comparison to the shipped version is install.sh --check's job.
kit_version() {
	[ -f .fork/VERSION ] || return 0
	awk '/^[[:space:]]*#/ {next} NF {print $1; exit}' .fork/VERSION
}

# Self-test of the load-bearing parsers/matchers above — pure string work, no git,
# ~1ms. lib.sh is the one file a bad edit can silently un-protect EVERY consumer of
# (the scripts go quiet, not loud — a broken split_field means anchors stop matching
# and every gate still prints OK), so verify.sh runs this at the top of every run and
# HARD-FAILS the gate when a helper no longer answers correctly, naming the culprit.
# Negative checks use if/then, never `cmd && fail` (set -e in the caller would abort
# on the failing && list before the diagnostic prints).
lib_selftest() {
	local bad=0 out
	out="$(split_field 'a.js; b with space.txt ,c.js')"
	[ "$out" = 'a.js
b with space.txt
c.js' ] || { echo 'lib_selftest: split_field broken (";"/"," split + whitespace trim)' >&2; bad=1; }
	out="$(symbol_path 'name@src/x.ts')"
	[ "$out" = 'src/x.ts' ] || { echo 'lib_selftest: symbol_path broken (name@path -> path)' >&2; bad=1; }
	[ -z "$(symbol_path 'no-at-token')" ] || { echo 'lib_selftest: symbol_path broken (no-@ token must print nothing)' >&2; bad=1; }
	glob_match 'src/icons/*.svg' 'src/icons/a.svg' || { echo 'lib_selftest: glob_match broken (glob anchor must match)' >&2; bad=1; }
	glob_match 'app/[id].tsx' 'app/[id].tsx' || { echo 'lib_selftest: glob_match broken (literal path with glob chars must match itself)' >&2; bad=1; }
	path_registered 'src/icons/a.svg' 'src/icons/*.svg' || { echo 'lib_selftest: path_registered broken (glob anchor must cover file)' >&2; bad=1; }
	if path_registered 'src/other.js' 'src/icons/*.svg'; then
		echo 'lib_selftest: path_registered broken (must NOT cover an unrelated file)' >&2
		bad=1
	fi
	out="$(printf 'x\n\nFork-Flow-Port: 0123456789012345678901234567890123456789\n' | port_trailer_sha_stream)"
	[ "$out" = '0123456789012345678901234567890123456789' ] || { echo 'lib_selftest: port_trailer_sha_stream broken (full-sha trailer must parse)' >&2; bad=1; }
	[ -z "$(printf 'x\n\nFork-Flow-Port: 0123abc\n' | port_trailer_sha_stream)" ] || { echo 'lib_selftest: port_trailer_sha_stream broken (abbreviated sha must be ignored)' >&2; bad=1; }
	out="$(printf 'Touches: stray.js\n## e1\nTouches: a.js; b.js\n' | registry_paths_stream)"
	[ "$out" = 'a.js
b.js' ] || { echo 'lib_selftest: registry_paths_stream broken (entry-aware Touches parse)' >&2; bad=1; }
	return "$bad"
}
