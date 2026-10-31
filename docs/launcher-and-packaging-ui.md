# Touchline 23 launchers and packaging interface

This is the current UI description, replacing the earlier multi-game development
report. The product supports FIFA 23 Legacy Edition only. For user steps see the
[English packaging guide](packaging-gui.md) or [中文打包指南](packaging-gui.zh-CN.md).
[Validation](fifa23/validation.md) separates device play from compilation and UI tests.

## Language and branding

Both launchers and Touchline 23 Packaging use English/Simplified Chinese strings
from `gui/Sources/PackagingModel/Localization.swift`. The interface can follow the
system or use a saved explicit choice. Game language comes separately from NACP;
an interface translation is not evidence of an in-game translation.

The game App is Touchline 23, bundle ID com.ohxiaoguang.touchline23. The tool is
Touchline 23 Packaging, bundle ID com.ohxiaoguang.touchline23.packaging. Historical
internal names such as NXPackagingGUI remain implementation details.

## iOS / iPadOS launcher

External mode scans Documents and its subfolders, identifies the matching base,
optional update and keys, and displays resource errors before Play. Directory mode
uses bundled resources and shows real bundled-resource failures instead of an
external-selection success message. No new import path is introduced by About.

Three independent switches control touchscreen input, the virtual-controller
overlay and the visible right stick in 3D layout. Turning off the overlay does not
disable touchscreen input; hiding the right-stick drawing does not remove its
hit testing. The layout button cycles Tap / 2D / 3D. Physical-controller handling
and game rumble remain separate. These settings persist before Play, and explicit
environment-file overrides remain authoritative.

| Setting | Variable |
| --- | --- |
| Touchscreen input | DM_TOUCH_INPUT |
| Virtual-controller overlay | DM_TOUCH_CONTROLS |
| Right-stick visibility in 3D | DM_RIGHT_STICK_VISIBLE |
| Touch feedback / game rumble | DM_TOUCH_HAPTICS / DM_RUMBLE |

The shared iOS target includes iPad. Separate iPad gameplay and current iOS About
button interaction are not recorded; do not describe compilation as device testing.

## macOS launcher

Choose the game resource folder and storage location independently. The resource
reader scans without moving the game. Saves/logs go under the chosen storage root.
The optional MOD folder uses the existing overlay resolver for directory or external
resources. It replaces resource paths, not guest code or shader libraries; compatibility
with any individual FIFA MOD requires its own testing. No title-specific MOD behavior
from another game is part of this product.

Touch-only settings are filtered from macOS; controller rumble remains. Build IDs,
resource diagnostics and backend selection are unchanged by the UI simplification.

## About Touchline 23

Both settings areas present the shared `dm/apple/AboutTouchline.swift` view. iOS
uses a navigation sheet; macOS a native sheet with a default-action Done button.
Content follows the interface language and contains:

- [Project home](https://github.com/ohxiaoguang/touchline23).
- [Issue tracker](https://github.com/ohxiaoguang/touchline23/issues).
- Independent-community affiliation disclaimer, source-license boundaries and a
  warning about unauthorized paid IPA resale/repackaging.

There is no updater, telemetry or automatic network check. Links open only when
selected. macOS opening/closing and both languages were tested; iOS compilation
passed, with device interaction still unverified.

## Dedicated packaging UI

The main window directly names FIFA 23 Legacy Edition, base 1.0.0 and optional
update 1.0.3. It has no game browser, search or game-sort controls. The shared
catalog/registry schema remains for build metadata and developer diagnostics;
multiple synthetic fixture rows in its tests are not supported products.

macOS/iOS target selection, External XCI/NSP and Directory modes, version checks,
Shader cache reuse/generation, progress, cancellation and diagnostics remain.
The GUI hides the unused DLC editor and clears legacy saved add-on paths at
startup so invisible settings cannot alter a build. Shared add-on resource support
and CLI schemas remain intact.

Directory mode keeps the reviewed update and disables its editor with an explanation;
change the selection in External mode first. Every input/target/mode change invalidates
approval. A confirmation names exactly the reviewed targets that can build; one
failed target is not silently counted as success.

## Source and local checks

| Area | Source |
| --- | --- |
| Language and settings | Localization.swift, dm/apple/LauncherSettings.swift |
| Launchers / About | dm/ios/Sources/Launcher.swift, dm/macos/Launcher.swift, dm/apple/AboutTouchline.swift |
| Packaging form / configuration | gui/Sources/NXPackagingGUI/App.swift, PackagingModel/Configuration.swift |
| Shared discovery / reading | dm/apple/ResourceDiscovery.swift, dm/resource, dm/macos/resource_check.c |
| Tests | Swift PackagingModel tests, scripts/tests, dm/apple/tests, dm/ios/tests, dm/resource/tests |

Run [local checks](../README.md#development-and-local-checks). UI changes should
compile the GUI and test language/argument behavior without recompiling game
Shaders or rebuilding game artifacts. Real game MOD, device and scene validation
requires its own scoped evidence.
