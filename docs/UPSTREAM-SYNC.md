# Upstream relationship

Upstream: https://github.com/TheBoredTeam/boring.notch (GPL-3.0). Research done 2026-10-21 against `upstream/dev` at `4cfd830`.

## Decision

We took a **one-time snapshot** of upstream `dev` (v2.8-rc.2 plus later fixes) as our starting point and **will not merge upstream going forward**. Upstream is heading toward an extension platform and lock-screen widgets (we don't support the lock screen at all). We're building a compact-only notch whose extensibility is a Raycast bridge, so the two designs differ.

Consequences:
- Our `main` = upstream `dev` + upstream `main`'s trailing CI commits. Upstream's own `main` is stale (last app-code change April 2026) and was never a useful base.
- `upstream` stays as a **fetch-only** remote. Use it to cherry-pick and to read their PRs.
- We refactor and delete freely. Conflicts with upstream no longer matter.
- GPL-3.0 applies. Keep the license, copyright headers and `THIRD_PARTY_LICENSES`.

## What we still watch upstream for

Check upstream occasionally (at least each new release tag, and after major macOS releases).

1. **Security fixes.** `codex/security-xpc-client-auth` (XPC helper authentication) was not merged into `dev` at snapshot time. The related "both sides" auth and shelf temp-file fixes were merged, so we have them. Re-check the client-auth branch.
2. **macOS compatibility.** The app uses private APIs (MediaRemote via `mediaremote-adapter`, IOBluetooth battery selectors). These break between macOS releases and upstream notices first. Contributors were already testing macOS 27.
3. **Dependency bumps** (`mediaremote-adapter`, Sparkle or other packages). Do these ourselves rather than waiting.
4. **Bug fixes** in areas we kept: music controllers, shelf, calendar, HUD, window management.

Cherry-pick, don't merge. Note the source commit or PR in the commit message.

## Upstream PRs we're adopting or mining

| PR | What | Plan |
|---|---|---|
| [#1668](https://github.com/TheBoredTeam/boring.notch/pull/1668) | Bluetooth accessory connect/disconnect banner with battery level (+336, opt-in, new Bluetooth entitlement) | Adopt. Cherry-pick and adapt into our alert pipeline. Compare with DynamicNotch and MewNotch before finalizing. |
| [#1718](https://github.com/TheBoredTeam/boring.notch/pull/1718) | Clock in the closed notch on non-notch displays (+65, merges cleanly) | Adopt. Fit it into the compact idle state. |

## Upstream work we are deliberately not taking

- The **extension platform** draft stack (#1639–#1653, `stack/extensions-*`, about 10k lines). Our Raycast integration is different: it integrates the extensions a user already has installed in Raycast. We don't ship our own native extension runtime, store or installer.
- **Lock-screen work** (#1346 unlock animation and privacy lockdown, #1498 widget containers). We removed lock-screen support entirely, so neither is relevant.
- Focus timer (#1551), system activity monitoring (#1422), timer/clipboard/visualizer (#1376), Codex activity (#1527), YouTube Music bridge (#1396). Optional. Revisit individually if we want them.

## Reference for the last three weeks of upstream (snapshot context)

Human-authored changes on `dev` from about 2026-09-30 to 10-21: small and mostly localization.
- Music: option to hide the source app icon on album art; iTunes artwork fallback for streamed Apple Music; inline sneak peek when the music live activity is off.
- Displays: display preferences became a persisted enum; setting so a single notch follows the active display.
- Non-notch: legacy non-notch heights migrated to the supported minimum.
- Power: status notice centred under the notch; labels translatable.
- App/UI: reopening the app opens Settings; minimum window width dropped; more strings localized.

All of this is in our snapshot.
