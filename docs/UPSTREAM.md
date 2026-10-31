# Where this tree comes from

Touchline 23 is not a fork that keeps its history; it is a snapshot of
`ohxiaoguang/nxnative-zzg` reduced to one game and renamed. This page records the
exact source so a later update can be compared against it.

## The snapshot

| | |
| --- | --- |
| Repository | `https://github.com/ohxiaoguang/nxnative-zzg` |
| Branch | `main` |
| Commit | `6dcf9868582388173f81f4f02385cd4cdb125b3e` |
| Commit date | 2026-10-29 13:16:58 +0800 |
| Commit subject | Restore GL uniform defaults to fix combat recovery flicker |
| Taken | 2026-10-31 (`git clone`, then the history was dropped: `rm -rf .git && git init -b main`) |

The upstream lineage above that commit is `seedds/nxnative`, the original
project: the Switch kernel and service emulation, the NVN → Metal and Vulkan →
Metal backends, the GL layer, the Shader translation chain and the game ports are
its work. `nxnative-zzg` added the packaging engine, the resource reader and the
FIFA 23 bring-up. This project keeps the MIT license and the third-party notices
(`dm/third_party/`) that came with them.

The publication remote is `origin` at `ohxiaoguang/touchline23`. The
[publication audit](fifa23/public-audit.md) records the resolved notice/provenance
review and the checks required for the initial source publication.

## What changed on top of the snapshot

Everything else is upstream code, unchanged:

- **One profile.** `dm/games/01001C8016B4E000/` is the only game; the other 59
  profiles and their tables are gone. The profile gained a `bundle_id` row and
  its App name, IPA name and icon are Touchline 23's.
- **Names.** The App, the launcher, the packaging GUI and their user-facing
  strings say Touchline 23; the bundle identifiers are
  `com.ohxiaoguang.touchline23` (App) and `com.ohxiaoguang.touchline23.packaging`
  (GUI). Logs and run directories are named after the App.
- **Darkest Dungeon's adaptation removed.** `dm/host/dd_pointer.h`,
  `hle_dd_pointer_mac.c` and their tests, the MOD-metadata notes and the research
  script for that game are gone. Nothing else about MODs changed.
- **Build entry point.** `scripts/build-mac.sh`, `scripts/build-ios.sh` and
  `scripts/touchline_build.py` replace the multi-game command lines: one game, no
  picker, no title ID to type, and every stage can reuse a previous run's output.
- **Other builds' rewriter cuts.** `dm/tools/sdk_patches.py` kept one entry per
  Nintendo SDK build some other game shipped; this game's `main` and `sdk` need
  no cut, so the table is empty and the file keeps its form and its test. Take an
  entry from upstream only for a build this tree actually ships, after checking
  it by disassembly.
- **Docs.** The single-game guides in `docs/`; the other games' pages, the
  gallery and the research records were dropped. The FIFA 23 notes are kept
  because they explain why the port looks the way it does.
- **Icon.** `assets/app-icon/` holds the project's own icon and the script that
  draws it; no game artwork is used.

## Following upstream later

The tree has no upstream remote on purpose: a `git pull` would bring back 59
profiles and reintroduce the names. Compare by hand instead.

```sh
git clone https://github.com/ohxiaoguang/nxnative-zzg /tmp/nxnative-zzg
cd /tmp/nxnative-zzg
git log --oneline 6dcf9868582388173f81f4f02385cd4cdb125b3e..origin/main
```

For one of those commits, or for everything since the snapshot:

```sh
# what changed in the engine, the graphics chain and the tools
git diff 6dcf9868..origin/main -- dm/host dm/gfx dm/tools dm/resource dm/apple dm/macos dm/ios > engine.patch
# what changed in this game's profile (shader tables, build rows, patches)
git diff 6dcf9868..origin/main -- dm/games/01001C8016B4E000 > profile.patch
```

Apply the engine patch in this tree with `git apply --3way engine.patch` and
resolve the hunks that touch renamed strings (`Touchline 23` where upstream says
`nxnative`), the removed Darkest Dungeon hooks, or `scripts/` (this tree's build
script is its own). The profile patch usually applies without trouble; check the
`bundle_id` and `app_name` rows survive.

Then, as with any chain change upstream:

1. If `dm/gfx/tools/dmsh_*` changed, run `dm/gfx/tools/dmsh_chain.py --header`
   and commit the new `dm/gfx/nvn/dmsh_chain.h`; the chain version in the header
   is what the host and the Shader libraries agree on.
2. Rebuild the game's Shader libraries with `dmsh_build.py` (the build scripts do
   it when no library is given), or point `--shaders` at the old library and let
   the tool refuse it if the chain moved.
3. Rebuild the App or the IPA and play.

Per-build knowledge — rewriter cuts, observation gates, frame-step stubs — lives
in the profile's `patches.py` and in `dm/tools/sdk_patches.py`, keyed by NSO
build ID. A new game build needs those addresses carried over with
`dm/tools/nso_fnmap.py` and checked by disassembly before they are used; never
let them run on a build they were not found in. See
[the build notes](fifa23/build.md).

## Upstream files kept as they were

`LICENSE`, `dm/third_party/`, the notices inside `dm/gfx/tools/` and the
authorship comments in the engine are untouched. If a later sync restores a file
this project deleted, that is upstream's copy, not a merge of somebody else's
code.

## Publishing the source tree

`origin` is `https://github.com/ohxiaoguang/touchline23.git`, the branch is `main`,
and the local identity is `ohxiaoguang` with the account's GitHub noreply email and
`user.useConfigOnly=true`. Do not override upstream authorship or global settings.

The [publication audit](fifa23/public-audit.md) closes the former translator notice
and source-origin blockers. Before any later release, review the exact Git index,
run the content checks and tests, inspect all manual findings and verify the chain.
Normal `git push -u origin main` publishes only reviewed commits; build products
and private game inputs remain outside Git. Do not force push or rewrite history.

The [third-party index](../THIRD_PARTY_NOTICES.md) and translator
[provenance materials](../dm/third_party/translator-runtime/README.md) must remain
with the published source. Traceability does not assert an independently reproduced
historical compiler invocation or permission to distribute game-derived artifacts.
