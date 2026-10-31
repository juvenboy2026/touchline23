# Research artifact index

This index maps private research topics to their maintained public explanation.
Raw reports, screenshots, saves, logs, dumps, programs and build artifacts remain
in the original external workspace. Private inventories and preservation hashes
are not published because they include sensitive paths and game-derived data.

| Research topic | Maintained public reference | Private evidence |
| --- | --- | --- |
| Survey and startup | [Compatibility](compatibility.md), [validation](validation.md) | Version surveys, resource and reservation diagnostics |
| Audio | [Audio lifecycle/downmix](audio-fix.md) | Stack analysis, PCM diagnostics and listening records |
| Extraction and lighting | [Shader fixes](shader-fixes.md) | EASF format analysis and compute-program comparisons |
| EASF key discovery | [Build](build.md#inputs-and-source-build) | Module registry analysis, digest-confirmed key fingerprints |
| Runtime stage pairing | [Shader fixes](shader-fixes.md#runtime-vertexpixel-pairing) | Pipeline errors and entrance/review captures |
| Player shadows | [Shadow investigation](shadow-investigation.md) | GPU-completed storage reads, masks and same-process controls |
| HUD and sideline materials | [Resource binding](bindless-hud-fix.md) | Handle tracing, reference patches and match captures |
| Build provenance | [Build](build.md), [migration](migration.md) | Input hashes, manifests, package checks and original source comparisons |

Historical weak-shadow and black-crowd samples remain valid failure evidence.
Later fixes supersede their status, not the fact that the failures occurred.
Useful controls and measurements are summarized in the linked documents; complete
iteration histories remain recoverable through Git and private research records.
Preserving an artifact does not grant permission to publish it.
