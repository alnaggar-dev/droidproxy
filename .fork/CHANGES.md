# Fork Customization Registry

A short map of your customizations. One entry per customization, not per commit.

Each entry is a `## custom: <slug>` heading followed by fields:

- **Reason** — why it exists (one sentence).
- **Touches** — tracked file paths this customization depends on, `;`-separated and grep-friendly (the field also splits on `,`, so keep prose out of it).
- **Symbols** — exact upstream symbols in `name@path` form. Add only when a same-signature behavior change could silently break you.
- **Drift-if** — the concrete condition that would silently break the customization.
- **Verify** — a command, or a human check written as `manual: <what to look at>`. `./.fork/verify.sh` runs the `Verify` of **every** entry: anything not marked `manual:` is run as a command (non-zero fails the gate); a `manual:` check is listed for you to confirm by hand. If the entry has a `Drift-if`, the `Verify` MUST be a runnable command (manual/missing is a hard error). Prove every new runnable `Verify` by watching it FAIL once (temporarily remove the customization, run it, restore); for a `Drift-if` also make the drift condition true once and confirm the command fails — and assert the value the `Drift-if` names (not a surface string that survives the break).
- **Status** — optional; defaults to `carry`. Set to `proposed-upstream` or `superseded` when a customization is on its way out, so `./.fork/audit.sh` reminds you to retire it.

Keep simple entries simple; add `Symbols`/`Drift-if` only when upstream behavior can silently change. See your agent memory (`CLAUDE.md` or `AGENTS.md`), Fork Maintenance section, for templates and the full workflow. The toolkit reads this file: `./.fork/brief.sh` flags entries whose `Touches`/`Symbols` paths are in an incoming upstream commit; `./.fork/verify.sh` runs the `Verify` of every entry (the integration gate runs it on every port); `./.fork/audit.sh` flags orphaned, unregistered, or retired customizations and checks the `.fork/UPSTREAM` pointer; `./.fork/port.sh` integrates upstream commit-by-commit.

---

## custom: grok-cli-provider

Reason: Adds a `grok` provider that signs in with a Grok subscription (SuperGrok / X Premium+) over the xAI OAuth 2.0 device flow (RFC 8628) and proxies the two Grok CLI models — Composer 2.5 (`grok-composer-2.5-fast`) and Grok Build (`grok-build`) — served only by `cli-chat-proxy.grok.com`, which the public `api.x.ai` API does not expose.
Touches: src/Sources/GrokAuth.swift; src/Sources/ThinkingProxy.swift; src/Sources/DroidProxyModelCatalog.swift; src/Sources/AuthStatus.swift; src/Sources/ServerManager.swift; src/Sources/SettingsView.swift; src/Sources/Resources/icon-grok.svg; src/Tests/CLIProxyMenuBarTests/GrokAuthTests.swift; src/Tests/CLIProxyMenuBarTests/ThinkingProxyGrokConvIDTests.swift; src/Tests/CLIProxyMenuBarTests/DroidProxyModelCatalogTests.swift; AGENTS.md; CHANGELOG.md; README.md
Verify: python3 -c 'import sys,pathlib; r=lambda p:(pathlib.Path(p).read_text() if pathlib.Path(p).is_file() else ""); ga=r("src/Sources/GrokAuth.swift"); cat=r("src/Sources/DroidProxyModelCatalog.swift"); tp=r("src/Sources/ThinkingProxy.swift"); seg=lambda s:next((b for b in cat.split("DroidProxyModelDefinition(") if ("idSlug: \"%s\""%s) in b),""); sys.exit(0 if ("authFileType = \"grok-cli\"" in ga and "apiHost = \"cli-chat-proxy.grok.com\"" in ga and r"custom:droidproxy:\(idSlug)" in cat and "\"id\": simpleID" in cat and all(("providerKey: \"grok\"" in seg(s) and "kind: .grok" in seg(s)) for s in ("grok-composer-2.5-fast","grok-build")) and "model.hasPrefix(\"grok-\")" in tp and "forwardToGrok(" in tp) else 1)'
Note: Provider routing has no upstream extension point, so the dispatch branch in ThinkingProxy and the provider row in SettingsView are minimal additive in-place edits mirroring the existing beta-gated Cursor provider; all OAuth device-flow, token-refresh, and credential logic lives in net-new GrokAuth.swift. No Drift-if: the upstream symbols this leans on (BETA_FLAG, RequestJSONFields.model, AuthPaths.authDirectory, the ServiceType/DroidProxyModelKind enums) break as Swift compile errors, caught by the project build `cd src && swift build && swift test` (the package lives under src/, which the generic root .fork/verify.sh does NOT compile), not silently; the runnable Verify above guards the one silent risk — a port dropping the Grok wiring while the file still compiles. Bundled cosmetic rename: SettingsView `*EffortSelectionColor` constants → `*ToggleTintColor`.

## custom: cliproxyapi-7.2.5-early

Reason: Early-adopts the upstream `cli-proxy-api` binary at v7.2.5 (upstream PR #145, commit 83a160e `chore(deps): bump CLIProxyAPI to 7.2.5`) ahead of it merging to upstream/main — cherry-picked as a custom: change so the .fork/UPSTREAM pointer stays honest at upstream/main instead of retargeting to the ephemeral PR branch.
Touches: src/Sources/Resources/cli-proxy-api
Verify: test "$(git hash-object src/Sources/Resources/cli-proxy-api)" = 1dd9204e4fae453540ed9b7205aa3fbe429f854b
Status: proposed-upstream
Note: Transient early-adoption. Binary-only swap (no Swift source changes); the grok-cli-provider customization rides on this vendored proxy but its wiring is unaffected by the bump. Verify pins the exact 7.2.5 git blob (fails on the prior 7.1.76 blob 4103d423…), cheap and execution-free — no running the 40MB binary in the gate. Retire BEFORE porting the upstream commit that ships 7.2.5: once PR #145 lands on upstream/main, use the drop-change skill to revert this commit (restoring the 7.1.76 blob) and delete this entry in one commit, THEN `./.fork/port.sh next` ports upstream's 7.2.5 commit cleanly. (If this entry is still present when that commit is ported, the cherry-pick is empty since the binary already matches — it still advances the pointer, but retire this entry immediately after.)
