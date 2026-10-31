# Bindless handles, indicators and Radar

The control triangle and both Radar modes share a descriptor interpretation bug.
Their texture handles can originate in vertex input, travel through a flat varying
and reach the pixel shader without passing through an ordinary texture binding
slot. The low 20 bits identify a texture descriptor in a pool and the high 12 bits
a sampler descriptor. Treating them as indices into a 32-slot bound-texture array
loses the resources even though the game submitted the HUD draws.

`dmsh_bindless.py` recognizes Direct resource arrays in translated MSL, expands
texture and sampler capacities to 16,384 and 4,096, adjusts only the corresponding
index clamps, and shifts subsequent Metal argument IDs. Unknown layouts fail
explicitly. `dmsh_build.py` records `bindless_pool` in reflection; `nvn_refl.*`
retains this distinction and the larger argument extents. At replay, Direct arrays
resolve pool IDs relative to the currently bound texture/sampler pools and retain
real handles in the driver segment. Legacy reflection keeps the old slot semantics.
The host filters incompatible texture types before attempting to resolve views.
It retains legal view conversions, including layer-0 reads of a 2D array through
a 2D texture declaration; an exact-type-only filter incorrectly discarded those.

The same mechanism covers handles read from storage buffers. A later historical
selective rebuild used it to restore observed sideline staff textures. A complete
normal-chain rebuild applies the rule to all recognized Direct shaders, rather
than maintaining a list of four special pixel shaders.

The historical investigation checked Ryujinx PRs #6577 (Input handles), #6721
(StorageBuffer sources) and #6853 (additional source tracing). The bundled
BindlessElimination implementation already contains these source-tracing paths;
this patch does not replace the C# translator or copy Vulkan descriptor code into
Metal. Public historical commit references:

- [Input handles](https://git.axenov.dev/Museum/ryujinx/commit/c6f8bfed904e30f7c5d890a2f0ef531eb9e298e5)
- [Storage-buffer handles](https://git.axenov.dev/Museum/ryujinx/commit/3a3b51893ee272af49d762387da5b27743786d56)
- [Further tracing](https://git.axenov.dev/Museum/ryujinx/commit/c41fddd25e8ddd3cf0b3cefeaf6595d2e4ede0fa)

Mac gameplay captures verify the control indicator following player selection
and both Radar modes. The latest iPhone feedback confirms the same features.
Crowd stage-interface closure has its own mechanism in [shader fixes](shader-fixes.md);
one successful material sample alone does not certify every scene.

Full-pool arrays require additional binding work and may increase residency. Capacity, pool
switching, descriptor types, other Direct sources and other games need additional
coverage. Indirect GPU pointer reads and their remaining limits are documented in the
[shadow investigation](shadow-investigation.md).
