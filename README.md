# Touchline 23

[简体中文](README.zh-CN.md) · [How the port works](docs/fifa23/README.md) · [Upstream record](docs/UPSTREAM.md) · [Packaging GUI](docs/packaging-gui.md)

Touchline 23 is a native Apple-silicon port of one game: **FIFA 23 Legacy Edition** for
Nintendo Switch, title ID `01001C8016B4E000`. The game's own ARM64 code runs; the
kernel services, the filesystem, the audio output and the GPU API (NVN) are
reimplemented for macOS and iOS, so there is no Switch emulator and no ROM
translation beyond what Apple's kernel requires.

It is a single-game project built on [nxnative](https://github.com/seedds/nxnative)
through the fork [ohxiaoguang/nxnative-zzg](https://github.com/ohxiaoguang/nxnative-zzg).
The execution architecture, the graphics backends and the original ports are
upstream work; see [provenance](docs/UPSTREAM.md) for the exact commit this tree
was taken from.

## The game it runs

| | |
| --- | --- |
| Game | FIFA 23 Legacy Edition (Nintendo Switch) |
| Title ID | `01001C8016B4E000` |
| Base game | 1.0.0 (`v0`) |
| Update | 1.0.3 (`v196608`), optional |
| Shader chain | `a885c56c665a` (`dm/gfx/nvn/dmsh_chain.h`) |

The base game and the update are two different builds of the same program: the
update needs its own RomFS, its own `main` and `sdk` and its own rewritten
modules. Never mix an updated RomFS with base code. The Shader library is built
from the base game's EASF archives and stays valid for both versions, because the
updates add no new shaders; the profile records both builds it was brought up on.

## Platforms

- **macOS 26 or later on Apple silicon** — the App is a plain `.app`; it reads the
  game from a folder you choose and keeps saves, logs and temporary files in that
  folder (inside `Touchline23/`).
- **iPhone and iPad, iOS 26 or later** — the build is an unsigned `.ipa` you sign
  and sideload yourself. iOS gives an App no access to the filesystem outside its
  own container, so on iOS the game files live under the App's `Documents`
  folder (any sub-folder, any depth).

Both platforms need a device with the memory a modern football game asks for:
the host reserves a 5 GiB guest address region at startup and a match runs with
roughly 2.8 GiB resident. Devices with 6 GB or more are the practical target.

## Game files you supply

Nothing in this repository is game data. You need your own copy of the game:

- a base `.xci` or `.nsp` dump of `01001C8016B4E000`,
- optionally the 1.0.3 update `.nsp`,
- your console's `prod.keys`.

**External resources (default).** The launcher asks for one folder. It scans the
folder and its sub-folders, identifies the base and the update by their contents,
checks them against the module IDs the App was built for, and reads the
containers in place — no extraction, no copy, no rename. The App and the IPA
carry no game container, no keys and no RomFS.

**Directory mode.** The RomFS is unpacked once and bundled into the App, which
then needs nothing else. Artifacts are much larger and the game version is
frozen at build time. Use it when you want a self-contained App.

## Build

Requirements: Apple silicon Mac, Xcode 26 (Metal toolchain, `swiftc`, `iconutil`),
.NET 10, `spirv-cross`, `xcodegen` for iOS, and a Python 3 with `capstone`,
`lz4`, `fontTools` and `pycryptodome` (the rewriter and the EASF tools use them).

```sh
./scripts/build-mac.sh --nsp-dir "/path/to/your/fifa23-folder"
./scripts/build-ios.sh --nsp-dir "/path/to/your/fifa23-folder"
```

The folder holds the base container, the optional update and `prod.keys`; the
script identifies which is which. Artifacts land in `Release/` as
`Touchline23.app` and `Touchline23.ipa`.

Both scripts run the same stages, and each can reuse what an earlier run made:

| Stage | Option to skip it |
| --- | --- |
| ExeFS and control data (`nx_extract`, program only) | `--exefs <ExeFS folder>` |
| Rewritten `main` and `sdk` (`dm/tools/patch_nso.py`) | `--patched <build/patched>` |
| Metal Shader libraries (`dmsh_build.py`, macOS and iOS) | `--shaders <dir with b-a885c56c665a>`, `--ios-shaders <same for iOS>` |
| Prepared EASF package | `--shader-pack <pkg>` |

`--work` names the work directory (default `build/work`), `--out` the artifact,
`--app-name`, `--version`, `--language`, `--show-fps` and `--icon` change what
the launcher shows. `./scripts/build-mac.sh --help` lists everything.

A Shader library is only accepted when its `inputs.tsv` names this profile's
inputs, so a library from another game, another profile revision or another
chain version is refused rather than silently linked. Building the 520
libraries from scratch takes a long time; a second build reuses the first.

### The packaging GUI

`scripts/build_packaging_gui.py --output <dir>` builds **Touchline 23
Packaging**, a SwiftUI App that does the same work with clicks: choose the game
folder, check the configuration, watch the log, collect the App or the IPA. It
carries its own Python, the reader, the extractor and the profile, so it can be
moved anywhere. See [the guide](docs/packaging-gui.md).

## What has been verified

Records are kept per feature; a Mac check is not an iPhone check and an IPA
audit is not gameplay. Details and their evidence are in
[compatibility](docs/fifa23/compatibility.md) and
[validation](docs/fifa23/validation.md).

| Feature | State |
| --- | --- |
| Native boot into the menus and into a match | Works, Mac and iPhone |
| Handheld and docked | Both reported working |
| Players, pitch, stadium, lighting, crowd | Render normally in the tested scenes |
| Match sound, crowd, commentary | Works, Mac and iPhone |
| Player indicator, 2D / 3D Radar | Works |
| Saves | Work; a match resumes from a save |
| iOS touch controls and gamepad | Work |
| Dynamic player shadows | Fixed; formal-match projections captured on Mac |
| Sideline staff (photographers, security, flag carriers) | Visible in the observed scenes |

## Known issues and limits

- Venue, weather, special-scene and long-session coverage is incomplete, and
  iPad play has no separate record yet.
- iOS physical memory is its own limit: the 5 GiB address reservation is not a
  promise about jetsam. A build signed without the Increased Memory Limit
  entitlement can still be killed in heavy scenes.
- Frame times in the recorded samples approach 60 fps with occasional long
  frames; no stable-60-fps claim is made.
- Loading screens can under-run audio, and a few diagnostic service calls are
  still unimplemented (the log shows `[RED]` lines for them).
- Online features, amiibo, and the Switch's own network services are outside
  what this port provides.
- The IPA is unsigned; signing and installation are the user's step.

## Layout

| Path | Purpose |
| --- | --- |
| `dm/host/` | The host: kernel services, NVN → Metal, audio, filesystem, input |
| `dm/gfx/` | Shader translation chain and its tools (`dmsh_*`) |
| `dm/games/01001C8016B4E000/` | The game profile: constants, shader tables, build rows |
| `dm/tools/` | Rewriter, extractor, profile helpers |
| `dm/macos/`, `dm/ios/`, `dm/apple/` | Launchers, platform glue and the iOS project |
| `gui/`, `tools/packaging_gui/` | The packaging App and the engine behind it |
| `scripts/` | The commands a user runs |
| `docs/` | Guides, the port's notes and the validation records |

## Tests

```sh
python3 -m unittest discover -s scripts/tests            # build scripts, packaging, profiles
make -C dm/host/tests GAME=01001C8016B4E000 run          # host units on this Mac
python3 -m unittest discover -s dm/resource/tests        # the container reader
DM_GAME=01001C8016B4E000 python3 -m unittest discover -s dm/gfx/tests
cd gui && swift test                                      # the packaging App's model
```

The Python suites run without game files. Building a real App or IPA is a
separate step, and only running it on a device says whether the game plays.

## License

MIT, see [LICENSE](LICENSE). nxnative and its contributors keep their
authorship; third-party notices are in `dm/third_party/`. This repository
distributes no game code, game data, keys, fonts, artwork or built Shader
libraries. The App icon is drawn by `assets/app-icon/make_icon.swift`.
