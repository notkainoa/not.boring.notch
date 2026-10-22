# not.boring.notch

A compact macOS notch app that brings Raycast and its extensions into the notch.
It is a fork of [Boring Notch](https://github.com/TheBoredTeam/boring.notch)
(GPL-3.0), snapshotted from upstream in October 2026 and developed independently.

**Status: early development. There are no releases yet.**

- `VISION.md` – what we're building and in what order
- `AGENTS.md` – how to build, test and contribute (for people and agents)
- `docs/UPSTREAM-SYNC.md` – how this fork relates to upstream

## Building

```sh
scripts/dev.sh build   # build only
scripts/dev.sh         # build and run (quit any installed Boring Notch first)
```

Requires Xcode 26 and macOS 14 or later.

## License

GPL-3.0. See `LICENSE` and `THIRD_PARTY_LICENSES/`. Based on Boring Notch by
TheBoredTeam and contributors.
