# Touchline 23 Packaging

[简体中文](packaging-gui.zh-CN.md) · [README](../README.md) · [Launcher and UI record](launcher-and-packaging-ui.md)

`scripts/build_packaging_gui.py --output <dir>` builds
**Touchline23Packaging.app**. It does with clicks what `scripts/build-mac.sh` and
`scripts/build-ios.sh` do with arguments: pick the game folder, check it, build
the App or the IPA, and keep the log.

The App may be moved outside the source checkout; it finds its own resources
through its bundle. It contains the SwiftUI executable, a relocatable CPython
runtime and build modules, capstone, LZ4, fontTools, pycryptodome, the Zstandard
backport, the game profile and its index, the native read-only reader, the
program extractor, the locked Shader translator and the sources the game host is
built from. No checkout, virtual environment or manual ExeFS/reader choice is
needed. The bundle is read-only input; generated data goes elsewhere.

The interface language follows the system (English / Simplified Chinese, English
fallback) and the choice persists. The launchers share the same catalog.

## Requirements

Apple silicon, macOS 26+, Xcode with the Metal toolchain, .NET 10, SPIRV-Cross
and, for iOS, XcodeGen. Settings shows whether these are present and offers a
refresh; a missing tool is reported when a build actually needs it. The App is
ad-hoc signed without notarization. IPAs are unsigned: signing and sideloading
are the user's step.

## Packaging

1. Choose the folder holding the base game (XCI or NSP), the optional 1.0.3
   update and `prod.keys`. An explicit base path can be entered instead.
2. Select macOS App, iOS IPA, or both. External resources are the default;
   Directory mode extracts and bundles the RomFS and needs considerably more
   space.
3. Output defaults to the game folder and follows a base-file change until you
   choose a location yourself; **Restore default output** resumes that.
4. **Check configuration** reads the container's title ID, extracts the ExeFS and
   the control data (program only, external mode never copies an image or the
   RomFS), and verifies every module Build ID and the display version against the
   profile.
5. **Build…** opens the confirmation sheet: game, version, targets, resource
   mode, Shader status and output folder, with **Technical Details** collapsed.
   **Start Packaging** runs the same engine, packers, artifact audits and
   publication checks the command-line scripts use. Targets run in order; a
   failure or a cancel stops the batch.

**Supported Games…** lists the bundled profile — there is one, FIFA 23 Legacy
Edition — with its Title ID and registered versions, searchable by name, Title ID
or version. Listing a profile does not certify a cold Shader build or a device
run; the actual build checks do that.

## Shaders and caches

Cache root: `~/Library/Caches/Touchline23Packaging/`, changeable in **Settings
and diagnostics** (an external SSD is fine). Switching roots does not move or
delete earlier data. Managed data lives under
`Touchline23Packaging-v1/{programs,shaders,tasks}` with ownership markers;
cleanup only touches that namespace.

The cache identity is the game, the registered Shader source versions, the global
chain and the profile input digest, plus each target's SDK reflections and
libraries. Changing the output location does not recompile Shaders. An
incompatible cache is kept with a diagnostic and a new entry is generated; tables
and stamps are never patched to pass validation.

Without a valid cache the real generation stage runs: the profile's EASF source
preparation (automatic key discovery, ranged reads of the BIG4 members), then
`dmsh_build.py`, then the runtime tables, then validation of both platforms, and
finally an atomic cache entry. Generated tables must be byte-identical to the
registered ones. **Measure cache** reports owned bytes; **Clear cache…** measures
again, asks for confirmation, refuses a changed measurement or an active lease,
never follows symbolic links out of the tree and leaves games, keys, saves and
artifacts alone.

## Outputs and cleanup

Only audited `.app` / `.ipa` files enter the output folder; an existing name gets
a numbered suffix and publication verifies the bytes before the final name
appears. Tasks, extracted code, intermediates and DerivedData stay on the cache
disk; success removes the work, failure keeps small redacted diagnostics unless
you choose otherwise. Logs and history: `~/Library/Logs/Touchline23Packaging`.

FIFA 23's Switch release ships no add-on content, and external-mode artifacts
carry none in any case: after installing, a DLC NSP dropped into the game folder
is verified and mounted as its own read-only filesystem by the host, never
overlaid onto the base RomFS. Loose NSO/NRO executables inside such a container
are reported as needing module collection and rewriting; a container that needs
new Shaders still needs matching libraries, not a certificate. Compressed NSZ
must be converted to NSP first.

Unknown versions, a control version that contradicts the code ID, unsupported
graphics audits, missing sources, invalid caches and dependency failures stop
packaging with a reason. This profile is NVN; the engine's GL and Vulkan paths
exist but no profile here uses them.

## Building the App from source

For a redistributor, not for an end user:

```sh
/path/to/build-python scripts/build_packaging_gui.py \
  --output /path/to/new/gui-build \
  --python /path/to/relocatable-python-with-dependencies \
  --python-site /optional/additional/site-packages --test
```

Use a relocatable CPython standalone installation with `lib/libpython*.dylib`.
The builder selects the dependency packages it needs, preserves their licenses,
compiles the reader and the extractor, copies a curated build-source/profile/tool
payload, writes the index and the resource inventory, checks the copied Python
imports, builds and tests the Swift code, and ad-hoc signs the App. Git data,
tests, private inputs, old caches and build products are excluded. The build
machine needs the .NET SDK with its LibHac package. There is no DMG, updater or
release step.
