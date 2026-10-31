# Game resource auto-discovery (macOS and iOS)

> Historical engineering report for the shared discovery implementation. Dated
> build/status statements and other-title cases below retain their original scope;
> they are not the current product support list. Use the [current launcher guide](launcher-and-packaging-ui.md)
> and [FIFA validation](fifa23/validation.md) for Touchline 23 behavior/evidence.

Status: implemented on `feature/resource-auto-discovery`. Scope: how a packaged game App finds
its own base game, update and console keys. It does not change the XCI/NSP reader, the guest, or
the packaging GUI.

## What changed for the player

| | before | now |
| --- | --- | --- |
| macOS | pick a base file, an update file and a keys file separately | pick **one folder**; every sub-folder is searched |
| iOS | files had to be `Documents/resources/{base,update}.nsp`, `prod.keys`, imported with a copy | drop the files anywhere under the App's `Documents`; nothing is copied |
| naming | fixed names required on iOS | any name; the container's bytes decide |
| version | checked at mount, inside the game | checked in the launcher, before Play is offered |

Nothing is copied, renamed, unpacked or modified. Containers are read in place, read-only.

## The shared module

`dm/apple/ResourceDiscovery.swift` — compiled into **both** Apps (`scripts/build_mac_app.py` for
macOS, `dm/ios/project.yml` + `dm/ios/tools/build_ipa.sh` for iOS). Only two things differ per
platform:

* the scan root — the folder the player picked (macOS, kept as a security-scoped bookmark) or
  `Documents` (iOS);
* where the result is handed on — a child process environment (macOS) or `setenv` before the
  guest mounts (iOS).

Everything else is one code path: walking, sniffing, probing, pairing, verification, ordering,
conflict reporting.

```swift
let report = ResourceDiscovery.scan(root: folder, titleID: titleID,
                                    modules: ResourceDiscovery.preparedBuilds(bundle: .main))
report.state        // ready / conflict / missingKeys / missingBase / versionMismatch / updateMismatch / nothingFound / unavailable
report.selection    // base + update? + keys, all verified
report.combinations // every verified combination, for the chooser
report.message      // one player-facing sentence
report.notes        // what was skipped and why, key-free
```

The module never decides from a file name alone. Names give a *hint* (which files to open, and
what to call them in the UI); the container's own table decides what a file **is**.

### The reader's probes (`dm/resource/nxrom.c`)

Three read-only additions, shared by everything that needs them (the Mac launcher links
`nxrom.c`; on iOS it is already part of `hle_resource.c`):

| function | what it reads | cost |
| --- | --- | --- |
| `nxrom_probe_container` | the container table, the Program NCA header, the RomFS section type | a few KiB, whatever the file's size |
| `nxrom_keys_usable` | key *names* (header_key, key_area_key_*, titlekek_*) | one small text file |
| `nxrom_verify` | `nxrom_open` + every prepared module's Build ID | one mount, no payload |

`patched` in the probe output is the discriminator between a base game and an update: an update's
Program NCA carries a **PatchRomFS** (BKTR) storage, a base game's an ordinary IVFF. That is a
content fact, not a naming convention.

No full-file hashing, no extraction, no second copy. `dm_mac_resources_check` is now a thin
wrapper over `nxrom_verify`, so the Mac launcher and the iOS App accept exactly the same files.

## Identification, in order

1. **Title ID** — the App's own: `NXTitleID` in the macOS `Info.plist`, `DM_GAME_ID` from
   `game_profile.h` on iOS (exported to the launcher as `DM_TITLE_ID`). Never guessed, never
   hard-coded per game.
2. **Candidates** — regular files only (symbolic links are skipped and counted, so a cycle cannot
   hang a scan), at any depth, in a stable byte order. A file is looked into when its name ends
   in `.nsp/.xci/.nsz/.ncz/.xcz`, or when it is at least 4 MiB (a dump under any other name is
   still found — the bytes decide).
3. **Container** — `PFS0` at 0 for an NSP, `HEAD` at 0x100 for a gamecard. The extension is
   never consulted: a renamed XCI is an XCI.
4. **Keys** — the first `*.keys` file (a `prod.keys` name wins) that has `header_key` plus a
   `key_area_key_*` or `titlekek_*`. Values are never read out, logged or shown; only missing
   *names* are reported.
5. **Pairing** — a Program NCA's title must be this game's, and the RomFS type decides base vs
   update (a `[UPD]` tag only breaks the tie for a container without a readable Program NCA).
   The same file reached twice (a hard link) is one candidate, by inode — never by hashing.
6. **Verification** — `nxrom_verify` opens the pair exactly as the host will and compares every
   prepared module's Build ID. Only a passing pair is offered.
7. **Ambiguity** — one passing pair is used; several are a `conflict` and the launcher lists
   them; an update that cannot match while the base game can is `updateMismatch` and the launcher
   offers "base game only" explicitly. Nothing is picked silently, and the highest version is
   never preferred.

## Version matching

The App's program, ExeFS and shaders are pre-processed, so the update must be the one the build
was prepared from — not the newest. `preparedBuilds` reads `prepared_builds.tsv` (macOS) or the
rewriter tables `*.fixups.tsv` (`# BUILD_ID`), both of which the build already packages. A
mismatch reports the module:

> Selected base/update does not match prepared module main. Choose the matching game version.

With no prepared metadata at all the App refuses (`.unavailable`) instead of skipping the check.

## macOS launcher (`dm/macos/Launcher.swift`)

1. **Choose folder** → `NSOpenPanel`, `canChooseDirectories`. The URL is stored as a
   **security-scoped bookmark** (`resource.bookmark.folder`), re-acquired on every launch, so the
   permission survives a restart.
2. The scan runs on a background queue; the UI shows a spinner and then base / update / keys with
   their real names, format and size.
3. A conflict (or an unusable update) shows the verified combinations with one button each; the
   choice is remembered per title (`resource.pick.*`) and re-applied on the next scan *only if it
   still verifies*.
4. **Play** re-verifies the selection once (a removed drive or a changed file is caught here) and
   then starts `dmhost` with `DM_RESOURCE_NSP/UPDATE/KEYS` pointing at the original paths. Access
   stays held for the whole session.
5. The storage folder (saves, logs, temporary files) is separate and unchanged; the game folder is
   never used for writes.
6. **Rescan** and **Change** are always available; Directory (bundled RomFS) builds show the old
   "nothing to select" panel.

## iOS launcher (`dm/ios/Sources/main.m`, `Launcher.swift`)

Order matters: the discovery must finish before anything can read a path.

```
main()
 └─ boot_env()                     directories, log, env.txt, language
     ├─ dm_resource_discovery_boot(Documents, DM_GAME_ID)   ← scan + verify + setenv
     └─ dm_host_preload_start()    module loading (reads the environment set above)
UIApplicationMain → launcher (SettingsView)
 └─ Play → verify once more → dm_main → guest MountRom reads DM_RESOURCE_*
```

* `dm_resource_discovery_boot` is the shared module's `@_cdecl` entry: it scans `Documents`,
  applies the selection with `setenv(..., overwrite: 0)`, marks the containers
  `NSURLIsExcludedFromBackupKey` (metadata only — no file is moved or deleted, so a 15 GB NSP in
  Documents does not become a backup burden), and returns a message for the log.
* `overwrite: 0` means a `Documents/env.txt` that sets `DM_RESOURCE_*` still wins: the diagnostic
  path is preserved, but normal use no longer needs an env file.
* If nothing matches, the boot code points at the legacy `Documents/resources/{base.nsp,
  update.nsp,prod.keys}` paths so the launcher's message is about the content, not a missing
  path. A folder that already uses that layout is found anyway: the scan covers it.
* The launcher shows what was found, a **Look again** button, and the same conflict chooser as the
  Mac. **Play** is disabled until a verified selection exists; a failure never starts the game.
* The old per-kind `fileImporter` and its `copyItem()` import are gone: normal resource import is
  "put the files in the App's folder", which is what `UIFileSharingEnabled` already shows.

## Performance and file safety

* Probe cost is bounded by headers: a 3.7 GB NSP is identified by reading a few KiB.
* A 158,582-file tree (a developer folder, 1040 symlinks, many build outputs) scans in ~5.5 s on
  this machine, of which ~2 s is the file-system walk; a normal game folder is well under a
  second before the single verification mount.
* One inode-based de-duplication, no hashing, no copying, no writing, no directory creation, and
  no cleanup of anything the player owns.
* Depth is capped at 64 and files at 200,000 with a note, so a pathological tree cannot hang a
  launcher.

## Tests

`dm/resource/tests/test_resource_discovery.py` compiles the module into a small harness
(`dm/resource/tests/discovery_cli/main.swift`) and drives it over synthetic folders made by
`fixture.py` (a few tens of KiB each — never a copy of a real dump). 29 cases, all passing:

| brief | test |
| --- | --- |
| 1 FIFA XCI at the root | `test_fifa_xci_at_root` |
| 2 XCI in a deep folder | `test_unusual_name_in_deep_folder` |
| 3/4 base and update with `[v0]` / `[v262144][UPD]` | `test_base_and_update_with_version_tags` |
| 5 `[APP]` / `[UPD]` prefix names, different folders, keys elsewhere | `test_app_upd_prefix_names_in_different_folders` |
| 6 Chinese names, spaces, brackets, `™` and full-width punctuation | `test_chinese_names_and_special_characters`, `test_fifa_xci_at_root` |
| 8 mixed games, only this title's files | `test_mixed_folder_selects_only_this_game` |
| 9 several valid updates | `test_two_matching_updates_are_a_conflict_and_a_choice_wins` |
| 9b the same file twice | `test_same_file_twice_is_not_a_conflict` |
| 10 wrong title | `test_other_title_only_is_missing_base` |
| 11 renamed container | `test_container_with_a_wrong_extension_is_judged_by_its_content` |
| 12 missing keys / unusable keys / no leak | `test_missing_keys`, `test_unusable_keys_say_what_is_missing`, `test_keys_content_is_never_echoed` |
| 13 missing base | `test_missing_base_but_update_present` |
| 14 valid file, unusable name | `test_nonstandard_name_is_accepted`, `test_small_unknown_file_is_not_opened` |
| 15 legacy `Documents/resources` | `test_legacy_documents_resources_layout` |
| 16/17 restart, repeatability | `test_scan_is_repeatable_and_ordered` (+ the bookmark restore in the Mac App) |
| 17 iOS reboot re-identifies without an env file | `test_boot_entry_sets_the_paths_itself`, `test_boot_entry_explains_a_folder_without_game_files`, `test_boot_entry_leaves_paths_an_env_file_already_set` |
| 19 build mismatch | `test_base_from_another_build_is_refused`, `test_update_that_does_not_match_is_reported_not_dropped`, `test_no_prepared_metadata_refuses_to_guess` |
| 20 no second copy, no modification | `test_scan_reads_headers_only_and_writes_nothing` |
| cycles, unreadable folders | `test_symlinked_folders_do_not_loop`, `test_unreadable_folder_is_skipped` |

The last three of the boot tests call `dm_resource_discovery_boot` itself — the symbol
`dm/ios/Sources/main.m` links — so the C boundary, the message buffer and the environment it
leaves behind are covered, not just the Swift API.

## Build and verification

Historical acceptance re-check on 2026-10-26 (maintainer-source record `5690b5f`,
not a current branch or this repository's commit):

| what | result |
| --- | --- |
| `cd dm/resource/tests && make core` | all suites pass, including the 29 discovery cases |
| `make mac` (real `nxrom.c` + `resource_check.c`, ASan/UBSan) | base/update accepted for NSP and XCI; wrong build and malformed metadata refused |
| `make hle GAME=010015100B514000` | NSP/XCI + update mount, save and fault paths pass |
| `make platform` | `nxrom.c` compiles for arm64-ios; the three shared Swift files type-check against the iPhone SDK |
| iOS `tools/compile_check.py` (`GAME=010015100B514000`) | `134 files + 3 Swift files, 0 failed` |
| macOS launcher, real compile + link (`build_mac_app.build_launcher`) | clean, no warnings |
| packaging a complete App with that real launcher (audit inside `package()`) | passes: `backend nsp, 1 program, 2 Shader files, stamp True, no RomFS, no containers or keys` |
| symbols in the packaged `Contents/MacOS/launch` | `_nxrom_probe_container`, `_nxrom_keys_usable`, `_nxrom_verify`, `_dm_mac_resources_check`, `_dm_resource_discovery_boot` all defined (`T`); the discovery messages are embedded |
| iOS `ResourceDiscovery.swift` compiled for `arm64-apple-ios26.0` | `_dm_resource_discovery_boot` exported (`T`); `main.m` holds the matching undefined reference, so the link closes |
| boot order in `main.m` | scan at line 71, `dm_host_preload_start` at 100, `UIApplicationMain` at 149 — all inside `boot_env()` |
| real 3.7 GB folder (158,582 files) | `ready` in 5.5 s, `[v0]` base + `[v262144][UPD]` update, prepared `patched_v262144` |

### Why no new `.app` / `.ipa` was produced

Both game builds need a Shader context that `validate_context` accepts, and that check is
deliberately strict: the context's `shader-summary.json` chain must equal `dm/gfx/nvn/dmsh_chain.h`,
the context's own `toolchain/gfx/tools/dmsh_chain.py` must recompute to the same value, the
context's gfx source snapshot must equal this tree's, and every reflection must carry that chain.

Re-checked on 2026-10-26 with the project's own validator:

```
dmsh_chain.py                 -> a885c56c665a   (matches the committed header)
validate_context(<wonder context>, macos) -> REFUSED: chain differs from the source tree
validate_chain_sources(<wonder context>)   -> REFUSED: snapshot differs ... tools/dmsh_chain.py
```

The original non-FIFA prepared contexts had earlier chain fingerprints and were
correctly refused. That dated result demonstrates cache/source validation; it is
not a current claim that FIFA artifacts cannot be built. Private context locations,
old workspace inventories and then-current branch state are omitted. Current FIFA
artifacts and library reuse are recorded in [validation](fifa23/validation.md) and
the [build guide](fifa23/build.md).

## Limits

* NSZ/NCZ/XCZ (compressed containers) are reported, not decompressed.
* DLC has its own implementation in the packaging engine (`tools/packaging_gui/dlc.py`). CNMT-verified ordinary DLC NSPs, including non-empty payloads, can be imported after installation and read directly. Base/update Build ID validation remains in force; compressed NSZ needs conversion to NSP first.
* A container smaller than 4 MiB whose name has no `.nsp`/`.xci` extension is not looked into.
* iOS conflict choices are not remembered across launches (the boot scan resolves the common
  case; a conflict is asked again).
* The macOS development-only `DM_RESOURCE_PICK` picker in `dm/host/front_mac.m` is unchanged; it
  is not part of a packaged App.
