# Graphics: FIFA 23 NVN to Metal

Touchline 23 supports one game: Nintendo Switch FIFA 23 Legacy Edition. Its
current path is **NVN -> Metal**, with EA EASF archives as offline Shader input.
This page describes that path and the useful shared engine mechanisms; retained
GL/Vulkan tools and historical tests do not add other supported games.
See the [build guide](../../docs/fifa23/build.md), [compatibility](../../docs/fifa23/compatibility.md)
and [project attribution](../../docs/UPSTREAM.md).

## Recording and replay

The game imports `nvnBootstrapLoader` and obtains the remaining NVN calls by name.
`nvn/hle_nvn.c` implements host objects and records commands; thunks and prototype
checks preserve the guest calling convention. Unknown calls report `[RED]`.
`nvn/nvn_mtl.m` replays the command stream into Metal at submission time.

Memory pools use unified CPU/GPU memory. Sync events and completion become visible
after GPU completion, not merely command encoding. Pipeline/depth-state caches,
background warm-up and presentation pacing reduce repeated work; a first-use
pipeline can still stall. Tegra block-linear textures are deswizzled for Metal.
[Object mapping](nvn_metal_mapping.md) and [texture formats](tex/README.md) give the
shared implementation details.

## FIFA Shader preparation and translation

The base game contains 386 NXSHADER programs in `shader.big` and `shaderboot.big`,
BIG4 members of the RomFS `datax.big` container. `scripts/build_fifa23.py` prepares
the EASF inputs using the user's own game and key source; keys and generated
payloads remain private. The registered update adds no Shader. The resulting
520 libraries per platform include the base programs and required generated variants.

```text
EA EASF/BIG4 inputs from the user's game
  -> scripts/build_fifa23.py / dm/gfx/tools/easf
  -> NXSHADER package and profile metadata
  -> locked dmsh_xlate (Ryujinx / Spv.Generator): SPIR-V
  -> SPIRV-Cross: Metal Shading Language
  -> Apple metal / metallib: macOS and iOS libraries
```

Translation is offline, not a runtime shader compiler on the phone. The FIFA
wrappers and packaging GUI use the dedicated EASF provider; the generic NSP
shader scanner alone is not a replacement for it. [Shader fixes](../../docs/fifa23/shader-fixes.md)
describes corrected compute layout, Direct descriptors, readable tiles and runtime
vertex/pixel pairing. [Shadow investigation](../../docs/fifa23/shadow-investigation.md)
records the indirect-read pool-window correction and its limits.

| File / output | Role |
| --- | --- |
| `dm/games/01001C8016B4E000/shader_map.tsv` | Hash/stage and package-index metadata; no program payload |
| `shader_facts.tsv`, `shader_pairs.tsv`, `bf_want.tsv` | Translation queries, stage interfaces and requested variants |
| `<key>_b.metallib` / `<key>_b.json` | Platform library and reflection used by the host |
| Variant metallibs/reflection | Readable-tile and vertex-input alternatives when required |
| Generated MSL / build reports | Private build outputs, never committed |
| `c1_full.tsv`, `cb_extent.tsv` | Locally generated uniform/extent tables tied to the library stamp |

The runtime and offline tools derive keys from shader control/code bytes. The
current global chain is `a885c56c665a`, declared in `nvn/dmsh_chain.h`. Its lock
fingerprints the translator and external tools. Per-profile inputs are separate:
their digest is written to `b-<chain>/inputs.tsv` and included in cache keys.
A profile-input change does not by itself redefine the global chain.

Keep the host, reflection, runtime tables and platform libraries consistent.
`dmsh_chain.py --header` follows a deliberate chain-tool change, then both platform
libraries and the host must be rebuilt. Documentation/UI edits require none of
that. A fresh dotnet publish is not the locked translator. Reuse existing libraries
through `--shaders` and `--ios-shaders` when stamps match.

## Shared binding and cache mechanisms

These are implementation details, not extra FIFA feature claims:

- Uniform slot r maps to constant section `c[3+r]`.
- NVN c2 contains combined handles at `0x20+8r`, images at `0x120+8r`, separate
  textures at `0x168+8r` and samplers at `0x568+8r`.
- Storage-buffer descriptors are in c0, with per-stage bases documented in the
  translator and reflection code. `dmsh_slots.py` plans Metal buffer indices;
  replay consumes the reflection instead of guessing bindings.
- The seed `pso_manifest.tsv` and per-device `pso_user.tsv` describe pipeline
  settings by shader key. A recorded pipeline does not prove a new scene correct.
- `nvn_builtin.h` retains inherited authored MSL helpers and their upstream
  provenance; it is not evidence that FIFA embeds or exercises every helper.
- GL/Vulkan adapters, archive readers for other formats and synthetic tests remain
  general engine infrastructure. This distribution has no profile for those paths.

## Implementation map

| Path | Purpose |
| --- | --- |
| `nvn/hle_nvn.c`, `nvn/nvn_obj.h` | NVN interface, host object layouts and command format |
| `nvn/nvn_mtl.m` | Metal replay, memory/texture binding, pipelines and presentation |
| `nvn/nvn_refl.m` | Parsed reflection and runtime binding metadata |
| `nvn/nvn_tex.c`, `nvn/nvn_dirty.c` | Layout sizes and dirty-page tracking |
| `tex/` | Formats, deswizzling and BC decompression |
| `tools/dmsh_xlate/`, `tools/dmsh_xlate_bin/` | Source and retained locked translator |
| `tools/dmsh_build.py`, `tools/dmsh_chain.py` | Library generation, stamps and global chain checks |
| `tools/dmsh_fetch.py`, `tools/dmsh_slots.py` | Readable-tile generation and Metal binding planning |
| `tools/c1_guard.py`, `tools/cb_extent.py` | Generated runtime tables |
| `tests/`, `metal/` | Local tests and standalone offscreen tools, not game assets |

## Local checks and diagnostics

```sh
DM_GAME=01001C8016B4E000 python3 dm/gfx/tools/dmsh_chain.py --check-tools
make -C dm/gfx/tests GAME=01001C8016B4E000 <selected-test-target>
```

Use the [regression guide](../../docs/fifa23/build.md#regression-checks) to select
fixture-independent checks, reflection tests with the actual library and tests
requiring a local Metal device. Some legacy tests need fixtures from other games;
missing fixtures are not a FIFA failure or a passing suite. Test the selected
change instead of recompiling all 520 libraries unnecessarily.

[Debugging](../../docs/agents/05-debugging.md) describes isolated runs, pass dumps,
GPU-completed readback and performance controls. Useful switches include
`DM_NVN_TSV`, `DM_NVN_PASSDUMP`, `DM_NVN_PASSGPU`, `DM_NVN_SHOT`,
`DM_NVN_TEXDUMP`, `DM_NVN_FUSE_CHECK`, `DM_PSO_RECORD` and `DM_PSO_MANIFEST`.
`DM_MSL_DIR` names the library parent and `DM_NVN_SHMAP` the profile map.
Put diagnostics on the game drive, never in published source.

Pass-elision, bindless, timestamp and frame-step controls are general mechanisms;
not every option is appropriate for this profile. In particular, shared pacing
variables do not establish a validated FIFA 30/60-FPS patch. Known rendering,
scene-coverage and memory limits are recorded in the FIFA compatibility pages,
not inferred from the original engine's support for other titles.
