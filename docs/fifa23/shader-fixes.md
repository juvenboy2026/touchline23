# Shader extraction, lighting and indirect pointers

The EA archives contain NXSHADER `.fxo` programs. A headerless compute program's
instruction area does not necessarily begin immediately after its control section:
a constant block can lie between them. `easf/fxo.py` uses the control section's
code-offset field at `+0x6f0`. The earlier offset truncated an environment-light
prefilter program, changing its lookup hash and leaving the game's dispatch
without a mapped compute shader. Restoring that program restored player lighting.

`easf/prepare.py` writes ordinary nxnative packages, hash maps, compute query facts
and vertex/pixel pairing tables. It accepts local decoded BIG4 or chunkzip archives,
and EASF files with automatic NSO key discovery or an optional private key file.
No key is embedded. EASF
plaintext is checked against the container digest before decompression. The normal
`dmsh_build.py` consumes these packages; no historical MSL overlay is required.

## Runtime vertex/pixel pairing

EA's engine combines one-stage FXO programs per draw, across archive files: the
vertex of `combiner.fxo` was observed bound with the pixel shaders of `glares.fxo`
and `hair_strand.fxo`, the vertex of `vbeams.fxo` with `hair_strand.fxo`'s pixel,
and more such pairs kept appearing the longer the game ran. The archive files' own
vertex/pixel co-residence covers only part of the matrix, and every pairing the
table missed failed Metal pipeline validation ("Fragment input(s) user(locnN) … not
written by vertex shader"): the host then drops those draws, which blacked out
whole stands for a moment during the pre-match entrance and the post-match review
on both the iPhone and the Mac.

The fix follows the single-stage sources of `shader_split.py` (`separable_pairs`):
`prepare.py` now also pairs every vertex shader with a pixel *cover* — the fewest
pixel shaders whose SPH input-map locations (words 6–13) together cover all pixel
inputs; for FIFA one pixel shader already reads all of locn0–7 (all `float4`, the
union measured across 364 pixel shaders). `dmsh_build.py`'s `vs_pad` then gives
every vertex the missing outputs as `(0,0,0,1)` — the hardware value of an unwritten
Maxwell attribute slot, the same semantics `vs_init` and Ryujinx's stage linking
use — so any runtime pairing links. 182 of 187 vertices gained pads (the rest
already write every location); chain `7f2ec952af18` in that historical capture. The current source chain is read from `dm/gfx/nvn/dmsh_chain.h`. Observed pairings may still be
recorded as evidence in `shader_pairs_extra.tsv`, which `prepare.py` merges into
`shader_pairs.tsv` (the extra rows survive regeneration). On the Mac the same
entrance-and-match replay that failed 36 pipelines in 1200 s (and still 10 after
adding the first ten observed pairs) ran the full 1500 s with zero pipeline
failures and normally coloured crowds.

## Indirect pointers

For the shadow path, the bundled Ryujinx GlobalToStorage pass can lose an indirect
address loaded from storage rather than a traceable constant-buffer base. The
recognized generated helper then returns zero. Bone matrices read through it
collapse and the projected player shadow mask stays empty.

`dmsh_ptrfix.py` retains the previously verified workaround: rewrite this vertex
helper to reconstruct the 64-bit GPU address, subtract the runtime backing-pool
base, check the readable extent, and read that buffer on the GPU. CPU inspection
cannot substitute for this read because the game may populate pointers on the GPU.
The follow-up correction records the storage register, pool pointer slot (12) and
parameter slot (13). The runtime binds the complete backing pool for indirect
reads while ordinary storage reads retain their instance-data origin. This also
permits valid bone targets before an interior binding; sharing a backing buffer
does not imply a forward offset. The source rule participates in chain/cache
fingerprints, and vertex-input variants inherit it. See the
[follow-up evidence](shadow-investigation.md) for proof and remaining limits.

This migration does not rewrite GlobalToStorage.cs. The workaround has a bounded
single-backing-buffer assumption and conservative 2 GiB offset cap; unresolved
forms still require analysis.
It preserves demonstrated shadow rendering, **not a guarantee of stable shadows**.
The interior-origin rejection has a verified correction; other faint-shadow
observations and broad scene coverage remain limited as recorded in the follow-up.

The [shadow investigation](shadow-investigation.md) records GPU tests and the
same-process control. The stage-interface fix above addresses the separate crowd
black-flash failure; current scene coverage is in [compatibility](compatibility.md).
