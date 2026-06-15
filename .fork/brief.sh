#!/usr/bin/env bash
# .fork/brief.sh — deterministic pre-merge risk briefing (see Fork Maintenance in your CLAUDE.md/AGENTS.md).
#
#   ./.fork/brief.sh <merge-base> <upstream-head>
#
# Prints only:
#   1. the upstream range and the files it changes
#   2. .fork/CHANGES.md entries whose Touches/Symbols paths are in that change set
#   3. the Verify: command for each hit entry
#   4. merge=ours paths upstream changed over the range
# It makes no decisions; it surfaces what to look at before you merge.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Shared parsing/matching helpers (split_field, symbol_path, glob_match,
# glob_match_any, merge_ours_paths) — one copy for all scripts, see .fork/lib.sh.
# shellcheck source=/dev/null
. .fork/lib.sh

if [ "$#" -ne 2 ]; then
  echo "usage: ./.fork/brief.sh <merge-base> <upstream-head>" >&2
  exit 2
fi
base="$1"; head="$2"
for ref in "$base" "$head"; do
  git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null \
    || { echo "error: not a commit: $ref" >&2; exit 2; }
done

changes=".fork/CHANGES.md"
# Detect renames/copies (-M -C) regardless of the user's diff.renames setting, so
# a customization whose file upstream MOVED is still flagged: the old path shows up
# as the source of an R/C line. Columns are <status>\t<path>[\t<newpath>].
namestatus="$(git diff --name-status -M -C "$base..$head")"
# Both the old and the new path feed is_incoming, so either side can match.
incoming="$(printf '%s\n' "$namestatus" | awk -F'\t' 'NF>=2{print $2} NF>=3{print $3}')"
# Match registry anchors glob-aware (so a "src/icons/*.svg" anchor catches an
# incoming "src/icons/one.svg"), consistent with audit.sh/verify.sh. Literal anchors
# (the common case) take a fast fixed-string grep first — which also matches a real
# path that itself contains glob metacharacters; only true glob anchors fall back to
# the per-line glob scan.
is_incoming() {
  printf '%s\n' "$incoming" | grep -Fxq -- "$1" && return 0
  glob_match_any "$1" "$incoming"
}
# If <path> was renamed/copied upstream, echo its new path (else nothing).
renamed_to() { printf '%s\n' "$namestatus" | awk -F'\t' -v p="$1" '$1 ~ /^[RC]/ && $2==p {print $3; exit}'; }
# True if <path> was DELETED upstream over the range with no rename/copy detected
# (a rename + heavy edit shows up as D + A, which git does not classify as R/C).
deleted_upstream() { printf '%s\n' "$namestatus" | awk -F'\t' -v p="$1" '$1=="D" && $2==p {f=1} END{exit !f}'; }

printf '== upstream range ==\n%s..%s\n\n' \
  "$(git rev-parse --short "$base")" "$(git rev-parse --short "$head")"

printf '== incoming files ==\n'
if [ -z "$namestatus" ]; then printf '(none)\n'; else printf '%s\n' "$namestatus"; fi

# --- CHANGES.md entries hit by incoming paths --------------------------------
heading=""; touches=""; symbols=""; verify=""; any=0
flush() {
  [ -z "$heading" ] && return 0
  # Candidate paths: Touches tokens + the path part of each Symbols "name@path".
  # Keep those whose anchor matches an incoming path (glob-aware via is_incoming);
  # dedup. The matching `case` lives in .fork/lib.sh as a sourced function, so it
  # is safe to call inside this $( ) — a `case` written literally here would hit
  # the bash 3.2 command-substitution mis-parse, but a function call does not.
  # if/then (not &&) so each loop body returns 0 — otherwise a final non-matching
  # candidate makes the loop exit nonzero and, under `set -o pipefail`, the whole
  # $( ) fails and `set -e` aborts the script mid-briefing.
  matched="$(
    {
      split_field "$touches"
      split_field "$symbols" | while IFS= read -r s; do symbol_path "$s"; done
    } | while IFS= read -r p; do
      if [ -n "$p" ] && is_incoming "$p"; then printf '%s\n' "$p"; fi
    done | awk 'NF && !seen[$0]++'
  )"
  if [ -n "$matched" ]; then
    any=1
    printf '\n* %s\n' "$heading"
    printf '%s\n' "$matched" | while IFS= read -r p; do
      [ -z "$p" ] && continue
      nw="$(renamed_to "$p")"
      if [ -n "$nw" ]; then printf '    matched: %s  -> RENAMED upstream to %s\n' "$p" "$nw"
      elif deleted_upstream "$p"; then printf '    matched: %s  -> DELETED upstream (find its new home)\n' "$p"
      else printf '    matched: %s\n' "$p"; fi
    done
    [ -n "$verify" ] && printf '    verify:%s\n' "$verify"
  fi
  heading=""; touches=""; symbols=""; verify=""
}

printf '\n== CHANGES.md entries hit ==\n'
if [ ! -f "$changes" ]; then
  printf '(no %s)\n' "$changes"
else
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "## "*)        flush; heading="${line#"## "}" ;;
      # Only capture fields once a heading is open, so a stray field before the first
      # "## " heading is ignored rather than attached to the first entry.
      [Tt]ouches:*)  [ -n "$heading" ] && touches="${line#*:}" ;;
      [Ss]ymbols:*)  [ -n "$heading" ] && symbols="${line#*:}" ;;
      [Vv]erify:*)   [ -n "$heading" ] && verify="${line#*:}" ;;
    esac
  done < "$changes"
  flush
  [ "$any" -eq 0 ] && printf '(no entries match incoming files)\n'
fi

# --- unregistered fork changes (this briefing's blind spot, surfaced) ----------
# The section above can only flag entries the registry KNOWS about: files your own
# commits changed that no anchor covers are invisible to it, so its "(no entries
# match incoming files)" would be FALSE COMFORT exactly when protection is missing.
# Same scan as audit.sh section 2 (lib.sh's fork_unregistered_files), scoped from the
# fork's own porting base — .fork/UPSTREAM, or merge-base on a never-ported fork —
# NOT from this briefing's <merge-base> argument (often an upstream SHA mid-backlog,
# which would walk a misleading range). Guarded so a corrupt pointer or missing
# upstream ref degrades to silence here (audit is where that fails loudly, exit 3).
ub="$(upstream_base 2>/dev/null)" || ub=""
if [ -n "$ub" ]; then
  unregistered="$(fork_unregistered_files "$ub")"
  # Only files still IN the tree are actionable here — a path your history touched
  # that has since vanished (upstream renamed/deleted it) cannot be registered or
  # deleted and would re-warn on every briefing forever. audit.sh does the full
  # tracked/deleted-by-you/historical accounting; the briefing keeps to live risk.
  live=""
  gone=0
  while IFS= read -r f; do
    if [ -z "$f" ]; then continue; fi
    if git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
      live="${live:+$live
}$f"
    else
      gone=$((gone + 1))
    fi
  done <<EOF
$unregistered
EOF
  if [ -n "$live" ]; then
    printf '\n== WARNING: unregistered fork changes (risk above is UNDERSTATED) ==\n'
    printf '%s\n' "$live" | while IFS= read -r f; do [ -n "$f" ] && printf '  %s\n' "$f"; done
    printf '  -> no registry entry anchors these files, so neither this briefing nor the\n'
    printf '     gate can protect them. Register with the fork-change skill (or delete\n'
    printf '     them), then re-run brief.\n'
    [ "$gone" -gt 0 ] && printf '  (+%d earlier unregistered path(s) no longer in the tree — see audit.sh)\n' "$gone"
  fi
fi

# --- merge=ours paths upstream changed ---------------------------------------
printf '\n== merge=ours paths changed upstream ==\n'
if [ ! -f .gitattributes ]; then
  printf '(no .gitattributes)\n'
else
  found=0
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    if [ -n "$(git diff --name-only "$base..$head" -- "$path")" ]; then
      printf '%s\n' "$path"; found=1
    fi
  done < <(merge_ours_paths)
  [ "$found" -eq 0 ] && printf '(none changed)\n'
fi

exit 0
