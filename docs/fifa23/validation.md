# Validation

> Later packaging and GUI builds are recorded in the fork's development history. The user confirmed FIFA iOS success on 2026-10-25 without a mode/installed-hash association. The 2026-10-24 counters, versions and device details below retain their original scope; they are not new runs of every mode.

Evidence is recorded through the current branch status on 2026-10-24. Results
below are existing records reviewed for this documentation cleanup; no game build
or runtime test was repeated. Raw logs, captures, saves and manifests stay outside
Git. [Compatibility](compatibility.md) is the current feature summary.

## This tree's first build (2026-10-31)

The single-game re-cut was built once with `scripts/build-mac.sh` and
`scripts/build-ios.sh`, from the same inputs the earlier FIFA records used:

| | |
| --- | --- |
| Source | the snapshot in [upstream](../UPSTREAM.md), reduced to one profile |
| Game inputs | base 1.0.0 container, 1.0.3 update, `prod.keys` (external, not in Git) |
| ExeFS | the update's `main` and `sdk` |
| Rewritten modules | `patch_nso.py` on both modules, same rewriter and SDK patches |
| Shader chain | `a885c56c665a`, libraries `b-a885c56c665a`, `inputs.tsv` = this profile's inputs |
| Shader libraries | 520 macOS + 520 iOS, reused from the earlier verified build; none regenerated |
| Artifacts | `Release/Touchline23.app`, `Release/Touchline23.ipa` (unsigned) |
| Identity | `com.ohxiaoguang.touchline23`, name `Touchline 23`, version `1.0.3` |

Both artifacts were checked statically: identifiers and names as above, the
project icon in both, no container, keys, RomFS or `.nso` inside either, and the
IPA's payload carrying only the host, the libraries, the profile and the App
icon. **No gameplay run was made from these artifacts** — neither on a Mac nor
on a device. Everything in the feature table below still comes from the earlier
records, not from this build.

## About-page continuation (2026-10-31)

The shared view is `dm/apple/AboutTouchline.swift`, presented from the settings
areas of `dm/ios/Sources/Launcher.swift` and `dm/macos/Launcher.swift`. It follows
the existing `LanguagePreferences` and central localization catalog. The iOS form uses native
navigation, icons and links with the shared disclaimer; macOS uses a native
sheet and default-action Done button. No telemetry/update checks were added.

- Both build wrappers completed using existing rewritten modules and the existing
  520-library macOS/iOS shader sets, chain `a885c56c665a`. No shaders were compiled.
- New artifacts: `Release/Touchline23.app` and unsigned `Release/Touchline23.ipa`.
  IPA SHA-256: `43594e64727552ed0f5bcc9b683d32bba0f30a71c240d2d0b31a3537a3c50c8e`.
- macOS interactive checks passed: About opens and closes in English and
  Simplified Chinese; all three disclaimers and both repository URLs are visible,
  with no clipped text. The launcher identifies the existing external XCI/base,
  NSP/update and keys. The interface language was restored to English afterward.
- iOS full source compile check: 134 native sources and 6 Swift sources, zero
  failures. The check now includes the shared About view. The resource-test iOS
  type-check target also includes About and BundledResources.
- Swift package suite: 100 passing tests. Resource discovery/build-mode/macOS
  packaging regression subset: 55 passing tests. The scripts suite passed 141 tests;
  the iOS suite passed 14 tests, including launcher/localization, project
  generation and public-scanner coverage. The obsolete Xcode fixture
  was adapted to this profile/version and its profile-first bundle-ID behavior.
- Artifact checks passed: name `Touchline 23`, ID `com.ohxiaoguang.touchline23`,
  external `nsp` backend, IPA CRC, no embedded original container/key/NSO/RomFS
  inputs or provisioning profile. Git ignores both artifacts.

The renderer, guest rewriter, game profile shader inputs, resource-reader runtime,
launch/import logic and touch-input implementation were not changed in this work.
No game session or iOS device UI test was performed. iPhone/iPad About interaction,
gameplay and touch behavior still need user sideload testing; compilation and
synthetic regression checks do not establish those results. No device was signed
or installed. The former source-publication blockers are resolved in the [audit](public-audit.md).

## Independent rebuild from a clean tree (2026-10-31)

A separate directory held a fresh copy of this tree, a new virtual environment
and the game inputs, and nothing else. Both wrappers ran end to end from it and
the results were compared with the artifacts this tree had already produced.

| Element | Method |
| --- | --- |
| Source | `git clone` of `2537149` into an external directory, 34 MB, no untracked file |
| Python | new venv on 3.9.6 with `scripts/requirements-fifa23.txt` (capstone 5.0.7, lz4 4.4.5, pycryptodome 4.1.0) plus fonttools 4.60.2 |
| Tools | Xcode 27.1 with Metal 32023.921, .NET 10 (SDK 10.0.402), SPIRV-Cross at lock `8caa75a31452ae23`, XcodeGen |
| Game inputs | the user's XCI, 1.0.3 update NSP and `prod.keys`, read-only |
| Not used | this tree's `build/` and `Release/`, the earlier App/IPA, any earlier Shader cache (`DMSH_CAS`, `DMSH_PREFILL` and `IOSOUT` unset), another line's workspace, symlinks |

Each run extracted the ExeFS, rewrote `main` and `sdk`, prepared the EASF package
with the key discovered in `main` (no key file), translated and compiled all 386
programs for both platforms, wrote the runtime tables, built the host with the
repository's own libvpx, and packaged the App or the unsigned IPA: 200 s for
macOS and 235 s for iOS.

| Comparison with the earlier verified build | Result |
| --- | --- |
| macOS library file set | 1294 = 1294, no difference |
| `*_b.metal`, 386 files | byte-identical |
| metallib, reflection, `inputs.tsv`, `_b_build.json`, 908 files | byte-identical |
| iOS library, 907 files | byte-identical |
| Two independent clean builds | no difference |
| App `msl/` (520 metallib) and `program/` | no difference |
| `c1_full.tsv`, `cb_extent.tsv` | first-line timestamp only |
| `dmhost` | differs by the debug path compiled into it |

The libraries were 386 base, 101 readable-tile and 33 vertex-input ones
(520 per platform) with the same `inputs.tsv` stamp, and the compiler reported
`shaders 386: ok 386` with no cache hit. The regenerated MSL is therefore the
same text the earlier build used, and the Shader corrections this project carries
survive the regeneration: they live in the profile's tables (`shader_map.tsv`,
`shader_facts.tsv`, `shader_pairs_extra.tsv`) and in the chain tools, not in
edited output files. `git log --all --diff-filter=A` shows no `*.metal` or
`*.metallib` ever committed, so the libraries are products, not sources.

Runtime, with the clean host, the clean modules and the clean libraries reading
the containers directly (no packaging, no earlier App): a 200 s run presented
10,801 frames with 18,000 audio callbacks and no underrun, and a 330 s run
reached a real match (Manchester City vs Paris SG, clock 05:13 to 10:21) with
pitch, crowd, boards, players, shadows, HUD and Radar 2D normal.
`failed to create render pipeline` and `not written by vertex shader` counted 0;
the remaining `[RED]` lines were the known unimplemented NVN queries listed under
[compatibility](compatibility.md). iOS was built and compared statically only:
the IPA carries the 520 matching iOS libraries, and no device was signed,
installed or run.

In the clean clone the script suite passed 148 tests (154 with the regression
tests the two fixes added), `scripts/check_markdown_links.py` found 39 files and
191 links with no error, and `scripts/check_fifa23_public.py` reported no
findings.

Scope: byte-identical reproduction depends on the pinned toolchain above; another
Metal compiler version can produce different metallib bytes without changing what
runs. The 2 GB of libraries and artifacts stay outside Git — regenerating them is
the supported workflow, and the reference numbers above are what a rebuild is
compared against.

The rebuild also exposed two limits in the tooling, both fixed afterwards: the
launcher required a `build-manifest.json` that only the standalone source build
wrote, and the source build required `.git` at its last step, which a downloaded
source archive cannot answer. Both were rechecked after the fix: a tree exported
without `.git` (`git archive`) built the same 1294 library files byte for byte and
recorded `source_revision: null` in its manifest, and `scripts/run_fifa23.py`
started the game both from that output directory and from the wrappers'
`build/work`, which holds no manifest at all.

## Platforms and evidence

| Platform | Evidence | Scope |
| --- | --- | --- |
| MacBook Air M1, game 1.0.3 | Source-built host, rewritten modules, gameplay captures, Metal tests and user listening | Formal Manchester City vs Paris SG match, training, player selection, both Radar modes and observed materials |
| iPhone Air | Device diagnosis followed by user-tested gameplay reported in the latest commits | Formal matches in handheld/docked, normal crowds, lighting, sound/commentary, indicator, Radar, saves, touch controls and gamepad |
| iOS package | 520 iOS libraries and unsigned arm64 IPA; latest record reports 1,333 static checks | Package structure and metadata; not independent gameplay evidence |

The iPhone's original failure report identifies iPhone18,4, iOS 27.0.1 and 8 GB
memory. Detailed post-fix captures and automated counters are not published here;
feature confirmation is user feedback, not a comprehensive device matrix.

Historical maintainer records identify the feature report as
`ee6d92ea057566157686699c77db5da8f8baef74` and the memory-layout correction as
`e8b40e0749aba67a656ae923595cd2fd62a68d91`. These source IDs belong to the earlier
non-public development line, not this repository's Git history or publicly
retrievable test logs. The platform results above are retained reports with their
stated scope. They supersede the earlier awaiting-reinstall status; detailed Mac
shadow evidence must not be extended to full iPhone shadow validation.

## Reproducible build evidence

- Locked translator and Metal fingerprints passed; SPIRV-Cross was deliberately
  repinned, as described in [build](build.md#toolchain).
- The initial clean build translated all 386 base programs from two original
  decoded BIG4 archives, with no historical MSL/metallib inputs. Repeat builds
  reused only newly generated caches; the final successful invocation was not a
  second empty-cache build.
- The set contains 386 base, 101 readable-tile and 33 vertex-input libraries: 520
  total. Lowering covers seven Direct shaders and two ptrfix vertex shaders
  (192 and 24 rewritten reads). Six shaders lack a full constant-bound proof;
  they are not silently treated as proven.
- The normal Makefile built the source host and libvpx; the current NSO rewriter
  regenerated `main` and `sdk`. Encrypted EASF decoding matched the decoded
  archives byte-for-byte, including exported package/query/map tables.
- iOS packaging used prepared shaders and verified extraction with `IOSOUT`,
  `build_ipa.sh` and `pack_ipa.py`. Xcode/SDK 27.1 produced an arm64 app with
  minimum OS 26.0. Static checks covered ZIP CRCs, modules, the 64-file RomFS,
  fonts, icon, reflection and sensitive-file exclusions.
- The full top-level NSP wrapper was not exercised as a FIFA build path. Neither
  source-build manifests nor IPA static checks establish runtime correctness.

## Automated regression records

| Check | Recorded result |
| --- | --- |
| Python compatibility rules | 6 passing tests, including compute offset, Direct layout, rejection controls, ptrfix and variant-cache parity |
| Audio compatibility | 50 checks; channel impulses, saturation, queue/lifecycle recovery |
| Audio SPSC | 100,000 buffers appended/released without failure |
| Application interface | 34 checks |
| Reflection pool | 396 checks including all 386 base reflection files; also passed on the pixel-cover chain |
| Indirect GPU reads | 14 Metal checks, including interior origins, endpoints, null and invalid reads |
| Pending-write dependencies | 8 Metal checks, including full-pool writes and immutable extent parameters |
| Texture views | Synthetic 2D-array layer-0 read through a 2D declaration and negative type controls passed |

The legacy `t_refl` suite passed 14 fixture-independent checks but failed to load
two other-game fixtures. It is not counted as a passing suite. These are targeted
records, not full regression certification for other game profiles.

## Key failure controls

### iOS reservation

The original installed app exited at `nnosInitialize` with `FATAL reserve guest
AS`, before NVN/Metal work. Its process entitlement blob had no kernel
entitlements; a device-side probe reproduced the failed 8 GiB reservation while
6 GiB succeeded. The crash handler's `_exit` explains the missing system report.

The profile now reserves `0x140000000` (5 GiB), with a `0x60000000` (1.5 GiB)
alias and a 3 GiB heap region. Mac menus and matches had neither address-region
allocations nor alias maps; the startup request `0xba400000` is about 2.91 GiB
(3.125 GB). A 900-second Mac match run with the new layout ended gracefully with
no FATAL/CRASH or heap/alias refusal messages. Subsequent iPhone gameplay confirms
startup with the layout. Physical memory/jetsam remains a separate limit.

### Crowd stage interface

The same Mac save route compared:

| Stage-pairing strategy | Duration | Failed Metal pipelines |
| --- | --- | --- |
| Archive pair evidence only, chain `fda6fe95693e` | 1,200 s | 36 |
| First ten additional observed pairs | 1,200 s | 10, including new pairs |
| Pixel cover, chain `7f2ec952af18` | 1,500 s | 0 |

The fixed replay showed coloured crowds during entrance and match, with normal
HUD, Radar and indicator. iPhone feedback subsequently reported normal crowds.
Earlier coloured-crowd samples alone had not resolved the intermittent failure;
the stage-interface control supplies the concrete mechanism. See
[shader fixes](shader-fixes.md) for the fix and its input-map assumptions.

### Shadow pointer window

GPU-completed readback and a same-process full-pool / forward-only / full-pool
control demonstrated legal bone pointers before the instance binding. Intermediate
projections disappeared with the old window and returned with the full pool.
Formal-match captures contain real player projections. The control's advancing
camera prevents pixel-aligned comparisons; all historical faint-shadow causes
and uniform stability remain unproven. See [shadow investigation](shadow-investigation.md).

## Test method for future changes

1. Follow [build](build.md) with original inputs and matching-chain host/libraries.
   Record source revision, chain, tool lock, game version and device/OS.
2. On Mac, launch with a copied save and the existing control API. Enter a formal
   match, switch players, select both Radar modes and listen for commentary.
3. Check entrance, training, match and review scenes. For shadows inspect both
   GPU-completed masks and final frames; identify texture serials in the current
   run before dumping. A nonzero mask count alone is not a visual pass.
4. On iPhone, have the user test the unsigned build after sideloading. Check both
   operation modes, touch/gamepad input, save/relaunch, sound, crowds and shadows.
   Record these separately from Mac checks and IPA static results.
5. Extend venue, weather, special-scene and long-session coverage. Report exact
   tested scope and preserve failing samples outside Git.

A scheduled timeout with graceful exit is not a visual pass. Historical frame
samples include roughly 16.7–42.8 ms frame medians, 6.5–13.1 ms GPU medians and
about 2.8 GiB footprint. Focus changes, display drops and uncontrolled system load
prevent a controlled performance comparison. Loading audio underruns and
unimplemented diagnostic/query warnings occurred; a match is not a zero-warning
claim. No stable-60-FPS or zero-cost guarantee follows from these records.
