# FIFA profile and shared configuration format

Touchline 23 ships exactly one profile:
[`01001C8016B4E000/game.tsv`](01001C8016B4E000/game.tsv), for FIFA 23 Legacy
Edition. No other profile is supported by this product. Tools use `DM_GAME` or
`GAME`; the single-game wrappers set them. Without a profile, generic tools stop
and list available entries rather than choosing a default.

## Current profile

| Area | FIFA 23 configuration |
| --- | --- |
| Identity | title/program `01001C8016B4E000`; name FIFA 23 Legacy Edition |
| App | Touchline 23, Touchline23.ipa, `com.ohxiaoguang.touchline23` |
| Builds | 1.0.0 / v0 and 1.0.3 / v196608, each with exact main/sdk build IDs |
| Packaging / Shader source | package v196608; Shader source v0 |
| Modules / marker | main and sdk; RomFS marker data3.big |
| Memory | 5 GiB reservation, 1.5 GiB alias; exact sizes in game.tsv |
| Shader archives | archive_format easf; datax.big with shader.big and shaderboot.big members |
| Graphics | NVN (default), tex_dyn_slots on; Direct/indirect rules in the normal chain |
| Frame step | No fps_target or frame-step rewriter patch; no 30/60-FPS launcher setting |

The registered base build supplies Shader provenance; detailed gameplay evidence
primarily concerns update 1.0.3. Build IDs are evidence gates, not interchangeable
version labels. See [compatibility](../../docs/fifa23/compatibility.md).

## Profile files and consumers

`game.tsv` uses `key<TAB>value` rows. Shader metadata lives alongside it:
`shader_map.tsv`, `shader_facts.tsv`, `shader_pairs.tsv`, `bf_want.tsv` and the
prewarm `pso_manifest.tsv`. An optional `shader_facts_manual.tsv` can override
query facts where binary analysis alone is insufficient. Those inputs affect
per-shader cache keys and the library input stamp, not the global chain version.

Optional `patches.py` defines CUTS, OBS and FRAME_STEP by exact NSO build ID;
Nintendo SDK cuts belong in `dm/tools/sdk_patches.py`. This game's registered
modules require no such cuts, so it has no patches.py and the SDK table is empty.
Never copy addresses to a new build without function mapping and disassembly.

Generated `c1_full.tsv` and `cb_extent.tsv` are ignored. A full Mac library build
makes them and ties them to its chain/input stamp; the host accepts only matching
tables. The global chain header remains `dm/gfx/nvn/dmsh_chain.h`.

| Consumer | Selection / purpose |
| --- | --- |
| Shader tools | DM_GAME; source tables, query facts and shader keys |
| Host / native tests | GAME; generated game_profile.h from game.py |
| iOS/macOS packers | App metadata, modules, marker, tables and platform libraries |
| Packaging GUI / engine | Container Title ID and build IDs, not the displayed name |
| settings.py | Profile/build conditions and NACP languages -> launcher.json |

Query with `python3 dm/games/game.py list` or
`python3 dm/games/game.py 01001C8016B4E000 <key>`. Launcher settings are described
once in `settings.tsv`. FPS or render-scale rows appear only if their profile/
rewriter conditions hold; generic schema entries are not automatically FIFA controls.

## Shared field reference

The engine retains the fields below for compatibility and maintenance. A field's
presence here does not mean FIFA sets it, that an external profile is supported,
or that enabling it is a recommended experiment. Per-game values belong in the
profile; SDK/import-derived defaults remain general rules in code.

| Key | Meaning |
| --- | --- |
| `title_id`, `program_id` | Application identity and the program ID reported to the guest |
| `name` | Profile/diagnostic label; control data can provide game display metadata |
| `app_name`, `bundle_id`, `ipa`, `app_category` | Independent product display name, bundle identity, IPA filename and category; explicit build overrides take precedence |
| `build <ver> <display> <module>=<build ID>…` | Registered module identities; unknown builds need a separately derived profile, not old fixed-address rules |
| `package`, `shader_versions` | Preferred package version and versions supplying the union of Shader inputs |
| `modules`, `romfs_marker`, `zip_store` | Rewrite/load order, required RomFS path and IPA storage extensions |
| `graphics_api` | nvn (default), vulkan or gl; available packaging/audit paths are checked separately |
| `archive_format` | nvn, easf or glsl source-provider format; FIFA uses easf |
| `archive_container`, `archive_member` | Container and repeatable member paths for archive preparation |
| `mem_reserve`, `mem_alias`, `mem_stack`, `app_pool` | Guest address-space partition and application pool |
| `mem_used` | Non-heap used-memory answer; heap checks also consider actual loaded module size |
| `sys_resource` | NPDM system-resource answer, affecting SDK memory initialization |
| `game_args`, `game_env` | Default guest arguments and environment values; host command/environment overrides remain explicit |
| `mem_map_limit` | Optional application-pool limit for MapPhysicalMemory |
| `present_interval` | game: respect requested vsync interval; display: pace by display ticks; requires appropriate game-time semantics |
| `fps_target` | Optional build-specific frame-step or engine frame-limit integration; 0 leaves game timing alone. Requires a verified implementation, not just a numeric setting |
| `fps_hold` | With a supported fps_target, allow adaptive multi-vsync holds; DM_FPS_HOLD overrides |
| `core_preempt` | Optional bounded approximation of Horizon same-core priority preemption; DM_PREEMPT overrides |
| `alloc_big_align` | Optional 64 KiB alignment of large StandardAllocator allocations |
| `shared_font` | Optional ttf/bfttf override; otherwise SDK version and imports select the ABI |
| `device_api` | Optional NVN API major.minor override; otherwise SDK-derived; DM_NVN_API overrides |
| `op_mode`, `perf_mode`, `pad_layout` | Initial operation/performance mode and controller layout |
| `feedback_snap` | Feedback-loop texture snapshot handling in replay |
| `alpha_from_red` | Treat single-channel texture data as alpha for applicable format semantics |
| `tex_flush_upload` | Refresh CPU-written texture contents at NVN flush boundaries |
| `tex_dirty_upload` | With flush-upload handling, detect additional CPU writes without explicit flush |
| `render_cond` | Evaluate recorded conditional render/clear operations |
| `tex_dyn_slots` | Bind dynamic texture/sampler fallback tables for compatible handle layouts; not part of the global chain fingerprint |
| `gpu_timestamps` | submission completion or per-segment GPU timing; DM_NVN_GPU_TS overrides |
| `vconv_range` | Bound CPU vertex conversion to the direct draw's proven range; indirect/GPU-written cases retain conservative ranges |
| `shader_groups`, `shader_note` | Source grouping and map annotation |

The inherited format also supports `vk_capture.tsv` and `gl_capture.tsv`, but this
profile needs neither. The source survey can identify API imports, GLSLC outputs,
archive providers and runtime-capture requirements. These are general engineering
facilities, not a multi-game feature in Touchline 23.

NVN driver tables and Metal slot planning are described in the
[graphics guide](../gfx/README.md#shared-binding-and-cache-mechanisms). EASF source
preparation and matching-cache rules are in the [build guide](../../docs/fifa23/build.md).
Do not add another game's profile as part of ordinary maintenance.
