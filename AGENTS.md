# AGENTS.md

## Build & Run

The Swift package lives in `src/`. Run all `swift build`, `swift run`, and `swift package` commands from there, not from the repo root.

```bash
# Preferred dev loop: kill any running DroidProxy, rebuild the .app bundle, and
# launch the freshly signed build. Use this instead of running create-app-bundle.sh
# + open by hand — it guarantees the old menu-bar process and bundled
# cli-proxy-api are stopped before the new app starts.
./dev-relaunch.sh

# Debug build (no .app bundle, no relaunch)
cd src && swift build

# Run the app manually (menu bar app — swift run does not work for LSUIElement apps)
# Build the .app bundle first, then open it:
./create-app-bundle.sh && open DroidProxy.app

# Release .app bundle at repo root
# Picks up CODESIGN_IDENTITY / APP_VERSION / TARGET_ARCH from env when present
./create-app-bundle.sh
```

`dev-relaunch.sh` is the preferred way to run DroidProxy during development. It calls `create-app-bundle.sh` (which runs `swift build -c release` and assembles the signed `.app`) after killing any running `CLIProxyMenuBar` / `cli-proxy-api` processes, then launches the fresh bundle. Do not use it for releases — those go through `.github/workflows/release.yml`.

`create-app-bundle.sh` currently builds `DroidProxy.app` at the repo root and bundles resources from `src/Sources/Resources/`.

### Notarization (local)

```bash
ditto -c -k --sequesterRsrc --keepParent "DroidProxy.app" "DroidProxy-notarize.zip"
xcrun notarytool submit "DroidProxy-notarize.zip" --keychain-profile "notarytool" --wait
xcrun stapler staple "DroidProxy.app"
```

### Sparkle update signing

```bash
src/.build/artifacts/sparkle/Sparkle/bin/sign_update DroidProxy-arm64.zip
```

## Source Of Truth

The compiled app code is under `src/`. Treat `src/Sources/**`, `src/Info.plist`, and `create-app-bundle.sh` as source of truth. There is no longer a mirrored top-level `resources/` tree — older AGENTS notes about it are stale.

## Architecture

DroidProxy is a macOS menu bar app (`LSUIElement`) with:

1. `ThinkingProxy` on `localhost:8317`, the user-facing TCP proxy.
2. Bundled `CLIProxyAPI` on `127.0.0.1:8318`, managed as a child process by `ServerManager`.

Typical request flow:

`Client -> :8317 ThinkingProxy -> :8318 CLIProxyAPI -> upstream provider`

### Current ThinkingProxy behavior

Reasoning effort is owned by **Droid CLI**, not the proxy. Each Factory custom model is registered with native reasoning metadata (`enableThinking`, `supportedReasoningEfforts`, `defaultReasoningEffort`, `reasoningEffort`) so Droid's per-session selector exposes every level the model supports, and Droid sends the chosen value in the request body. The proxy does **not** inject `thinking`, `reasoning`, `reasoning_effort`, `output_config`, `budget_tokens`, or `generationConfig.thinkingConfig` for any model — it forwards the request unchanged.

What it still does today:

- **Anthropic-Beta rewriting**: When a Claude request has `thinking.type` of `enabled`/`adaptive`/`auto`, the proxy strips `redact-thinking-2026-02-12` from the `Anthropic-Beta` header and appends the visible-thinking beta list (interleaved-thinking, prompt-caching-scope, fast-mode, etc.). Without this, Claude emits only signed empty thinking blocks.
- **Service tier (fast mode)** for Responses API paths (`/v1/responses`, `/api/v1/responses`): injects `"service_tier":"priority"` for `gpt-5.4` or `gpt-5.5` when `AppPreferences.gpt54FastMode` or `AppPreferences.gpt55FastMode` is enabled and the client did not already set `service_tier`. Fast mode is API priority and is independent of reasoning effort.
- **Gemini path rewrite**: `/v1/responses` (and `/api/v1/responses`) are rewritten to `/v1/chat/completions` for OAuth Code Assist Gemini models (the `-preview`-suffixed names) since CLIProxyAPI does not support those via the Responses API endpoint.
- **Per-request reasoning log** to `/tmp/droidproxy-debug.log`: each `POST` emits a `REQUEST REASONING:` line that extracts just `reasoning` / `reasoning_effort` / `thinking` / `output_config` / `service_tier` / `generationConfig` from the parsed body so the actual values Droid is sending are visible without dumping the whole prompt. Example: `REQUEST REASONING: model=gpt-5.5 reasoning={"effort":"xhigh","summary":"auto"}`.
- Preserves JSON key order by editing the raw JSON string instead of re-serializing (critical for Anthropic's prompt cache). The remaining helpers (`injectJSONField`, `findTopLevelFieldLocation`, etc.) exist for `processOpenAIFastMode`.

What it no longer does (removed in the Droid-CLI-thinking refactor):

- No Claude adaptive thinking injection (Opus 4.8 / Sonnet 4.6 — `thinking` + `output_config`)
- No classic `thinking.budget_tokens` injection
- No Codex `reasoning.effort` injection
- No Gemini `generationConfig.thinkingConfig` injection
- No Kimi `reasoning_effort` injection
- No `claude-opus-4-8(high)` / `gpt-5.2(xhigh)` etc. “advanced variant” suffix parsing — every level now ships in the single base entry via Droid CLI metadata
- No Max Budget Mode override
- No Amp CLI routing (the `/auth/cli-login` redirect, `/provider/*` rewrite, `ampcode.com` management forwarding, and Amp response normalization were removed when switching to mainline CLIProxyAPI)

## Auth And Providers

The current app/UI exposes four provider types:

- `claude`
- `codex`
- `gemini`
- `kimi`

Auth data lives in `~/.cli-proxy-api/` as JSON files. `AuthManager` scans that directory and reads fields like:

- `type`
- `email`
- `login`
- `expired`
- `disabled`

Behavior to know:

- Multiple accounts per provider are supported
- Per-account disable/enable is supported via the `disabled` field in each auth JSON
- The last enabled account for a provider cannot be disabled
- Provider-level toggles in `SettingsView` are separate from per-account disable flags
- Provider-level disable writes `oauth-excluded-models` into `~/.cli-proxy-api/merged-config.yaml`
- `CLIProxyAPI` hot-reloads config changes, so provider enable/disable does not require a restart
- The app watches `~/.cli-proxy-api/` for changes from both `AppDelegate` and `SettingsView`

## Key Files

| File | Role |
|---|---|
| `src/Sources/main.swift` | NSApplication entry point that instantiates `AppDelegate` and calls `NSApplicationMain`. |
| `src/Sources/AppDelegate.swift` | App lifecycle, menu bar UI, settings window, notifications, Sparkle updater, auth-directory watcher, startup ordering for the two local servers. |
| `src/Sources/ServerManager.swift` | Starts/stops bundled `cli-proxy-api`, captures logs, merges config (including injecting the remote-management `allow-remote`/`secret-key` settings from UserDefaults), handles provider enable/disable, runs Claude/Codex/Gemini login commands, and kills orphaned backend processes. |
| `src/Sources/ThinkingProxy.swift` | Raw TCP HTTP proxy that forwards requests to CLIProxyAPI. Rewrites the Anthropic-Beta header to drop `redact-thinking-2026-02-12` on Claude thinking requests, injects `service_tier=priority` on enabled Codex fast-mode models, rewrites OAuth Code Assist Gemini `/v1/responses` to `/v1/chat/completions`, and emits a `REQUEST REASONING` log line per request. Does not inject reasoning or thinking fields. |
| `src/Sources/DroidProxyModelCatalog.swift` | Authoritative catalog of DroidProxy-exposed models. Each `DroidProxyModelDefinition` carries its supported `levels` plus a `defaultLevelValue`, and `settingsEntry` always embeds Factory's native reasoning metadata (`enableThinking`, `supportedReasoningEfforts`, `defaultReasoningEffort`, `reasoningEffort`) so Droid CLI's per-session selector can expose the full level set. |
| `src/Sources/SettingsView.swift` | SwiftUI settings UI for server status, launch-at-login, provider toggles, auth flows, the Codex fast-mode (`service_tier=priority`) subsection, the Factory custom-models Apply button, OLED theme, background opacity, and remote-access settings. No thinking/reasoning selectors — those live in Droid CLI. |
| `src/Sources/AuthStatus.swift` | `AuthManager`, account parsing, expiry detection, file deletion, and per-account disabled-state updates. |
| `src/Sources/AppPreferences.swift` | UserDefaults-backed preferences: fast-mode toggles for GPT 5.3-codex/5.4/5.5; `allowRemote`, `secretKey`, `oledTheme`, `backgroundOpacity`, `verboseLogging`. No thinking-effort keys — reasoning is driven entirely by Droid CLI. |
| `src/Sources/OAuthUsageTracker.swift` | Reads Codex/Claude OAuth quota windows for the "OAuth Quota Usage" section in `SettingsView`. Owns its own refresh button; there is no menu-bar usage display. |
| `src/Sources/NotificationNames.swift` | Shared `Notification.Name` constants (`serverStatusChanged`, `authDirectoryChanged`). |
| `src/Sources/IconCatalog.swift` | Caches `NSImage` lookups from the bundle's resource path so menu-bar / settings icons aren't re-decoded per access. |
| `src/Sources/LogoView.swift` | Inline-SVG `LogoView` used in the settings UI. |
| `src/Sources/AuthDirectoryMonitor.swift` | Debounced `DispatchSource` watcher on `~/.cli-proxy-api` that fires an `onChange` callback when auth JSON files are added, changed, or removed. Used by both `AppDelegate` and `SettingsView`. |
| `src/Sources/AuthPaths.swift` | Single source of truth for the auth directory location (`~/.cli-proxy-api`). |
| `src/Sources/Resources/config.yaml` | Bundled CLIProxyAPI config (`port: 8318`, localhost binding, auth dir). |
| `src/Info.plist` | Bundle metadata. Current source-of-truth values include app name `DroidProxy`, bundle ID `com.droidproxy.app`, and Sparkle feed URL on `anand-92/droidproxy`. |

## Conventions

- Use `NSLog`, not `print` or `os_log`
- Source-of-truth edits land under `src/` (especially `src/Sources/**`, `src/Sources/Resources/`, `src/Info.plist`) and `create-app-bundle.sh` at the repo root; there is no longer a parallel top-level `resources/` mirror
- Treat `DroidProxy.app`, `CLIProxyMenuBar`, and `com.droidproxy.app` as the active app identity
- `CLIProxyAPI` is bundled as `src/Sources/Resources/cli-proxy-api`
- `ThinkingProxy` uses surgical string insertion for JSON edits to preserve cache-sensitive key ordering (do not switch to `JSONSerialization.data` round-trips)
- Local backend traffic is intended to stay on localhost only (`127.0.0.1:8318`)

## Release Notes For Agents

Release automation lives in `.github/workflows/release.yml` (no `Makefile` or `scripts/create-release.sh` in this repo). The app ships as a single arm64 build; there is no x86_64 appcast or Intel release path.

If a task touches release tooling, audit the current workflow and `create-app-bundle.sh`.

<!-- BEGIN fork-flow:memory — managed block; re-run the kit installer to update. Keep your own notes OUTSIDE these markers (they are overwritten on update). -->
# Fork Maintenance

This repo is a **personal fork**. Your customizations live on `custom/main` and must survive upstream changes. You never merge upstream — you integrate it **one commit at a time**, porting each upstream commit onto your fork, tracked by `.fork/UPSTREAM` (the SHA of the last upstream commit you ported). Four skills drive the work: **`fork-change`** (register a customization), **`upstream-port`** (port upstream), **`drop-change`** (retire a customization), **`propose-upstream`** (send a change to the author) — each lives at `.fork-flow/skills/<name>/SKILL.md`. Read `.fork/CHANGES.md` before changing code or porting.

## Hard rules

- **Never `git pull upstream` or `git merge upstream`.** Fetch, inspect each commit, then **port** it with `./.fork/port.sh` — it cherry-picks `-x --no-commit`, advances `.fork/UPSTREAM` in the *same* commit, and writes a `Fork-Flow-Port: <sha>` trailer (that trailer, not the staged pointer, is what the gate and `audit.sh` trust). Don't hand-roll the cherry-pick.
- **Lowest-risk integration point wins:** upstream extension point > net-new file you own > small in-place edit > `merge=ours` whole-file override (last resort — it hides upstream changes, including security fixes). This is the one choice you make *while* coding.
- **Register every customization** in `.fork/CHANGES.md`, in the *same* `custom:` commit (the `commit-msg` hook warns, never blocks, if you forget).
- **`./.fork/verify.sh` is the gate.** It builds/tests and runs every registry entry's `Verify`, proving your customizations survived; the `pre-commit` hook runs it (`--registry`) on any commit that integrates upstream **or stages `.fork/CHANGES.md`** — registering and retiring are gated too (bypass: `--no-verify`). The shipped CI workflow (`.github/workflows/fork-flow-gate.yml`) re-runs `--registry` on every push to `custom/main` — the server-side backstop that catches a bypassed or unwired local gate (enable Actions on the fork once).
- **Port small and often** (stop at release tags), and **prune** with `./.fork/audit.sh` — the cheapest customization is one you can delete (the `drop-change` skill retires one cleanly).
- **Lockfiles are never hand-merged.** On a lockfile conflict during a port: take upstream's side, re-run the install so your own dependencies re-resolve on top, stage, continue.
- **One writer.** This flow assumes a single linear `custom/main` written from one clone at a time — porting from two machines (or letting a bot commit) diverges it with no sanctioned reconcile. Serialize ports through one clone; other clones only `git pull --ff-only`.

## Adding a customization → run the `fork-change` skill

Code the change first, at the lowest-risk integration point (above). Then run `fork-change` before committing: it reads your diff, drafts the `.fork/CHANGES.md` entry, and runs the gate. Commit code and entry together in one `custom:` commit.

## Porting from upstream → run the `upstream-port` skill

Run `upstream-port` (driven by `./.fork/port.sh`). Once on a fresh fork: `./.fork/port.sh init <sha> [ref]`. Then `./.fork/port.sh next` ports the oldest unported commit; on conflict it stops — inspect with `./.fork/conflict-context.sh <sha> <file>`, re-apply your customization onto upstream's new code, `git add`, then `./.fork/port.sh continue` (or `abort`). Never silently take upstream and drop a custom behavior. Undo the newest port with `./.fork/port.sh revert` — it rewinds `.fork/UPSTREAM` and re-runs the gate, and `next` can re-port later. **Fell releases behind?** Catch up per release instead of per commit: `./.fork/port.sh range <release-tag>` squash-ports the whole span as one gated commit (one conflict set per file; files upstream deleted that you modified pause as conflicts too — `git rm` accepts the deletion, `git add` keeps yours), tag by tag, oldest first — then return to `next`. `./.fork/audit.sh` shows the unported backlog, pointer health, and what each `merge=ours` pin currently hides (`port.sh`/`audit.sh` default to the upstream ref recorded in `.fork/UPSTREAM`). Conflicted ports and ranges auto-append a skeleton entry to `.fork/PORTS.md` in the port commit — replace its `(fill in)` lines with the real decisions.

## Retiring a customization → run the `drop-change` skill

When upstream ships your change (audit's patch-id hits, your merged PR) or you no longer want one, run `drop-change`: it reverts the customization's commit(s) and deletes its `.fork/CHANGES.md` entry in the same `custom: retire <slug>` commit — the `pre-commit` gate fires on that commit automatically (a staged registry change is a gate trigger) and proves every remaining entry still passes. Retire BEFORE porting the upstream commit that ships the same change, so that port applies clean. Audit's DROP CANDIDATES list is this skill's worklist.

## Proposing a change upstream → run the `propose-upstream` skill

When a customization is worth contributing, mark its entry `Status: proposed-upstream` and run `propose-upstream`. It derives the upstream base ref from `.fork/UPSTREAM` (never assume `upstream/main` — many projects default to `develop`) and cherry-picks only that customization's commit(s) onto it — **never merge `custom/main` into a PR**, which drags every other customization into the author's history — strips fork-flow bookkeeping, verifies in isolation, and opens the PR. Keep the entry `proposed-upstream` until upstream merges it; then retire it at the next port.

## Registry — `.fork/CHANGES.md` (one entry per customization)

Each entry starts with `## custom: <slug>` (exactly two `#`, a space, a non-empty slug — `verify.sh` fails the gate on a malformed heading so a typo can't drop the next entry's `Verify`). Fields:

- **Reason** — one sentence: why it exists.
- **Touches** — tracked file paths it depends on; `;`-separated (the field also splits on `,`, so keep prose/parenthetical notes out of it), grep-friendly.
- **Verify** — a command, or `manual: <what to look at>` (`verify.sh` runs the non-`manual:` ones; unmarked prose runs and fails). Default to a micro-runnable asserting a **value/shape** (`node -e`/`ruby -e`/`python -c` against the file — still sub-second, no install), not a grep: a grep survives relocated/disabled code; use it only when the string itself *is* the customization.
- **Symbols** — `name@path`; add only when a same-signature upstream change could break you *silently* (derive with `lsp references`, or `search` if no language server). Symbols without a `Drift-if` is valid when no honest runtime tripwire exists.
- **Drift-if** — the condition that would silently break it; when present, `Verify` MUST be a runnable tripwire.
- **Status** — optional; `proposed-upstream` (PR open), `superseded` / `upstreamed` / `applied-upstream` (upstream has it) — all four make `audit.sh` list the entry as a DROP CANDIDATE for the `drop-change` skill.

## Layout

```
custom/main         your daily branch          custom/<slug>      larger change, squash-merged
upstream/<default>  read-only upstream mirror   pr/<slug>          clean PR branch off the upstream mirror

.fork/UPSTREAM             pointer: "<sha> <ref>" of the last upstream commit you ported
.fork/port.sh              the PORT driver: init (--force = sanctioned re-target) | list | next | one | range (catch-up) | revert | continue | abort | status
.fork/CHANGES.md           registry (Reason, Touches, Verify, Symbols, Drift-if, Status)
.fork/PORTS.md             per-port journal (conflicted ports/ranges auto-append a skeleton)
.fork/verify.sh            the gate — --fast | --registry | full (runs every Verify)
.fork/brief.sh             per-commit risk briefing (rename/delete/glob-aware)
.fork/conflict-context.sh  per-file conflict hunks + the upstream commit being ported
.fork/audit.sh             health: fork delta, merge=ours divergence, orphans, unregistered, drop candidates, unported backlog, pointer consistency
.fork/setup.sh             per-clone wiring (hooks + git config); run once per clone — --check reports
.fork-flow/skills/         the four skills (fork-change, upstream-port, drop-change, propose-upstream)
.fork/hooks/               commit-msg reminder + integration gate (pre-commit, pre-merge-commit); chains any pre-existing hook manager
.gitattributes             merge=ours overrides (last resort) + mergiraf syntax-aware merge (ON by default)
.github/workflows/fork-flow-gate.yml   CI gate: re-runs verify.sh --registry on every push (hooks are per-clone; CI is not)
```

Per-clone setup is one-time per clone — neither `git clone` nor copied files carry it: run `./.fork/setup.sh` (shipped with the fork; `--check` reports wiring). It sets the hooks and git config — a hook manager the project already uses (husky etc., even a dormant `.husky/` before the first install) is CHAINED, not clobbered: the gate runs first, then its hooks; managers that re-point hooks on dependency installs un-wire the kit, which `verify.sh`/`port.sh` warn about (re-run setup). Port commits run with `FORK_FLOW_PORT=1` set — guard the project's own formatter hooks on it (port.sh warns when a chained hook rewrote a port; rewritten ports stop matching upstream). Setup also configures the `mergiraf` merge driver — the `merge=mergiraf` lines in `.gitattributes` are active; when the binary is missing, setup configures Git's normal text merge as a safe fallback (install it with `cargo install mergiraf` / `brew install mergiraf`, then re-run setup to activate syntax-aware merges). First-time GitHub wiring (origin/upstream remotes + `custom/main`) is the kit installer's job: `install.sh --setup` (it applies the same setup.sh). Then set the pointer once with `./.fork/port.sh init <upstream-sha> upstream/<default-branch>` (if upstream ever force-pushes its history, the one sanctioned pointer reset is `init --force` — see the upstream-port skill; never hand-edit `.fork/UPSTREAM`).
<!-- END fork-flow:memory -->
