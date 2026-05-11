# Graph Report - .  (2026-05-11)

## Corpus Check
- Corpus is ~30,143 words - fits in a single context window. You may not need a graph.

## Summary
- 442 nodes · 564 edges · 72 communities detected
- Extraction: 70% EXTRACTED · 30% INFERRED · 0% AMBIGUOUS · INFERRED: 170 edges (avg confidence: 0.55)
- Token cost: 12,000 input · 8,500 output

## God Nodes (most connected - your core abstractions)
1. `ThinkingProxy` - 47 edges
2. `AppDelegate` - 32 edges
3. `SettingsView` - 23 edges
4. `ServerManager` - 13 edges
5. `Key Files Reference Table` - 12 edges
6. `View` - 10 edges
7. `DroidProxy Project Overview` - 10 edges
8. `ThinkingProxy.processThinkingParameter` - 9 edges
9. `AuthManager` - 8 edges
10. `UsageWindowKind` - 8 edges

## Surprising Connections (you probably didn't know these)
- `Setup.tsx Factory custom models reference` --semantically_similar_to--> `SettingsView.droidProxyModels (Factory model list)`  [INFERRED] [semantically similar]
  website/src/components/Setup.tsx → src/Sources/SettingsView.swift
- `Provider Priority` --semantically_similar_to--> `Auth and Providers`  [INFERRED] [semantically similar]
  CHANGELOG.md → AGENTS.md
- `Multi-Account Support` --semantically_similar_to--> `Auth and Providers`  [INFERRED] [semantically similar]
  CHANGELOG.md → AGENTS.md
- `Claude Thinking Proxy (Original)` --semantically_similar_to--> `ThinkingProxy (TCP Proxy on 8317)`  [INFERRED] [semantically similar]
  CHANGELOG.md → AGENTS.md
- `Thinking Effort Configuration` --semantically_similar_to--> `Current ThinkingProxy Behavior`  [INFERRED] [semantically similar]
  SETUP.md → AGENTS.md

## Hyperedges (group relationships)
- **ThinkingProxy Per-Model Injection Flow** — agents_thinkingproxy_behavior, agents_apppreferences, setup_thinking_effort_config, agents_cliproxyapiplus_backend [EXTRACTED 0.95]
- **Usage Tracking Pipeline** — agents_usage_store, agents_claude_usage_probe, agents_codex_usage_probe, agents_usage_models, readme_usage_tracking [EXTRACTED 0.95]
- **DroidProxy Two-Hop Request Flow** — agents_thinkingproxy, agents_cliproxyapiplus_backend, agents_request_flow, setup_localhost_8317 [EXTRACTED 0.95]

## Communities

### Community 0 - "ThinkingProxy Injection Engine"
Cohesion: 0.1
Nodes (4): AmpProviderRewriteState, Config, ThinkingProxy, TopLevelFieldLocation

### Community 1 - "AGENTS Architecture Docs"
Cohesion: 0.06
Nodes (44): Amp Routing Behavior, AppDelegate.swift Role, AppPreferences.swift Role, DroidProxy Architecture, Auth and Providers, AuthManager Auth Directory Scanner, AuthStatus.swift Role, Build and Run Instructions (+36 more)

### Community 2 - "SwiftUI Settings Views"
Cohesion: 0.07
Nodes (11): LogoView, NSViewRepresentable, AccountRowView, HazardStripesView, MaxBudgetToggleView, ServiceRow, SettingsView, Timing (+3 more)

### Community 3 - "Effort/Thinking Preference Keys"
Cohesion: 0.06
Nodes (37): AppPreferences.claudeMaxBudgetModeKey, AppPreferences.gemini31ProThinkingLevelKey, AppPreferences.gemini3FlashThinkingLevelKey, AppPreferences.gpt53CodexReasoningEffortKey, AppPreferences.gpt54ReasoningEffortKey, AppPreferences.opus47ThinkingEffortKey, AppPreferences.sonnet46ThinkingEffortKey, Adaptive thinking (thinking.type=adaptive) (+29 more)

### Community 4 - "AppDelegate Lifecycle"
Cohesion: 0.08
Nodes (6): AppDelegate, Notification.Name, NSApplicationDelegate, NSObject, NSWindowDelegate, UNUserNotificationCenterDelegate

### Community 5 - "Website React Components"
Cohesion: 0.07
Nodes (0): 

### Community 6 - "Auth Directory Scanner"
Cohesion: 0.12
Nodes (12): AuthAccount, AuthManager, ServiceAccounts, ServiceType, claude, codex, gemini, CaseIterable (+4 more)

### Community 7 - "Changelog History"
Cohesion: 0.09
Nodes (24): DroidProxy Changelog, Gemini Factory Custom Models, Gemini Provider Support, Gemini Thinking Level Controls, Opus 4.6 Factory Custom Model Removal, Claude Opus 4.7 Migration, Semantic Versioning, Build from Source Instructions (+16 more)

### Community 8 - "Factory Model Catalog"
Cohesion: 0.12
Nodes (14): DroidProxyModelCatalog, DroidProxyModelDefinition, DroidProxyModelKind, claudeAdaptive, claudeClassic, codex, gemini, DroidProxyModelVariant (+6 more)

### Community 9 - "Server Process Manager"
Cohesion: 0.2
Nodes (4): OutputCapture, RingBuffer, ServerManager, Timing

### Community 10 - "Claude Usage Probe"
Cohesion: 0.16
Nodes (11): ClaudeUsageProbe, TokenInfo, Codable, ProviderUsageSnapshot, UsageWindow, UsageWindowKind, daily, hourly (+3 more)

### Community 11 - "Challenger Droids Setup"
Cohesion: 0.22
Nodes (11): Challenger droids (Opus 4.7 / GPT 5.4 / Gemini 3.1 Pro), challenger-opus droid (custom:droidproxy:opus-4-7), custom:droidproxy:opus-4-6 (legacy scrubbed), custom:droidproxy:opus-4-7 Factory model, Rationale: scrub legacy opus-4-6 entry so users don't end up with stale entries next to Opus 4.7, SettingsView.applyChallengerPlugin, SettingsView.applyFactoryCustomModels, SettingsView.challengerPluginFiles (+3 more)

### Community 12 - "App Boot + Proxy Wiring"
Cohesion: 0.33
Nodes (6): AppDelegate, AppDelegate.pollForProxyReadiness, AppDelegate.startServer, CLIProxyAPIPlus backend (port 8318), localhost:8317 proxy endpoint, ThinkingProxy (class)

### Community 13 - "Codex Usage Probe"
Cohesion: 0.47
Nodes (1): CodexUsageProbe

### Community 14 - "Cloudflared Tunnel Manager"
Cohesion: 0.5
Nodes (1): TunnelManager

### Community 15 - "Icon Cache"
Cohesion: 0.5
Nodes (1): IconCatalog

### Community 16 - "Notification Names"
Cohesion: 1.0
Nodes (1): Notification.Name

### Community 17 - "AppPreferences Module"
Cohesion: 1.0
Nodes (1): AppPreferences

### Community 18 - "Amp Routing"
Cohesion: 1.0
Nodes (2): Amp CLI routing rewrites, ThinkingProxy.forwardToAmp

### Community 19 - "Opus 4.7 Thinking Default"
Cohesion: 1.0
Nodes (2): AppPreferences.defaultOpus47ThinkingEffort (xhigh), Rationale: xhigh default per Anthropic's recommendation for coding/agentic workloads

### Community 20 - "Community 20"
Cohesion: 1.0
Nodes (2): Codex auth_unavailable Blackout Fix, Disable Cooling Rationale

### Community 21 - "Community 21"
Cohesion: 1.0
Nodes (2): Encrypted Reasoning State Mismatch Fix, Session Affinity Rationale

### Community 22 - "Community 22"
Cohesion: 1.0
Nodes (2): Amp CLI OAuth Integration Fix, Amp Request Routing Improvements

### Community 23 - "Community 23"
Cohesion: 1.0
Nodes (0): 

### Community 24 - "Community 24"
Cohesion: 1.0
Nodes (0): 

### Community 25 - "Community 25"
Cohesion: 1.0
Nodes (0): 

### Community 26 - "Community 26"
Cohesion: 1.0
Nodes (0): 

### Community 27 - "Community 27"
Cohesion: 1.0
Nodes (0): 

### Community 28 - "Community 28"
Cohesion: 1.0
Nodes (0): 

### Community 29 - "Community 29"
Cohesion: 1.0
Nodes (0): 

### Community 30 - "Community 30"
Cohesion: 1.0
Nodes (0): 

### Community 31 - "Community 31"
Cohesion: 1.0
Nodes (0): 

### Community 32 - "Community 32"
Cohesion: 1.0
Nodes (0): 

### Community 33 - "Community 33"
Cohesion: 1.0
Nodes (0): 

### Community 34 - "Community 34"
Cohesion: 1.0
Nodes (0): 

### Community 35 - "Community 35"
Cohesion: 1.0
Nodes (0): 

### Community 36 - "Community 36"
Cohesion: 1.0
Nodes (0): 

### Community 37 - "Community 37"
Cohesion: 1.0
Nodes (0): 

### Community 38 - "Community 38"
Cohesion: 1.0
Nodes (0): 

### Community 39 - "Community 39"
Cohesion: 1.0
Nodes (0): 

### Community 40 - "Community 40"
Cohesion: 1.0
Nodes (0): 

### Community 41 - "Community 41"
Cohesion: 1.0
Nodes (0): 

### Community 42 - "Community 42"
Cohesion: 1.0
Nodes (0): 

### Community 43 - "Community 43"
Cohesion: 1.0
Nodes (0): 

### Community 44 - "Community 44"
Cohesion: 1.0
Nodes (0): 

### Community 45 - "Community 45"
Cohesion: 1.0
Nodes (0): 

### Community 46 - "Community 46"
Cohesion: 1.0
Nodes (0): 

### Community 47 - "Community 47"
Cohesion: 1.0
Nodes (0): 

### Community 48 - "Community 48"
Cohesion: 1.0
Nodes (0): 

### Community 49 - "Community 49"
Cohesion: 1.0
Nodes (0): 

### Community 50 - "Community 50"
Cohesion: 1.0
Nodes (0): 

### Community 51 - "Community 51"
Cohesion: 1.0
Nodes (0): 

### Community 52 - "Community 52"
Cohesion: 1.0
Nodes (0): 

### Community 53 - "Community 53"
Cohesion: 1.0
Nodes (0): 

### Community 54 - "Community 54"
Cohesion: 1.0
Nodes (0): 

### Community 55 - "Community 55"
Cohesion: 1.0
Nodes (1): Codex Provider Support

### Community 56 - "Community 56"
Cohesion: 1.0
Nodes (1): CLIProxyAPI Upstream Releases

### Community 57 - "Community 57"
Cohesion: 1.0
Nodes (1): Intel Mac (x86_64) Support

### Community 58 - "Community 58"
Cohesion: 1.0
Nodes (1): Amp CLI Login Flow Fix

### Community 59 - "Community 59"
Cohesion: 1.0
Nodes (1): Z.AI GLM Provider Support

### Community 60 - "Community 60"
Cohesion: 1.0
Nodes (1): Claude Models via Antigravity

### Community 61 - "Community 61"
Cohesion: 1.0
Nodes (1): Interleaved Thinking Support

### Community 62 - "Community 62"
Cohesion: 1.0
Nodes (1): GitHub Copilot Support

### Community 63 - "Community 63"
Cohesion: 1.0
Nodes (1): GPT-5.1 Codex Max Support

### Community 64 - "Community 64"
Cohesion: 1.0
Nodes (1): Claude Opus 4.5 Support

### Community 65 - "Community 65"
Cohesion: 1.0
Nodes (1): Antigravity OAuth Support

### Community 66 - "Community 66"
Cohesion: 1.0
Nodes (1): Gemini 3 Pro Models via Antigravity

### Community 67 - "Community 67"
Cohesion: 1.0
Nodes (1): Qwen Models Documentation

### Community 68 - "Community 68"
Cohesion: 1.0
Nodes (1): Gemini Support (1.0.4)

### Community 69 - "Community 69"
Cohesion: 1.0
Nodes (1): Icon Caching System

### Community 70 - "Community 70"
Cohesion: 1.0
Nodes (1): Qwen Support (1.0.6)

### Community 71 - "Community 71"
Cohesion: 1.0
Nodes (1): VibeProxy 1.0.0 Initial Release

## Knowledge Gaps
- **96 isolated node(s):** `Timing`, `Notification.Name`, `AppPreferences`, `Config`, `Timing` (+91 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Notification Names`** (2 nodes): `NotificationNames.swift`, `Notification.Name`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `AppPreferences Module`** (2 nodes): `AppPreferences.swift`, `AppPreferences`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Amp Routing`** (2 nodes): `Amp CLI routing rewrites`, `ThinkingProxy.forwardToAmp`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Opus 4.7 Thinking Default`** (2 nodes): `AppPreferences.defaultOpus47ThinkingEffort (xhigh)`, `Rationale: xhigh default per Anthropic's recommendation for coding/agentic workloads`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 20`** (2 nodes): `Codex auth_unavailable Blackout Fix`, `Disable Cooling Rationale`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 21`** (2 nodes): `Encrypted Reasoning State Mismatch Fix`, `Session Affinity Rationale`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 22`** (2 nodes): `Amp CLI OAuth Integration Fix`, `Amp Request Routing Improvements`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 23`** (1 nodes): `SPUInstallationType.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 24`** (1 nodes): `SUInstallerLauncher+Private.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 25`** (1 nodes): `SPUUserAgent+Private.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 26`** (1 nodes): `SPUStandardUserDriver+Private.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 27`** (1 nodes): `SUAppcastItem+Private.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 28`** (1 nodes): `SPUAppcastItemStateResolver.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 29`** (1 nodes): `SPUGentleUserDriverReminders.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 30`** (1 nodes): `SPUDownloadData.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 31`** (1 nodes): `SPUUpdaterDelegate.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 32`** (1 nodes): `SUVersionDisplayProtocol.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 33`** (1 nodes): `SUAppcast.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 34`** (1 nodes): `SPUUpdaterSettings.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 35`** (1 nodes): `SUExport.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 36`** (1 nodes): `SPUStandardUserDriver.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 37`** (1 nodes): `SPUUserUpdateState.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 38`** (1 nodes): `SUUpdaterDelegate.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 39`** (1 nodes): `SPUUserDriver.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 40`** (1 nodes): `SUErrors.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 41`** (1 nodes): `SUAppcastItem.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 42`** (1 nodes): `SPUStandardUserDriverDelegate.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 43`** (1 nodes): `SUStandardVersionComparator.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 44`** (1 nodes): `SPUUpdateCheck.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 45`** (1 nodes): `SPUUpdater.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 46`** (1 nodes): `SUUpdater.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 47`** (1 nodes): `SPUStandardUpdaterController.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 48`** (1 nodes): `SPUUpdatePermissionRequest.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 49`** (1 nodes): `SUVersionComparisonProtocol.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 50`** (1 nodes): `SUUpdatePermissionResponse.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 51`** (1 nodes): `tailwind.config.js`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 52`** (1 nodes): `vite.config.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 53`** (1 nodes): `postcss.config.js`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 54`** (1 nodes): `Package.swift`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 55`** (1 nodes): `Codex Provider Support`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 56`** (1 nodes): `CLIProxyAPI Upstream Releases`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 57`** (1 nodes): `Intel Mac (x86_64) Support`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 58`** (1 nodes): `Amp CLI Login Flow Fix`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 59`** (1 nodes): `Z.AI GLM Provider Support`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 60`** (1 nodes): `Claude Models via Antigravity`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 61`** (1 nodes): `Interleaved Thinking Support`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 62`** (1 nodes): `GitHub Copilot Support`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 63`** (1 nodes): `GPT-5.1 Codex Max Support`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 64`** (1 nodes): `Claude Opus 4.5 Support`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 65`** (1 nodes): `Antigravity OAuth Support`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 66`** (1 nodes): `Gemini 3 Pro Models via Antigravity`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 67`** (1 nodes): `Qwen Models Documentation`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 68`** (1 nodes): `Gemini Support (1.0.4)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 69`** (1 nodes): `Icon Caching System`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 70`** (1 nodes): `Qwen Support (1.0.6)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 71`** (1 nodes): `VibeProxy 1.0.0 Initial Release`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `UsageWindowKind` connect `Claude Usage Probe` to `Auth Directory Scanner`?**
  _High betweenness centrality (0.013) - this node is a cross-community bridge._
- **Why does `ServerManager` connect `Server Process Manager` to `Auth Directory Scanner`?**
  _High betweenness centrality (0.011) - this node is a cross-community bridge._
- **What connects `Timing`, `Notification.Name`, `AppPreferences` to the rest of the system?**
  _96 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `ThinkingProxy Injection Engine` be split into smaller, more focused modules?**
  _Cohesion score 0.1 - nodes in this community are weakly interconnected._
- **Should `AGENTS Architecture Docs` be split into smaller, more focused modules?**
  _Cohesion score 0.06 - nodes in this community are weakly interconnected._
- **Should `SwiftUI Settings Views` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._
- **Should `Effort/Thinking Preference Keys` be split into smaller, more focused modules?**
  _Cohesion score 0.06 - nodes in this community are weakly interconnected._