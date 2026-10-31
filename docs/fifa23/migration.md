# Historical FIFA integration record

This page records work predating the independent Touchline 23 public history.
The source IDs below belong to the earlier development line and are retained
as historical evidence, not as Git ranges to run in this repository. Current
development starts from this repository's `main`; see [project origin](../UPSTREAM.md)
and the [build guide](build.md).

The previous implementation used baseline
`51a3fb444287bd304629a497b2115f5c2146dd70`. This fork integrated its compatibility
work onto upstream baseline `2f69480260068c0979ee42a1c31b420eecfd27e2`, preserving
newer games, renderer threading, integer pixel outputs and launcher/packaging
changes. Integration used a three-way content merge rather than replacing the
current source tree.

| Source area | Integrated behavior |
| --- | --- |
| `dm/host/hle_audio.c` | AudioUnit host-stack lifecycle, six-channel stereo downmix and missing-consumer recovery |
| `dm/host/hle_oe.c` | Crash-report switches consistent with the absent applet backend |
| `dm/gfx/tools/easf/` | EA archive parsing, corrected compute offset and ordinary package/query export |
| `dmsh_ptrfix.py`, build/reflection/runtime | Bounded indirect vertex reads with reflected backing-pool base/extent |
| `dmsh_bindless.py`, build/reflection/runtime | Descriptor-pool arrays, argument extents and compatible texture views |
| FIFA profile | Identity, build IDs, memory layout and shader metadata |
| Build/run helpers and host Makefile | External outputs, original-NSO rewriting and isolated copied-save runs |

Later corrections add the full-pool pointer window, 5 GiB iOS layout and runtime
FXO stage-interface closure. Their mechanisms and evidence live in the technical
documents rather than a migration timeline. These technical decisions are now maintained in Touchline 23. For the independent
repository's changes use `git log --oneline main` or compare explicitly available
local commits; do not use a baseline from the older source line as a local range.

## Integration boundaries

The production path uses reflection and the normal shader chain. Legacy host
executables, manual overlay generators, copied translator outputs, test-only HUD
adapters, diagnostic dumps and embedded-key decryptors are not build inputs.
The EASF reader accepts private key input and supplies no key values.

Repeated builds exposed an interaction between `fs_uint` and readable-tile
variants: cached MSL includes an appended integer entry, while cold variant
generation used only the primary entry. `dmsh_fetch.py` excludes that appended
entry from tile rewriting; a synthetic test checks cold/cache parity. This is a
general build fix rather than a per-game shader substitution.

Shared graphics/audio findings do not certify the original engine's entire game list;
Touchline 23 supports only its FIFA profile. FIFA external XCI/NSP loading is now connected by
the dedicated EASF image/preparation path and GUI cache-reuse recipe. The generic
NSP Shader scanner still does not replace that adapter. Both platform/resource
recipes have scoped build/audit records; see the [GUI guide](../packaging-gui.md).
The source commit this tree was taken from is recorded in
[the upstream record](../UPSTREAM.md); the older migration baselines above retain
their historical meaning.

## Source and third-party attribution

Archive readers, compatibility rules and host changes originate in the previous
local implementation. The new EASF path implements the format using
pycryptodome's AES API; no FIFA-Mods source or embedded keys were copied. Raw
research and unknown-origin artifacts remain private. No game program or directly
converted game shader source is included.

Bundled Ryujinx 1.3.2 sources and locked translator retain their existing MIT
notices in `dm/third_party/ryujinx/LICENSE.txt`, alongside Spv.Generator's license.
No C# translator change was migrated. Historical Ryujinx references in the
[HUD notes](bindless-hud-fix.md) are research references, not newly vendored code.
SPIRV-Cross remains an external tool with its upstream license. See the
[third-party inventory](../../dm/third_party/README.md).

Profile hash maps, query sizes, pairing evidence and buffer proofs are
compatibility metadata: they contain no program bytes, constant blobs,
disassembly, MSL or metallibs. Keep that boundary in future publication reviews.
Existing upstream authorship, copyright notices and acknowledgements are retained.
