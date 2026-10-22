# Raycast integration research (VISION item 6)

Status: research spike, 2026-10-21. No app code was written for this.

This is about using **Raycast and the extensions the user already has installed** from the notch. It is not an extension store, not a JS runtime of our own, and not upstream Boring Notch's planned ExtensionKit/XPC extension platform.

**How to read the evidence.** "Verified" means read in an official doc, in a source file, or on disk on this Mac (Raycast 2.8.0, `/Applications/Raycast.app`, inspected read-only). "Inferred" means it is our reasoning. "Unconfirmed" means we looked and could not settle it. Most doc citations point at https://developers.raycast.com. The full text is at https://developers.raycast.com/llms-full.txt, and line numbers below refer to that file as fetched on 2026-10-21.

## TL;DR

- **Inbound (us → Raycast) is easy but one-way.** The deeplink `raycast://extensions/<owner>/<ext>/<command>?launchType=background&arguments=…&context=…&fallbackText=…` can launch any installed command. Raycast asks the user to confirm once per command. After "Always Open Command" it launches silently, and that choice survives a Raycast restart (tested by the user on 2026-10-21). There is **no result or callback channel**.
- **Outbound (Raycast → us) only happens if Raycast-side code chooses to call us.** Extensions are unsandboxed Node, so they can reach a unix socket, localhost HTTP, a URL scheme or a CLI. The user's existing third-party extensions know nothing about us, so **we cannot capture their output** (lists, toasts, HUDs, menu-bar items). Content has to come from code we control: a small companion Raycast extension, or Script Commands calling a CLI we ship.
- **Discovery is possible but undocumented.** Every installed store extension's full `package.json` sits unencrypted in `~/.config/raycast/extensions/<uuid>/`, with commands, titles, modes, arguments, AI tools and icons. Enabled state, aliases, hotkeys and settings live in Raycast's encrypted databases, which we should not touch.
- **Recommendation:**
  - The app owns a small, versioned local API: a unix socket plus a `notchctl` CLI, with a URL scheme for fire-and-forget calls.
  - We ship one companion Raycast extension, "Not Boring Notch", that turns Raycast-side events into notch alerts, live activities and panels.
  - A "Raycast launcher" panel reads installed manifests and fires deeplinks.
  - Details are in [Recommendation](#recommendation).

## Q1. Triggering Raycast from outside

**Deeplinks (verified).** Source: https://developers.raycast.com/information/lifecycle/deeplinks (llms-full.txt about lines 2795–2830).

- The format is `raycast://extensions/<author-or-owner>/<extension-name>/<command-name>`.
  - For store extensions the three parts are the manifest's `owner` (or `author`), `name`, and the command's `name`.
  - For built-ins the owner is `raycast` and the other two parts are slugified names, for example `raycast://extensions/raycast/calendar/my-schedule`.
  - Every root item has a "Copy Deeplink" action.
- Query parameters:

  | Param | Meaning |
  |---|---|
  | `launchType` | `userInitiated` or `background`. Quoted: "Runs the command in the background, skipping bringing Raycast to the front." |
  | `arguments` | URL-encoded JSON object matching the command's declared `arguments`. |
  | `context` | URL-encoded JSON object, delivered as `LaunchProps.launchContext`. |
  | `fallbackText` | Prefills the search bar or the first text input. |

- **The confirmation prompt is verified.** Quoted: "Whenever a command is launched using a Deeplink, Raycast will ask you to confirm that you want to run the command." The Raycast 2.8 binary has a `FrontendGeneralConfirmExternalCommandLaunchInput` message, which is consistent with this.
  - Secondary sources say the prompt offers "Always Open Command", which suppresses it afterwards per command. Those sources are the manual's deeplinks page, which we could only read through a search summary because it renders client-side, and a 2023 MacStories article (https://www.macstories.net/stories/raycast-adds-deeplinking-of-commands/).
  - **Tested by the user on Raycast 2.8.0, 2026-10-21** (see [Test results](#test-results-2026-10-21)):
    - The prompt appears the first time *each command* is launched by deeplink, even with `launchType=background`. Background mode does not bypass it.
    - "Always Open Command" exists. Once chosen, later launches run with no prompt and no Raycast window, whether `launchType` is `background` or `userInitiated`, so approval is per command, not per launch type.
    - The approval persisted after quitting and relaunching Raycast. Persistence across Raycast *updates* is untested.
    - `arguments` prefill works for a `view` command.
- **The URL shape for script commands is verified.** It is `raycast://script-commands/<slug>?arguments=a&arguments=b`, with repeated positional `arguments` params. This is the code `@raycast/utils` `createDeeplink` emits (`DeeplinkType.ScriptCommand`; https://developers.raycast.com/utilities/functions/createdeeplink).
- **Search-summary only, unconfirmed:** `raycast://ai-commands/<slug>` and `raycast://confetti`.
- **The registered schemes are verified** from `Raycast.app/Contents/Info.plist`: `raycast`, `raycast-x`, `com.raycast`, `com.raycast-x`.

**What can run without the Raycast window.**
- Commands have three modes: `view`, `no-view` and `menu-bar` (https://developers.raycast.com/information/manifest).
- A `no-view` command launched with `launchType=background` is the only way to run "headless". Tested: an approved `no-view` command ran with no Raycast window, under both launch types.
- `view` commands always need the Raycast window. That is fine when the user explicitly picks them from the notch: Raycast opens normally.
- A `menu-bar` command launched in the background just refreshes its menu bar item.

**Results (verified absent).** A deeplink returns nothing.
- There is no x-callback-url and no reply URL.
- The extension-side equivalent `launchCommand()` "does not indicate that the launched command has finished executing" (https://developers.raycast.com/api-reference/command).
- Any result must be pushed back by Raycast-side code (Q2).

**Other channels.**

| Channel | Finding |
|---|---|
| AppleScript | Verified absent. There is no `.sdef`, no `NSAppleScriptEnabled` and no `OSAScriptingDefinition` in the 2.8.0 bundle. |
| Shortcuts | We found no macOS Shortcuts actions for Raycast (unconfirmed absence). Shortcuts can only "Open URL" a deeplink. |
| CLI | `ray` (from `@raycast/api`) is a development CLI: `ray develop`, `ray build`, `ray lint`, `ray publish`. It has no runtime "run command". |
| Local API/server | None is documented and we found none. |
| Services | Raycast registers one macOS Service, "Send to Raycast AI" (`NSServices` in `Info.plist`, verified). |
| MCP | Raycast is an MCP *client* (https://manual.raycast.com/model-context-protocol). We could expose an MCP server that Raycast AI calls, but that is a separate, AI-only path. |
| Hotkeys and aliases | These are configured by the user inside Raycast and stored encrypted. They are no use to us. |

**Script Commands (verified).** Sources: https://github.com/raycast/script-commands (README, `documentation/ARGUMENTS.md`, `documentation/OUTPUTMODES.md`) and https://manual.raycast.com/script-commands.

- Scripts are shell, Python or other files with `# @raycast.*` metadata, in a folder the user registers in Raycast settings.
- Output modes:

  | Mode | Behavior |
  |---|---|
  | `fullOutput` | Terminal-like view. |
  | `compact` | Last line shown in a toast. |
  | `silent` | Last line shown in a HUD after the window closes. |
  | `inline` | First line shown in the root item, refreshed every `refreshTime`. The minimum is 10s, and only the first 10 inline commands auto-refresh. |

- There are up to 3 arguments (`text`, `password`, `dropdown`), which arrive as `$1`–`$3`.
- Scripts run unsandboxed, as the user. This is the lowest-effort way for a user to wire Raycast to our app: a `silent` script that runs `notchctl alert "…"`.

## Q2. Getting data back out of Raycast

**Extensions are not sandboxed (verified).** Quoted from https://developers.raycast.com/information/security (llms-full.txt line 3367): "Extensions are **not further sandboxed** as far as policies for file I/O, networking, or other features of the Node runtime are concerned."
- Each extension runs in a worker isolate inside Raycast's shared Node process. Raycast 2.8 ships Node 22: `~/Library/Application Support/com.raycast.macos/node/runtime/node-v22.23.3-darwin-arm64`.
- So an extension can use `net` (unix sockets), `fetch` to `127.0.0.1`, `child_process` and `fs`.
- `open(target)` opens files, folders and URLs (https://developers.raycast.com/api-reference/utilities). We infer it works for custom schemes because it wraps the system open; the Parachord example below relies on its own scheme.
- `runAppleScript` lives in `@raycast/utils`.

**`callbackLaunchOptions` is not a Raycast API (verified).**
- It does not appear in `@raycast/api` 2.8.2's type definitions.
- It is the community convention from `raycast-cross-extension` (https://github.com/LitoMore/raycast-cross-extension-conventions). A consumer passes `callbackLaunchOptions` in `launchContext`, and the provider calls `callbackLaunchCommand(options, result)`, which is just `launchCommand` back into the caller's command with `{ result }` as context.
- It only works **between Raycast extensions**. It cannot target a non-Raycast app.
- Cross-extension `launchCommand` shows a permission alert ("If the command is part of another extension, the user will be presented with a permission alert", llms-full.txt line 4044).

**Sanctioned extension ↔ companion-app pattern.** The store guidelines (https://developers.raycast.com/basics/prepare-an-extension-for-store) explicitly contemplate extensions "tightly coupled to an app" that users have installed. Store extensions already talk to local apps (all source verified from `raycast/extensions` `main`):

| Extension | Transport | Notes |
|---|---|---|
| `dondori` | Unix socket | `src/client.ts`: `SOCKET_PATH = ~/Library/Application Support/Dondori/raycast.sock`, newline-delimited JSON, 1.5s timeout, "app not running" error. **Closest model to what we want.** |
| `parachord` | Localhost HTTP + URL scheme | Builds `parachord://…` URLs and POSTs them to `http://127.0.0.1:8888/protocol`. Shows a toast on `ECONNREFUSED`. |
| `masscode` | Localhost HTTP + bearer token | Port and token are preferences. A source comment warns to use `127.0.0.1`, because `localhost` may resolve to `::1`. |
| `anki`, `search-joplin-notes` | Localhost HTTP JSON APIs | The port is a preference. |
| `hammerspoon`, Spotify tutorial | AppleScript | Needs the target app to be scriptable. |

**Other Raycast surfaces we cannot read from outside.**
- **Toasts, HUDs, list items and menu-bar items** that a *third-party* extension renders go to Raycast's own UI. No API mirrors them to other apps, and the only way to get them would be Accessibility scraping of Raycast's windows, which we reject.
- **Extensions' `LocalStorage` and `Cache`** are per extension and stored encrypted (https://developers.raycast.com/api-reference/storage).
- **Background refresh (`interval`)** applies to `no-view` and `menu-bar` commands. The minimum is 10s per the changelog at llms-full.txt line 16540; older manifest docs say 1m. Store-installed interval commands are inactive until the user activates them (https://developers.raycast.com/information/lifecycle/background-refresh). This is how our companion extension can poll something periodically, though our app should push rather than poll.
- **AI tools (`tools` in the manifest).** These are functions that only Raycast AI invokes. There is no external invocation API (unconfirmed absence). One community project, raybridge (https://github.com/jlokos/raybridge), exposes them over MCP but reportedly decrypts Raycast data with sqlcipher. We reject that approach (see Q6 and Terms).

**Conclusion for Q2.** The supported return channel is our own code running inside Raycast, either the companion extension or Script Commands, calling a local endpoint we own. Unmodified third-party extensions cannot send us data.

## Q3. Discovering what the user has installed

All of this was verified on this Mac, Raycast 2.8.0, read-only.

| Path | What's there | Readable? |
|---|---|---|
| `~/.config/raycast/extensions/<uuid>/` | One directory per installed store extension, named by store UUID. Contains the **full `package.json` manifest**, compiled `*.js` per command, `tools/*.js`, `assets/` (icons), and in 2.8 a `plugin.json` that points to the `agent-plugins.org` schema. | Plain JSON and PNG, world-readable (`drwxr-xr-x`). |
| `~/.config/raycast/extensions/node_modules/` | Shared runtime: `@raycast/api` (bundled `index.js` only, no `.d.ts`), React. | Yes. |
| `~/.config/raycast/node-compile-cache/` | Node compile cache. | Not useful. |
| `~/Library/Application Support/com.raycast.macos/` | `main.db`, `settings_v2.db`, `node_extensions.db`, `frecency.db`, `clipboard.db`, `ai.db` and others, plus `extensions/<uuid>/com.raycast.api.cache`. | **Encrypted.** The headers are not `SQLite format 3`. A third-party write-up (https://simo.sh/notes/migrating-raycast-clipboard-history) and Raycast's security page say the key is in the Keychain. |
| `~/Library/Preferences/com.raycast.macos.plist` | 21 keys, mostly window state. No settings of interest. | Yes, but useless. |

**What each manifest gives us.** These fields come from real manifests on disk:
- Extension: `name`, `title`, `author`, optionally `owner`, `icon` (relative to `assets/`), `description` and `platforms` (`["macOS","Windows"]`).
- Per command: `name`, `title`, `description`, `mode` (`view` / `no-view` / `menu-bar`), `interval`, and `arguments[]` (`name`, `type` `text|password|dropdown`, `placeholder`, `required`, `data`).
- AI tools: `tools[]`, each with `name`, `title`, `description` and a JSON-schema `input`.

That is everything needed to build a deeplink and an argument form. Example: `raycast://extensions/thomas/color-picker/pick-color?launchType=background`.

**What we cannot get from disk:**
- Whether an extension or command is **enabled**.
- User **aliases**, **hotkeys** and **preferences**.
- **Built-in** Raycast commands, which have no manifests. The deeplink docs only document a few built-in slugs.
- **Script Commands**, since the folders are registered in encrypted settings.
- **Development extensions** (`ray develop`). On this machine there are none, so their location is unverified.

**Stability.** The on-disk layout is **undocumented**, so treat it as best-effort.
- The `package.json` format itself is the documented, public manifest (https://developers.raycast.com/information/manifest), so parsing it is low-risk.
- The *location* and UUID naming could change. It survived the move to Raycast 2.x on this machine.

**Sandboxing (our side).** `boringNotch.entitlements` has `com.apple.security.app-sandbox` = true, so the app **cannot read `~/.config/raycast` today**. Options:
1. Add `com.apple.security.temporary-exception.files.home-relative-path.read-only` = `/.config/raycast/extensions/`. This is fine because we don't ship through the Mac App Store.
2. Have the user grant the folder once with an `NSOpenPanel` and a security-scoped bookmark. The app already has the bookmark entitlements.
3. Let the companion Raycast extension send the list instead. It can read the same directory, since it isn't sandboxed.

**Privacy.**
- We would only read manifests. We would never touch the encrypted databases, clipboard history, AI chats or the Keychain.
- The installed-extension list itself is mildly personal, so keep it on-device.

## Q4. Raycast-side companion extension ("shim")

**Feasible, verified by precedent.** Dondori, Parachord and masscode are store extensions that exist mainly to talk to a local companion app. The guidelines contemplate this (https://developers.raycast.com/basics/prepare-an-extension-for-store):
- Allowed: "calling known system binaries", and binaries with source and hash checks.
- Rejected: **opaque binaries**, **Keychain access**, and external analytics.
- Required: a README with setup steps when setup is needed.
- Discouraged: "Avoid asking users to perform additional downloads", but app-coupled extensions are acknowledged.
- Possible rejection reasons: duplicating native features, or a "very similar extension" already existing.

**What it could do:**
- **`no-view` commands with arguments** for the user to call directly, from Raycast, hotkeys, aliases or deeplinks:
  - "Notch: Show Alert" (title, subtitle, symbol).
  - "Notch: Start Timer/Progress".
  - "Notch: Open Panel".
  - Each sends one JSON message to our socket and calls `showHUD` only on failure.
- **A cross-extension provider** following `raycast-cross-extension` conventions. Other extensions that *opt in* (their authors add a call) can `launchCommand({ ownerOrAuthorName, extensionName: "not-boring-notch", name: "show", context: {...} })`. This only helps future cooperating extensions, not the user's existing ones, and the first use shows Raycast's permission alert.
- **A `menu-bar` or `interval` `no-view` command** that runs inside Raycast periodically, for example to sync the installed-extension list to the app. That avoids the sandbox entitlement in Q3, option 3.
- **"Run X and send its result to the notch".** This works only for things *our* extension computes itself or reads through public APIs. It cannot read another extension's output.

**What it can't do:**
- Run headless without Raycast installed and running.
- Read other extensions' data, preferences or rendered UI.
- Receive pushes from our app. Raycast has no inbound API, so the app can only *launch* the extension's commands via deeplink, with `context` as the payload. The confirmation prompt applies.
- Ship a native binary without source. Any `notchctl` must come from the app bundle, not the extension.
- `rust:` and `swift:` native imports are limited. Per a Simple Notch build-script comment, "Raycast itself rejects Rust calls on macOS". That claim is unconfirmed, and we don't need native code anyway.

**Rate limits:** none documented for local calls. The only throttling is the background-refresh floor (10s, or 1m in older docs), which macOS may also defer for energy reasons. Our app must rate-limit and coalesce inbound alerts itself.

**Distribution.** Publishing to the store needs review (extension names are unique, and the `author` is a Raycast account). Installing from source (`npm install && npm run dev`, then keeping it) works for the prototype and for power users. An extension kept via `ray develop` keeps working after the dev session stops, but it is marked as a development extension.

## Q5. Display side: what fits in the notch

| Raycast-side source | Notch concept (VISION) | Notes |
|---|---|---|
| `showHUD` / `silent` script output (one line) | **Temporary alert** (item 4 mechanism) | Most natural mapping. Our companion command or script sends `{type:"alert", title, subtitle?, sfSymbol?, duration?}`. Raycast's own HUD will still appear if the command calls `showHUD`, so our commands shouldn't. |
| `showToast` with `Toast.Style.Animated` and later Success/Failure | **Live activity with progress** | Sequence: `start` → `update(progress, text)` → `finish(success/failure)`, keyed by an `id`. The extension must send the updates itself. |
| `inline` script / `menu-bar` command title (periodic value) | **Persistent compact chip** (a live activity with no end) | For example the "next meeting" or "build status" text in the closed notch. The source must push on change and the app keeps the last value. No polling in the app. |
| List or Detail results (`view` commands) | **Expandable panel** (item 2), "Raycast panel" | Only for content *our* extension produces. Payload: `{type:"panel", title, items:[{title, subtitle, icon?, accessory?, action?}]}`, where an action is a URL, often a Raycast deeplink, opened on click. Cap the size. |
| Installed commands (from manifests, Q3) | **Expandable "Raycast launcher" panel** | The user pins commands. Clicking fires a deeplink. Commands with `arguments` get a small inline form built from the manifest. `view` commands open Raycast. |
| Menu-bar items of other extensions | Not feasible | They are rendered by Raycast with no export. |

The lock screen (item 3) should default all Raycast-originated content to hidden or redacted. Arbitrary text can be pushed in, so we can't know what's private.

## Q6. Prior art

| Project | What it does | Takeaway |
|---|---|---|
| **Simple Notch launcher** with [HanlunWang/simple-notch-extensions](https://github.com/HanlunWang/simple-notch-extensions) | Mirrors `raycast/extensions` daily, builds each extension with esbuild against **its own `@raycast/api` shim**, and runs them in its own runtime. Raycast itself is not involved (README verified). `rust:`/`swift:` imports are stubbed to reject. | The only Raycast-in-a-notch project we found, and it is exactly what VISION rules out: a runtime of our own that re-implements Raycast's API, with license, terms and API-churn exposure. It shows the "use the user's real Raycast" path hasn't been done. |
| **AtollExtensionKit** ([Ebullioscopic/AtollExtensionKit](https://github.com/Ebullioscopic/AtollExtensionKit)) | Swift SDK over XPC for third-party apps to present, update and dismiss live activities in the Atoll notch app, with an authorization prompt and priorities (README verified). | A good model for **our app's message vocabulary** (present/update/dismiss, ids, priorities, user authorization). XPC isn't reachable from Raycast's Node, so we need a socket and a CLI instead. |
| **Dondori** (raycast/extensions) | Store extension ↔ companion app over a unix socket in Application Support. | The transport to copy. |
| **zNotch**, **Say No to Notch** (Raycast store) | Raycast extensions that control a notch-*hiding* app, which must be running. | Store accepts app-coupled extensions. |
| **MewNotch** | A "bash script view" that runs commands and shows output in the expanded notch (pull model). | An alternative to a push API, but it means polling, which conflicts with "cheap at rest". |
| **Hammerspoon extension** | Raycast → app via AppleScript after the user opts in (`hs.allowAppleScript(true)`). | Opt-in on the target app side is normal. |
| **Alfred External Triggers** | `alfred://runtrigger/<bundle>/<trigger>/?argument=…` and AppleScript `run trigger` (https://www.alfredapp.com/help/workflows/triggers/external). A forum report says triggers steal focus. | Same shape as Raycast deeplinks: one-way, with no result. |
| **raybridge** ([jlokos/raybridge](https://github.com/jlokos/raybridge)) | Exposes Raycast extensions' AI tools over MCP. It reportedly needs sqlcipher to read Raycast's encrypted data. | Shows the fragile, ToS-adjacent route. We did not inspect its code. |
| **Boring Notch upstream** | No Raycast integration. The extension platform is unshipped: issue #670 plans ExtensionKit/XPC, and PR #1401 refactors the closed notch into regions and is "not an ExtensionKit API yet". Issues #951 and #1470 ask for external tools to push status into the notch. | It confirms demand for a push API. Our local API serves that too, not just Raycast. |

No notch app we found exposes an API that Raycast extensions call. A search of `raycast/extensions` for "dynamic island", "alcove" and "notchnook" returned nothing. GitHub code search was partly rate-limited, so absence is likely but not proven.

**Terms.** The Raycast Terms of Service (https://www.raycast.com/terms-of-service, §VI) prohibit reverse engineering, and scraping or "similar data gathering".
- Documented deeplinks, and parsing the public manifest format, are fine.
- Decrypting Raycast's databases or scraping its UI is not. We exclude both.
- We found no separate developer terms that would block a companion extension.

## Candidate architectures

### A. Read manifests and launch by deeplink (outbound only)

The app reads `~/.config/raycast/extensions/*/package.json` (with a sandbox exception or a user-granted bookmark). It shows a pinned-commands panel and fires `raycast://extensions/...` with `launchType=background` for `no-view` commands and `userInitiated` for `view` commands, building argument forms from the manifest.

- Pros:
  - Zero Raycast-side setup.
  - Works with every installed store extension immediately.
  - Uses only the documented URL scheme and the public manifest format.
- Cons:
  - **No results ever come back.** The notch is a launcher, not a display.
  - A confirmation prompt on first launch of each command.
  - No enabled-state, alias or built-in command info.
  - The undocumented directory layout.
  - Sandbox entitlement work.

### B. Local API in the app, plus a companion Raycast extension (inbound)

The app listens on a unix socket in its container. A sandboxed app's Application Support resolves to `~/Library/Containers/<bundle-id>/Data/Library/Application Support/…`, which unsandboxed Raycast can connect to. The socket speaks newline-delimited JSON: `alert`, `activity.start/update/end`, `panel.show/update/close` and `ping`, each with an `id`, a TTL and a source tag.
- We ship a `notchctl` CLI inside the app bundle, plus a `notboringnotch://` URL scheme for simple one-shot alerts.
- The companion extension "Not Boring Notch" offers `no-view` commands and a cross-extension provider, and talks to the socket the way Dondori does.
- Script Commands can call `notchctl`.

- Pros:
  - A real two-way story: Raycast-side code pushes alerts, progress and panels.
  - It follows proven store precedent.
  - Cheap at rest: the app idles on a socket, with no polling.
  - The same API serves non-Raycast clients (shell, Claude Code hooks, CI scripts; see upstream #951 and #1470).
- Cons:
  - The user's existing extensions still can't feed the notch unless they are scripts or our extension.
  - The extension has to be published or installed from source.
  - We own a protocol to version.
  - A socket in a container path is less pretty, and the extension needs to find it. Use a fixed, documented path, or let the app write the path to a well-known file.

### C. Script Commands and CLI only (no Raycast extension)

The same app-side socket and `notchctl` as B, but no companion extension. We ship a folder of example Script Commands (`notch-alert.sh`, `notch-timer.sh`, …) that the user adds to Raycast. The user wraps their own workflows with them.

- Pros:
  - Smallest surface, with no store review.
  - Scripts are transparent.
  - Raycast's `silent` and `inline` modes already map well to alerts and chips.
- Cons:
  - Power users only.
  - Three arguments maximum.
  - No access to Raycast's JS APIs (`launchCommand`, cross-extension conventions).
  - Not discoverable for normal users.

(Rejected: running extensions in our own shim runtime, the Simple Notch approach, because VISION explicitly excludes it. Also rejected: decrypting Raycast's databases or scraping its windows through Accessibility, because of the ToS and fragility.)

## Recommendation

**B + A, built in layers, with C falling out for free.**

1. **App-side local API first.**
   - A unix-socket server with a small versioned JSON protocol (`v:1`) and message types for alerts, live activities and panels.
   - `notchctl` in `Contents/MacOS` (or `Contents/Helpers`).
   - A `notboringnotch://alert?...` URL scheme for one-liners.
   - These are independent of Raycast and also deliver C.
   - Rate-limit and coalesce by `id`, show the source in the UI, and redact on the lock screen by default.
2. **Companion Raycast extension.**
   - `no-view` commands: Show Alert, Start Progress, Show Panel, and Toggle Notch Panel.
   - A cross-extension `show` command following `raycast-cross-extension` conventions.
   - An `interval` command (default off) that reports the installed-commands list to the app, so the app needs no sandbox exception.
   - Start installed from source, and publish once the protocol is stable.
3. **Raycast launcher panel (A).**
   - Read the manifests, either sent by the companion extension or read directly with a read-only home-relative exception.
   - Let the user pin commands, and fire deeplinks.
   - Explain the one-time "Always Open Command" prompt in onboarding. Each newly pinned command will prompt once. A good place for it is right after pinning, with a "Try it" button so the prompt appears while the user expects it.

Why this order: the push API is what makes the notch a *display* for Raycast, and it is fully supported. Launching is useful but one-way. The prompt behavior is now tested and acceptable: one approval per command, then silent.

## Product design (agreed 2026-10-21)

**Where Raycast lives in the UI.**
- Not a separate page: that is the tab UI item 1 deletes.
- Not a freeform customizable home: that fights compact-only and multi-display sizing.
- The home view stays as it is, with now playing (`CompactHomeView`) on top. A bar of buttons sits below it, and the bar is what users customize.

```
┌──────────────────────────────────────────────┐
│  [art]  Song title — Artist      ◀◀  ▶  ▶▶   │  ← CompactHomeView, unchanged
│  ──────────────────────────────────────────  │
│  📅  🪞  🗂   │   🎨  🔍  📋  ⏱   │   ⋯        │  ← the bar
└──────────────────────────────────────────────┘
   built-in      pinned Raycast     Raycast
   panels        commands           panel
```

**Behavior.**
- Built-in buttons expand into their item 2 panel.
- Pinned Raycast commands show the extension's own icon from `assets/`. A click depends on the command's mode:

  | Command | What a click does |
  |---|---|
  | `no-view` | Deeplink with `launchType=background`, then a brief "sent" state. Raycast reports nothing back, so we never claim success. |
  | Has `arguments` | Expands the notch into a small form generated from the manifest, then sends the deeplink. |
  | `view` | Collapses the notch and opens Raycast. |
  | `menu-bar` | Not pinnable. Launching it only refreshes Raycast's own menu-bar item. |

- "⋯" expands a Raycast panel. It holds the pins that don't fit and, later, panels pushed by the companion extension.
- Pushed alerts and progress are not part of the home view. They go through the live-activity and alert system, so they show while the notch is closed.
- The closed notch shows no pins for now. We can revisit a hover strip once the bar exists.

**Reuse what's already there.** The app already has the right pieces, so match their style and don't build parallel ones:

| Need | Existing piece to use |
|---|---|
| Bar buttons | `HoverButton` (`components/HoverButton.swift`): the same hover capsule, sizes and symbol transitions the music controls use via `MusicControlSlotButton`. For extension PNG icons, add an image variant of `HoverButton`, not a new button style. |
| Bar item model and Settings | Copy the `MusicControlButton` pattern: a `Codable`, `Defaults.Serializable` enum or struct stored under one `Defaults` key in `Constants.swift`, like `musicControlSlots`. The Settings pin list should look and behave like `MusicSlotConfigurationView`. The Raycast settings page follows the existing `Form`/`Section` style of `components/Settings/Views/*` (for example `ShortcutsSettingsView`), using `HelpText` and the badges from `SettingsHelpers.swift`. |
| Panels ("⋯", argument form) | The item 2 expandable-panel mechanism (per-panel preferred size and an animated morph of `NotchShape`). Don't add a new window. |
| Pushed alerts and activities | Add cases to `LiveActivityItem` in `LiveActivityStack.swift`, modeled on `.notification` and `NotificationLiveActivity`. Transient alerts auto-expire and hand back to music, exactly as notifications do now. Short, one-off feedback can follow the `PowerStatusNotice` and battery-interrupt pattern. |
| Text that doesn't fit | `MarqueeText` (`components/LiveActivities/MarqueeTextView.swift`). |
| New strings | `Localizable.xcstrings`. |

**Build order.**
1. During items 1 and 2: build the bar as a generic component with an item type, shipping only the built-in panel buttons.
2. Raycast pins: a manifest reader, Settings → Raycast, deeplink launch from the bar, and the argument form.
3. The local socket and `notchctl`, feeding new `LiveActivityItem` cases.
4. The companion Raycast extension, pushing panels into "⋯".

## Risks and unknowns

1. **Deeplink confirmation (now low).** Tested: the prompt appears once per command, background mode doesn't bypass it, and "Always Open Command" makes later launches silent and survives a Raycast restart. Still open: whether the approval survives Raycast updates, and whether the prompt itself brings the Raycast window forward. The user didn't report a window, but we didn't check for it specifically.
2. **Background launches stealing focus (medium).** `launchType=background` *should* keep Raycast in the background. We also need to check that `NSWorkspace.open` from our LSUIElement app doesn't activate anything, and that our URL scheme handler doesn't activate our app when an extension calls `open("notboringnotch://…")`. A socket avoids this entirely, which is one reason to prefer it over the URL scheme.
3. **Undocumented install layout (medium).** `~/.config/raycast/extensions/<uuid>/package.json` could move. Mitigation: prefer the companion extension's report, and treat direct reads as a fallback.
4. **No enabled-state or built-ins (low to medium).** The launcher may list disabled commands. Deeplinking a disabled command errors inside Raycast, and we don't know how that looks. Built-in commands must be added manually by deeplink, using Raycast's "Copy Deeplink" action.
5. **Sandbox (medium).** Socket placement inside the container, the read-only exception for `~/.config/raycast`, and whether the XPC helper or an unsandboxed CLI is the better host for the listener. `notchctl` itself is a separate binary run by Raycast, so it isn't sandboxed and connects as a client.
6. **Security of the local API (medium).**
   - Any local process running as the user can post alerts. That is acceptable, since it is the same trust level as the user, but rate-limit it and never execute anything on behalf of a message.
   - Panel actions should be limited to opening URLs, and a confirmation is needed for non-`raycast://` and non-`https` schemes.
   - The socket file should be mode 0600.
   - If we ever add HTTP, bind to `127.0.0.1` with a token, like masscode.
7. **Store review (low to medium).** "Requires companion app" extensions exist, but review could still push back. The fallback is distributing from source.
8. **Raycast 2.x churn (medium).** Raycast 2.8 is cross-platform (manifests list `Windows`) and has a new backend. Deeplinks and the manifest format are public and stable so far. Everything else is not.
9. **Unconfirmed bits:** the `raycast://ai-commands/…` and `raycast://confetti` URL forms, and the focus behavior of launches from our own app rather than from Terminal's `open -g`.

## Proposed prototype (1–2 days, throwaway branch)

1. **Deeplink behavior test, run by the user (no code).**
   - Use the installed `no-view` command Color Picker → Pick Color (`raycast://extensions/thomas/color-picker/pick-color`). It only opens the system colour loupe, and Esc cancels it.
   - From Terminal, run `open -g "raycast://extensions/thomas/color-picker/pick-color?launchType=background"` twice, choosing "Always Open Command" the first time. Then run it with `launchType=userInitiated`, then with a `view` command.
   - Record whether a prompt appears, whether the Raycast window or focus moves, and whether the choice persists after quitting and relaunching Raycast.
   - The exact steps are under [How to test the open questions](#how-to-test-the-open-questions).
   - The user needs to do this. Agents on this Mac must not launch or drive apps.
2. **Socket and CLI spike in the app.**
   - A `RaycastBridgeServer` behind a `Defaults` flag, listening on `<container>/Application Support/not.boring.notch/bridge.sock`.
   - One message type, `alert`, routed into the existing live-activity or alert path. Plus `notchctl alert --title … --subtitle …`.
   - Measure idle CPU and wakeups with the listener active.
3. **Companion extension spike** (`raycast-extension/` in this repo, or a separate repo).
   - One `no-view` command, "Show in Notch", with `title` and `subtitle` arguments, that writes to the socket (copy Dondori's client shape) and shows a HUD only on failure.
   - Run it via Raycast, via a hotkey, and via the deeplink from step 1.
4. **Manifest reader spike.** Parse `~/.config/raycast/extensions/*/package.json` with a read-only home-relative exception. List `no-view` commands in a debug panel and fire one by deeplink. Validate the deeplink built from `owner ?? author`/`name`/`command.name` against Raycast's "Copy Deeplink" output for 3 extensions.

Success criteria: an alert appears in the notch within ~100 ms of running the Raycast command, Raycast never comes to the front for `no-view` flows after the first approval, and there is no measurable idle cost.

## How to test the open questions

This is for the user to run. Agents don't launch apps on the shared Mac. No build is needed and the notch app is not involved. Run it from Terminal with Raycast running, and keep another app (such as Terminal) in front so focus changes are visible.

1. **First background launch:** `open -g "raycast://extensions/thomas/color-picker/pick-color?launchType=background"`
   - Expected: a Raycast confirmation prompt. Note whether it raises the Raycast window and whether it offers "Always Open Command".
   - Choose "Always Open Command". The colour loupe should appear. Press Esc.
2. **Repeat step 1.**
   - Expected: no prompt, the loupe appears straight away, and the Raycast window never shows. Terminal should keep focus once the loupe is dismissed.
3. **User-initiated launch:** `open -g "raycast://extensions/thomas/color-picker/pick-color?launchType=userInitiated"`
   - Note whether the Raycast window flashes or takes focus.
4. **`view` command with an argument:** `open -g "raycast://extensions/thomas/color-picker/convert-color?arguments=%7B%22text%22%3A%22%23FF6363%22%7D"`
   - Expected: a prompt if it is new, then the Raycast window opens on Convert Color with `#FF6363` filled in.
5. **Persistence:** quit Raycast from its menu-bar icon (Quit Raycast), reopen it, and repeat step 2. The "Always Open" choice should still apply.
6. **Background launch of a fresh command:** `open -g "raycast://extensions/thomas/color-picker/menu-bar?launchType=background"`
   - This is a menu-bar command, so it only refreshes the menu-bar item.
   - Note whether a prompt appears even though `launchType=background` is set.

Please write down these four answers, because they decide the launcher UX:
- Does the prompt appear for background launches?
- Does "always" persist?
- Does anything steal focus?
- Does the `arguments` prefill work?

### Test results (2026-10-21)

The user ran these on Raycast 2.8.0.

| Step | Result |
|---|---|
| 1. First background launch (`pick-color`) | A prompt appeared. After "Always Open Command" the picker opened. |
| 2. Repeat | No prompt and the picker opened. No Raycast window. |
| 3. `launchType=userInitiated` | Straight to the picker, same as step 2. No window flash and no prompt, so approval is per command, not per launch type. |
| 4. `view` command with `arguments` | A prompt (new command), then it opened with the argument prefilled. |
| 5. After restarting Raycast | Still no prompt. The approval persists. |
| 6. Background launch of a new `menu-bar` command | A prompt the first time, even with `launchType=background`. After that nothing visible, which is expected because it only refreshes its menu-bar item. |

The four answers:
- Background launches do prompt the first time for each command.
- "Always" persists across a restart.
- Nothing visibly stole focus after approval.
- Argument prefill works.

This supports the launcher panel (architecture A, layer 3 of the recommendation) as designed.
