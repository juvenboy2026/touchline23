# Compatibility

Tested game: FIFA 23 Legacy Edition 1.0.3 (`01001C8016B4E000`). The profile also
identifies 1.0.0 for shader provenance; that is not equivalent gameplay coverage.
The current source chain is `a885c56c665a` (`dm/gfx/nvn/dmsh_chain.h`). Older chain IDs in captured experiments remain historical evidence; never relabel or reuse them as current libraries.

Mac results use a MacBook Air M1. iPhone results are user testing on an iPhone Air,
recorded in the latest branch status; Mac automated checks do not establish iOS
runtime behavior. See [validation](validation.md) for the evidence and its sources.

| Feature | Current evidence | Remaining coverage |
| --- | --- | --- |
| Native boot and formal matches | Mac source-host tests and iPhone user testing | First-launch reliability and long sessions |
| Handheld / docked | Both modes reported working in the latest status | Broader mode-switching scenarios |
| Players, pitch, stadium and lighting | Mac captures and iPhone feedback show normal rendering in tested scenes | More venues, weather and cameras |
| Crowd rendering | Runtime stage-interface defect fixed; Mac replay has zero failed pipelines and iPhone feedback reports normal crowds | Other venues and special scenes |
| Match sound, crowds and commentary | User-confirmed on Mac and iPhone | Other output devices and commentary languages |
| Red player indicator, 2D / 3D Radar | Mac gameplay captures and iPhone feedback | All gameplay modes and settings persistence paths |
| Saves | Working in latest user-tested status; Mac runs resume a copied tournament save | All save modes, reinstall and upgrade paths |
| iOS touch controls / gamepad | Working in latest iPhone feedback | Controller models and reconnect behavior |
| Dynamic player shadows | Full-pool indirect-read correction verified by Mac GPU tests and same-process control; formal-match projections captured | Uniform stability across scenes and detailed iPhone shadow comparison |
| Sideline staff | Photographers, security and flag carriers restored in observed Mac scenes | All staff and venues |

## Fixed failures

- **Black screen / exit after Play on iOS:** the former 8 GiB reservation failed
  before graphics initialization. The 5 GiB layout now enters matches on iPhone.
- **Crowd black flashes in entrance / review scenes:** missing vertex outputs for
  runtime FXO pairings caused Metal pipeline failures and dropped draws. Pixel
  cover and `vs_pad` close the interface; this is a fixed failure with limited
  scene coverage, not a current blanket claim that spectators remain black.
- **Lost player shadow geometry:** the old forward-only pointer window rejected
  legal targets before an instance binding. The full backing-pool window fixes
  this proven failure class; it does not explain every historical faint shadow.

Details are in [shader fixes](shader-fixes.md),
[shadow investigation](shadow-investigation.md) and [validation](validation.md).

## Known limits

- Venue, weather, special-scene and long-session coverage is incomplete; iPad
  gameplay has no separate verification record here.
- The 5 GiB guest address reservation and physical memory usage are separate.
  Signing without Increased Memory Limit can still encounter iOS jetsam limits;
  device play does not establish memory safety for every scene or device.
- Indirect reads assume one backing pool and retain a conservative 2 GiB offset
  cap. Unrecognized or cross-pool pointer forms need further analysis.
- Direct descriptor arrays are bounded to 16,384 textures and 4,096 samplers;
  pool switching, resource types and other games require further regression work.
- Historical frame samples approach 60 FPS with about 2.8 GiB footprint, but
  uncontrolled long frames and display drops prevent performance parity claims.
- Shared graphics/audio changes have not received full runtime regression testing
  across the upstream game list. General upstream limits still apply.
- Both external XCI/NSP and Directory FIFA recipes now have macOS/iOS real artifact and audit records. The GUI uses the FIFA EASF-prepared cache, not the generic NSP Shader scanner. That scanner limitation still matters to the generic pipeline; it is no longer a reason to call FIFA external mode unimplemented. See the [GUI guide](../packaging-gui.md).
