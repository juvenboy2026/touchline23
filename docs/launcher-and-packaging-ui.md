# Launcher and packaging UI changes

The record below was written for the fork's multi-game packaging UI. Its subject
matters here because Touchline 23's App uses the same launcher: the game folder,
the storage folder, the language menu and optional Mac MOD folder. Bilingual
menus and the settings rows it describes are what the current launcher shows.

Date: 2026-10-27. Branch: `feature/launcher-and-packaging-ui`.
Baseline: fetched and independently queried remote main
`87d8cacbede5f0a4e52e5108cb076d62dc68d313`.
The starting checkout was clean, with one worktree. The UI branch was created directly from
that remote main; the older DLC branch and local main were not used as the implementation base.
At that original delivery this work was local only, with no main merge or push.

## Changes and files

| Area | Files | Behavior |
| --- | --- | --- |
| Shared language policy/catalog | `gui/Sources/PackagingModel/Localization.swift`, `GameCatalog.swift` | System default; English fallback; existing English and Simplified Chinese catalog shared with launchers; manual choice persists |
| Phone controls | `dm/apple/LauncherSettings.swift`, `dm/ios/Sources/DmGamepad.m`, `TouchControlVisibility.h`, `main.m` | Persistent master overlay switch and separate optional 3D right-stick drawing |
| Launcher presentation | `dm/ios/Sources/Launcher.swift`, `dm/macos/Launcher.swift`, shared `LauncherSettings.swift` | Localized controls/status, language picker, verified preflight DLC count and real resource diagnostics |
| Packaging controls | `gui/Sources/NXPackagingGUI/App.swift`, `PackagingModel/Configuration.swift` | Directory update selection disabled with reason; external mode omits inactive bundled inputs |
| Build/distribution wiring | `dm/ios/project.yml`, `dm/ios/tools/compile_check.py`, `dm/resource/tests/Makefile`, `scripts/build_mac_app.py`, `scripts/build_packaging_gui.py`, `tools/packaging_gui/distribution.py` | Both launchers compile the existing canonical catalog; standalone tool payload includes it |
| Tests | Swift configuration/localization tests, `scripts/tests/test_gui_localization.py`, `scripts/tests/test_launcher_platform_settings.py`, `dm/apple/tests/LauncherSettingsChecks.swift`, `dm/ios/tests/test_touch_visibility.py` | Persistence, language fallback, stage/count states, native visibility policy, the iOS-only touch switches and the Mac filter, and argument consistency |
| Docs | README files, packaging guides, this report | Current defaults, controls and validation limits |

## Phone controls

The iOS launcher adds three switches, each its own variable, saved per game in UserDefaults and
overridable from an environment file:

| Switch | Variable | Default | What it decides |
| --- | --- | --- | --- |
| `Enable touchscreen input` | `DM_TOUCH_INPUT` | on | whether the game is sent the touch screen at all — taps, drags and gestures |
| `Show virtual controller` | `DM_TOUCH_CONTROLS` | on | whether the overlay is drawn |
| `Show right stick in 3D mode` | `DM_RIGHT_STICK_VISIBLE` | off | whether the (already drawn) 3D right stick is visible |

They never share a value: turning the touch screen off leaves the overlay, its buttons and the
layout button working, and turning the overlay off leaves the game its touch input. Edits save
immediately, including if the user closes before Play. An env-file value remains locked and
authoritative. `DM_TOUCH_INPUT` is applied once, at the overlays' single boundary to the host
(`DmGamepad.m pushGame`), so it covers every game and both console modes without touching game
logic; a Tap-layout press with the switch off reaches neither the game nor any control but the
layout button, which still cycles to 2D or 3D.

`Touch feedback` (`DM_TOUCH_HAPTICS`) is the fourth phone setting and comes from the game profile's
settings list rather than the iOS block, because the haptic click belongs to the virtual gamepad.
A macOS launcher filters it out — `DmGamepad.m` is its only reader — while game rumble
(`DM_RUMBLE`) stays, since a controller on a Mac rumbles.

The master off state hides the entire control layer and routes screen touches to the game.
Physical controller handlers, buttons, axes and controller auto-hide remain unchanged. The right
switch only draws the existing floating right-stick center/knob; hit testing, movement and dead
zones are unchanged. It stays editable whenever the master switch is on, whatever layout is
saved or in force, so a choice can be made before switching to 3D; it is disabled only when
controls are off. Its saved choice is retained. Runtime layout changes hide the visual in 2D/Tap
and restore it in 3D; connected controllers still hide the whole touch overlay.

The layout button cycles Tap → 2D → 3D → Tap in handheld and docked mode alike. Docked used to
hide Tap (the Switch's screen is out of reach there) and step 3D back to 2D; the host now feeds
the game the touch screen in both modes, so all three layouts are offered in both.

## Resource status on iOS

Embedded mode (`DMResourceBackend=directory`) shows no resource section at all: the game files are
inside the App, so there is nothing to scan, choose, version-match or diagnose. External mode
(`nsp`) keeps the whole thing — the file rows, the rescan button, the choice between conflicting
copies, the DLC discovery count and the diagnostics.

Hiding the section does not hide a broken App. `main.m` still refuses to boot without the profile's
RomFS marker, and the launcher checks the same thing by the same rule (`BundledResources`): the root
`main.m` already resolved and exported as `DM_ROMFS`, then `Documents/romfs`, then the App's own
`romfs`, each counting only when it holds the profile's marker (`DM_ROMFS_MARKER`); then a Metal
library under `DM_MSL_DIR` (or `<App>/msl`). Judging `<App>/romfs` alone made the launcher contradict a
game that was running from the copy in Documents, so the roots are the host's, in the host's order.
When none of them has the marker the launcher says which part is missing, and `log.txt` records the
answer (`launcher: embedded resources: …`). The Play button is unchanged in both modes, and the DLC
packed into `aoc/` is still mounted at run time.

`DM_PAD_LAYOUT_DEFAULT` passes the compiled profile's existing layout to the settings UI. No game
profile or compatibility constant is changed. The gamepad is created after launcher settings are
applied, so the current launch sees the selected values.

## One language mechanism

The existing `GUIText` catalog and `InterfaceLanguage`/`LanguagePreferences` remain canonical.
They are compiled into the launchers as well as the packaging GUI, rather than maintaining a
second translation dictionary. Build/distribution paths explicitly include that source.

A new installation follows the system's preferred UI language: English and Simplified Chinese
are supported; unsupported languages fall back to English. Traditional Chinese has no separate
translation and currently falls back to English. The picker offers System, English and 简体中文.
Existing explicit saved language choices are retained. System mode resolves again after restart
and observes locale changes. The packaging preference uses its existing key; launchers use
`launcher.interface-language.v1` in their own App domains. Interface language is separate from
`DM_LANG`, the language the game itself supports.

Launcher settings labels, choice names (including all NACP language choices), buttons and status
chrome use the same catalog. Original low-level resource errors, file names, paths and raw tool
output remain available under the explicitly labelled technical diagnostics disclosure. The main
status and resource-notice indicator are localized. Long scan diagnostics show the first 20 items
in a bounded scroll area instead of growing the launcher without limit.

## Packaging mode and DLC presentation

Directory mode still needs the correct optional update to prepare code/resources consistently;
hiding it and silently dropping the path would change the build. Its field and chooser are
therefore disabled, with instructions to switch to External mode to edit it. The retained update
is sent to both modes and checked by the existing engine. Switching to External omits Directory-only
RomFS/AOC arguments, while retaining their UI values for a return to Directory mode. Existing
configuration observation clears reviews, cancels/debounces identification and requires a new
preflight; the execution guard also compares the full reviewed configuration.

External launchers show `DLC verified before launch: N` only when the existing discovery selection
has passed verification. The count comes directly from `ResourceCombination.dlcs`. During scan,
failed verification or no selection it shows an explicit unknown/unverified state, never a stale
count or a fabricated zero. Real foreign/corrupt/unsupported-resource notes and verification errors
are exposed through the existing report; resource notices are highlighted before launch.

The iOS conflict-selection path now retains/applies the chosen report, including its AOC environment,
so a later verification does not apply a different report selection. Rescan clears stale presentation
state. The shared discovery/reader/AOC engine itself is unchanged.

Directory launchers do not have a reliable preflight DLC scan through that existing API. They say
so and defer actual availability to runtime. Neither launcher calls discovery counts "loaded";
an explicit note distinguishes startup verification from the game's eventual Count/List/Mount/Read.

## Verification

Final selected checks, with repeated attempts not added to totals:

- **65 Swift tests passed**: localization, configuration, game catalog and approval behavior.
- **5 localization coverage tests passed**: existing packaging strings, launcher labels/notes and
  all generated game-language choice labels use the shared catalog.
- **37 shared resource-discovery tests passed**, including existing DLC fixtures.
- **3 Xcode preparation/workflow tests passed**, using synthetic inputs.
- **1 native visibility-policy test passed**, executing all 16 switch/controller/layout combinations.
- Separate compiled LauncherModel harness passed default values, immediate persistence/reload,
  retained right-stick choice, layout gating and env-file override checks.
- iOS compilation: **134 native sources + 4 Swift sources**, zero failures. macOS launcher compiled
  and linked with the shared catalog. `git diff --check` passed.
- Standalone packaging GUI App built and passed `codesign --verify --deep --strict`. Its validation
  copy uses a separate bundle ID (`org.nxnative.packaging-ui-validation.20261027`) to isolate all
  test preferences from the user's original GUI.

Native UI inspection of that isolated App verified: initial System/Chinese display, disabled update
field and chooser with the Directory explanation, live English switch, English retained after
quit/relaunch, update editing restored in External mode, and System restoring Chinese. The test App
was then closed. No packaging command or game was launched during those UI interactions.

The GUI validation App and logs are under
`/path/to/launcher-ui-validation-20261027/`; scratch logs used
`/tmp/nx-ui-20261027/`. For the persistence harness:

```sh
xcrun swiftc -swift-version 5 -parse-as-library gui/Sources/PackagingModel/Localization.swift dm/apple/LauncherSettings.swift dm/apple/tests/LauncherSettingsChecks.swift -o /tmp/launcher-settings-checks
/tmp/launcher-settings-checks
python dm/ios/tests/test_touch_visibility.py -v
python -m unittest scripts.tests.test_gui_localization -q
```

## Limits and preserved behavior

The extra Xcode workflow check exposed an inherited fixture that pointed to a nonexistent
Profile directory during GL cache preparation. The fixture now copies the registered metadata
into its owned temporary directory; assertions and production compatibility checks are unchanged.
The original error log is retained, and all three tests pass after that setup correction.

No phone/controller hardware or iOS touch interaction was tested; persistence/policy tests and
native compilation are the evidence for those changes. No complete game build, Shader compilation,
FIFA game regression or update/DLC compatibility study was repeated. The generic DLC reader/services,
registry/engine, Shader sources/chain, FIFA profile and Darkest Dungeon profile/GL compatibility
implementation have no changes from the baseline. Shared discovery regressions remain passing.
Unsupported system languages use English; raw technical diagnostics retain their original text.
Reliable bundled DLC preflight enumeration remains unavailable and is reported honestly.

## Optional Mac MOD folder (2026-10-28)

The Mac launcher's Storage location section now places an optional MOD folder
row immediately below Saves and logs. Choose/Change remembers a folder bookmark;
Clear removes the bookmark and disables the overlay on the next game start.
No selection removes DM_ROMFS_OVERLAY even if an old environment supplied it.
Both bundled RomFS and external NSP modes use the same selection policy.

Select the RomFS overlay root. For Darkest Dungeon the layout is
`<root>/mods/<MOD>/project.xml` plus each MOD's modfiles.txt, preview and assets.
The enclosing folder with a romfs child, or the standard mods directory directly
containing individual projects, is also recognized. Files stay in place and are
read only; the launcher neither imports nor edits MODs. A missing selected folder
is reported before starting, and the user can choose it again or clear it.

Five executable Swift policy tests cover both backends, no selection and stale
environment removal, the three conventional folder choices, spaces/Unicode,
missing paths and the host's colon-delimited root restriction. Localization and
platform-setting checks pass, as does the Mac packaging regression. Native UI
inspection confirmed the row position, initial disabled-MOD text, opening the
folder panel and cancelling without changing the selection. Complete native
folder confirmation and restart interaction were not established by automation;
the directory/environment policy was exercised with synthetic folders instead.
No game, user save or user MOD was run for this chooser validation.
