# Indirect GPU reads and dynamic shadows

The full-pool correction fixes a proven interior-origin rejection in indirect
vertex reads. Metal tests and a same-process control verify that failure class;
training and formal-match captures contain projected player silhouettes.
Uniform shadow stability across venues, weather, cameras and match periods is
not established. Current crowd status is tracked separately in
[compatibility](compatibility.md); the historical crowd failure does not invalidate
the pointer-window control.

## Root cause and completed-GPU evidence

The bundled Ryujinx GlobalToStorage pass can lose an indirect address loaded from
storage rather than a traceable constant-buffer base. The recognized generated
helper returns zero, collapsing bone transforms and shadow geometry.
`dmsh_ptrfix.py` reconstructs the 64-bit GPU address and performs bounded GPU
reads. CPU inspection cannot substitute because the game can write pointers on
the GPU.

A further defect existed in the workaround: it used the instance binding as the
start of a forward-only readable window. A formal-match sample of
`a1feb9dd02bc6e19` held 193 instances across nine captured bindings. Two draws,
with 12 and 16 instances, had valid bone pointers before their instance origin
but inside the same backing pool. Unsigned subtraction underflowed and the range
check rejected these legal reads. Sharing a buffer does not imply a positive
offset from an interior binding.

An opt-in replay probe copied storage bindings into independent buffers after
the render pass and waited for the submission fence. It captured at most 16
bindings of 32 KiB per requested frame. This distinguishes completed GPU data
from CPU encode-time or deferred-update bytes. Raw data stays outside Git.

## Implementation contract

- `dmsh_ptrfix.py` recognizes the unresolved helper and reflects a separate
  `pool_slot`: vertex slot 12 binds the complete backing pool; slot 13 holds its
  guest base and extent. Ordinary storage reads retain their instance origin.
- Every four-byte indirect read must fit inside that pool and the conservative
  2 GiB offset cap. Null, unmapped and out-of-range reads return zero. Cross-pool
  address resolution is not supplied.
- `nvn_mtl.m` reads the ptrfix reflection, binds the pool and uses immutable
  parameters keyed by base and extent. A vertex-conversion slot collision fails
  explicitly. Older reflection without `pool_slot` retains its earlier convention.
- Pending uniform writes anywhere in the indirect window must complete before
  the draw, including writes before the instance origin. The replay dependency
  check covers the pool window without adding an arbitrary delay.
- Source rules participate in chain/cache fingerprints and vertex-input variants.
  No change to GlobalToStorage.cs, CPU pointer pre-read, fabricated projection or
  game-specific position rule is required.

The correction's chain `fda6fe95693e` regenerated 520 libraries: 516 were
byte-identical to the prior chain and four changed (two ptrfix programs and their
vertex-input variants). The chain at that investigation stage, `7f2ec952af18`, also includes the
independent [stage-interface fix](shader-fixes.md#runtime-vertexpixel-pairing).
The pointer implementation is traceable to
[d7d7fae](https://github.com/ohxiaoguang/nxnative-zzg/commit/d7d7fae).

## Same-process control

`DM_NVN_PTRFIX_FORWARD_ONLY=1` emulates the old origin/extent while retaining the
same library, scene, weather and game process. A full-pool / forward-only /
full-pool sequence found 301 / 292 / 284 shadow instances with valid bone targets
before their bindings; none was null or outside its pool. Intermediate targets
contained recognizable projections, became empty with the old window, and
recovered with the full pool. The main mask retained static geometry during the
failed control. This proves geometry loss before compositing.

The pause background continues to animate, so these are not frozen-frame,
pixel-aligned comparisons; raw coverage counts are not quality scores. In moving
play, the old window sometimes retained projections because allocation layout
placed targets after the binding. This conditional behavior matches the defect
and prevents attributing every faint-shadow observation to it. Restore the
production full-pool setting after controls.

## Regression coverage and diagnostics

Six rule tests, fourteen Metal indirect-read checks and eight Metal replay
checks passed. They cover targets before/after an interior origin, endpoints,
underflow, null and partial out-of-bounds reads, pending writes inside/outside
the instance range, unrelated writes and base reuse with a changed extent.
Commands are in [build](build.md#regression-checks).

Corrected restarts reached training and formal play. Captures show silhouettes
in masks, intermediates and final colour targets, with indicator and Radar still
working. Training and match lighting differ; faint final projections do not by
themselves prove missing geometry. Detailed iPhone shadow comparisons and broad
scene stability remain open.

Texture serials are per-run observations, not stable compatibility IDs. Identify
the current main mask, intermediates and composition target from pass records
before using `DM_NVN_TEXDUMP_ONLY`. Uniform diagnostics distinguish pending bytes
from CPU physical bytes; neither replaces GPU completion. A bounded probe may
miss a shader when another matching program consumes its capture budget first.
