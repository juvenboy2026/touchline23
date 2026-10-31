# 01 — FIFA 23 containers and extraction

Use the project's reader/extractor with your own files. Keep originals, keys,
extractions and analysis on the game drive, outside Git and the home directory.
The current profile is `01001C8016B4E000`, base v0 and update v196608. The
[build wrappers](../fifa23/build.md) and [packaging tool](../packaging-gui.md)
perform the ordinary preparation; manual extraction is a development operation.

## Private inputs

Provide your own base XCI/NSP, optional update NSP and prod.keys by file path.
The extractor imports common ticket material where present; do not print key
values or place key bytes in a command line, source file or public manifest.
Malformed/mismatched key files should receive a diagnostic; preserve the original
and do not silently edit them to make a hash failure disappear.

## XCI / NSP / NCA / NSO

| Layer | Meaning and handling |
| --- | --- |
| NSP | PFS0 container with content NCAs, metadata and sometimes tickets/certificates |
| XCI | Gamecard image with HEAD header and HFS0 partitions; the reader opens the secure content view without copying the whole image |
| Program NCA | Contains ExeFS and RomFS; base/update sections must be layered and integrity checked |
| Control NCA | NACP display version/languages and optional control image, kept private |
| ExeFS | main.npdm, program NSOs and SDK modules; FIFA loads/rewrites main and sdk |
| RomFS | Filesystem of game data, read externally or prepared for Directory mode |
| NSO | Executable segment container with build identity, compression flags and optional hashes |

The repository's `dm/tools/nx_extract` uses LibHac. Once built:

```sh
"$NX_EXTRACT" "$PROD_KEYS" "$BASE_CONTAINER" "$UPDATE_NSP" "$EXTRACT_OUT" --program-only
```

Use `-` for an absent update. `--program-only` avoids full RomFS extraction;
`--manifest` supports an external view for build tools. For a full Directory-mode
extraction, omit the program-only flag. Read the tool's usage and the build guide
before changing preparation modes; preserve base/update version identities.

A patch NCA must be applied over the matching base. Never pair update RomFS with
base main/sdk, and do not trust filenames as identity. The extractor and the
launcher verify Title ID, control version and module Build IDs. Container corruption
or a hash mismatch is not a key to suppress validation. Any explicit damaged-input
mode is a forensic facility, not a normal build recipe or a valid publication input.

## FIFA archive inputs

The game stores the EASF Shader archives as BIG4 members of datax.big. The dedicated
EASF path can range-read those members from the external container; a full game
extraction is unnecessary for an external build. Automatic key discovery uses the
user's own main module and validates the archive data; no key is supplied here.
See [Shader preparation](../fifa23/build.md#inputs-and-source-build).

## NSO analysis and build gates

`dm/tools/nsoseg.py` is the shared segment reader used by analysis and rewriting.
It validates headers/bounds and handles raw, LZ4 and the retained ZBIC variant.
ZBIC support is generic infrastructure, not a claim that the registered FIFA
builds need it. Its original BSD license and Atmosphere/zstd attribution remain
in dm/tools/zbic; the decoder is compiled on first relevant use and cached.

Use `dm/tools/nso.py` to produce an analysis image and `nso2elf.py` for an ELF.
Those outputs are private. If a new module build appears, use nso_fnmap.py to map
functions/globals from the old build and verify candidates by disassembly. All
cuts, observation gates and fixed addresses must stay behind exact build-ID gates.
The registered FIFA builds currently need no profile or SDK rewriter cuts.

## Workspace and diagnostics

```text
<game drive>/<private work>/
  extracted/v0/ExeFS/       base program and control data
  extracted/v196608/ExeFS/  matching update program and control data
  analysis/                decompressed images, ELF, surveys, disassembly
  patched/                 rewritten modules and rewriter metadata
  shaders/                 generated source/libraries and private manifests
  runs/                    copied saves, logs, captures and control files
```

This is a suggested private layout, not mandatory names. Existing prepared inputs
can be reused through --exefs, --patched, --shaders and --ios-shaders. Never rerun
all Shader compilation merely to inspect metadata. Other archive readers retained
in the engine are general tools, not other games supported by this project.
