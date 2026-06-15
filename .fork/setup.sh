#!/usr/bin/env bash
# .fork/setup.sh — wire THIS clone's per-clone config (see Fork Maintenance in your
# CLAUDE.md/AGENTS.md).
#
#   ./.fork/setup.sh           apply the per-clone git config (idempotent)
#   ./.fork/setup.sh --check   report wiring status, change nothing; exit 1 if unwired
#
# git config is per-clone state — neither `git clone` nor copied files carry it — so a
# fresh clone of an installed fork is HALF-PROTECTED until this runs: no hooks (the
# integration gate and the commit-msg reminder are silently off for manual commits;
# port.sh still gates its own commits inline), no merge=ours driver during ports, no
# rerere. This script SHIPS WITH THE FORK precisely so any clone can wire itself with
# one in-repo command, without a fork-flow kit checkout. The kit's install.sh --setup
# applies this same config (it runs this script), plus the one-time GitHub wiring
# (origin/upstream remotes, custom/main) that needs gh and is repo state, not config.
# Keep the config list below in sync with install.sh's manual-setup echo.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

mode="${1:-}"
case "$mode" in
"" | --check) ;;
*)
	echo "usage: ./.fork/setup.sh [--check]" >&2
	exit 2
	;;
esac

# The mergiraf driver depends on whether the binary exists: the real syntax-aware
# driver when it does, Git's text merge as a safe fallback when it does not (same
# rule as install.sh --setup; .gitattributes ships its merge=mergiraf lines ACTIVE).
mergiraf_driver='mergiraf merge --git %O %A %B -s %S -x %X -y %Y -p %P -l %L'
fallback_driver='git merge-file -L %X -L %S -L %Y %A %O %B'

# Is HOOK ($1) wired in the EFFECTIVE hooks dir? git resolves core.hooksPath in
# `--git-path hooks`, so this covers both the core.hooksPath=.fork/hooks setup and
# per-hook symlinks into .git/hooks. $2 is a needle the kit's copy always contains.
hook_wired() {
	local d
	d="$(git rev-parse --git-path hooks 2>/dev/null)"
	[ -n "$d" ] && [ -f "$d/$1" ] && grep -qs "$2" "$d/$1"
}

# A project may ALREADY manage hooks (husky, lefthook, real files in .git/hooks).
# Never clobber them silently: core.hooksPath still moves to .fork/hooks (the gate
# must run first, unconditionally), but the previous hooks dir is recorded in
# fork-flow.chainHooksDir and the kit's three hooks CHAIN to the same-named hook
# there after their own logic — the project's pre-commit/commit-msg keep running and
# can still block a commit (their exit code decides). Hooks of OTHER names in that
# dir do not auto-run while core.hooksPath points at .fork/hooks; symlink any you
# need into .fork/hooks/. Prints the dir to chain, or nothing.
detect_chain_dir() {
	local cur eff h self
	cur="$(git config core.hooksPath 2>/dev/null || true)"
	# never record the kit's own hooks dir as a chain (recursion). Compare RESOLVED
	# paths (pwd -P), not strings: a hand-set absolute hooksPath may reach the same
	# dir through a symlinked prefix (macOS /var/folders -> /private/var/folders).
	self="$(cd .fork/hooks 2>/dev/null && pwd -P)"
	if [ -n "$cur" ] && [ "$cur" != ".fork/hooks" ] &&
		[ "$(cd "$cur" 2>/dev/null && pwd -P)" != "$self" ]; then
		printf '%s' "$cur"
		return 0
	fi
	if [ -z "$cur" ]; then
		# default .git/hooks: chain only when a REAL (non-kit) hook we would shadow exists
		eff="$(git rev-parse --git-path hooks 2>/dev/null)"
		for h in pre-commit pre-merge-commit commit-msg; do
			if [ -n "$eff" ] && [ -x "$eff/$h" ] && ! grep -qs '_merge-gate' "$eff/$h" && ! grep -qs 'fork-flow' "$eff/$h"; then
				printf '%s' "$eff"
				return 0
			fi
		done
		# DORMANT husky: a fresh clone carries the project's committed .husky/ hooks but
		# no install has run yet, so core.hooksPath is still unset — without this, setup
		# records NO chain and the project's hooks are silently off until the first
		# install's takeover + re-setup cycle (observed live: the takeover happened in
		# the middle of a full verify's install). Record the dir up front. After the
		# takeover, re-running setup records whatever husky pointed hooksPath at
		# (.husky/_) via the branch above.
		for h in pre-commit pre-merge-commit commit-msg; do
			if [ -f ".husky/$h" ] && ! grep -qs 'fork-flow' ".husky/$h"; then
				printf '%s' ".husky"
				return 0
			fi
		done
	fi
	return 0
}

rc=0
chk_cfg() { # <config-key> <wanted> <label>
	local cur
	cur="$(git config "$1" 2>/dev/null || true)"
	if [ "$cur" = "$2" ]; then
		printf '  ok       %s\n' "$3"
	else
		printf '  MISSING  %s   (have: %s)\n' "$3" "${cur:-<unset>}"
		rc=1
	fi
}

if [ "$mode" = "--check" ]; then
	if hook_wired pre-commit _merge-gate && hook_wired pre-merge-commit _merge-gate && hook_wired commit-msg fork-flow; then
		printf '  ok       hooks (integration gate + commit-msg reminder)\n'
	else
		printf '  MISSING  hooks — manual commits/merges are UNGATED in this clone\n'
		cur="$(git config core.hooksPath 2>/dev/null || true)"
		if [ -n "$cur" ] && [ "$cur" != ".fork/hooks" ]; then
			printf '           (core.hooksPath = %s — another hook manager re-pointed it?\n' "$cur"
			printf '            re-run ./.fork/setup.sh: it takes the hooks back and CHAINS those)\n'
		fi
		rc=1
	fi
	chain="$(git config fork-flow.chainHooksDir 2>/dev/null || true)"
	[ -n "$chain" ] && printf '  ok       chained hooks: %s (project hooks run after the gate)\n' "$chain"
	chk_cfg rerere.enabled true 'rerere.enabled (replay past conflict resolutions)'
	chk_cfg rerere.autoUpdate false 'rerere.autoUpdate=false (replays must pass review)'
	chk_cfg merge.conflictStyle zdiff3 'merge.conflictStyle zdiff3'
	chk_cfg merge.ours.driver true 'merge.ours.driver (merge=ours overrides hold during ports)'
	if command -v mergiraf >/dev/null 2>&1; then
		chk_cfg merge.mergiraf.driver "$mergiraf_driver" 'merge.mergiraf driver (binary present)'
	else
		chk_cfg merge.mergiraf.driver "$fallback_driver" 'merge.mergiraf fallback driver (binary not installed)'
	fi
	if git remote get-url upstream >/dev/null 2>&1; then
		printf '  ok       upstream remote\n'
	else
		printf '  MISSING  upstream remote (cannot be guessed: git remote add upstream <url>)\n'
		rc=1
	fi
	if [ "$rc" -ne 0 ]; then
		printf 'setup.sh: this clone is NOT fully wired — run ./.fork/setup.sh\n' >&2
	else
		printf 'setup.sh: fully wired\n' >&2
	fi
	exit "$rc"
fi

git config rerere.enabled true
git config rerere.autoUpdate false # replays must pass review, never auto-stage
git config merge.conflictStyle zdiff3
git config merge.ours.driver true
chain="$(detect_chain_dir)"
if [ -n "$chain" ]; then
	git config fork-flow.chainHooksDir "$chain"
	echo "  found existing hooks in $chain — the kit's pre-commit/pre-merge-commit/commit-msg"
	echo "  CHAIN to the same-named hooks there (gate first, then yours; other hook names in"
	echo "  $chain do not auto-run — symlink any you need into .fork/hooks/)"
fi
git config core.hooksPath .fork/hooks # commit-msg reminder + both integration-gate hooks
if grep -qs '"prepare"[[:space:]]*:.*husky' package.json; then
	echo "  NOTE: husky re-points core.hooksPath on every dependency install — re-run"
	echo "        ./.fork/setup.sh after installs (verify.sh full and port.sh warn when unwired)"
fi
if command -v mergiraf >/dev/null 2>&1; then
	git config merge.mergiraf.name mergiraf
	git config merge.mergiraf.driver "$mergiraf_driver"
	echo "  git config set: rerere, zdiff3, merge.ours.driver, merge.mergiraf, core.hooksPath"
else
	git config merge.mergiraf.name "mergiraf fallback"
	git config merge.mergiraf.driver "$fallback_driver"
	echo "  git config set: rerere, zdiff3, merge.ours.driver, merge.mergiraf fallback, core.hooksPath"
	echo "  NOTE: mergiraf not installed — syntax-aware merges are inactive; install it and re-run ./.fork/setup.sh"
fi
if ! git remote get-url upstream >/dev/null 2>&1; then
	echo "  NOTE: no 'upstream' remote — porting needs one: git remote add upstream <url> && git fetch upstream"
	echo "        (first-time GitHub wiring — gh fork, origin, custom/main — is install.sh --setup's job)"
fi
echo "setup.sh: clone wired."
