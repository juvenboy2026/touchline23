# FIFA 23 Legacy Edition

The one game Touchline 23 runs: the Switch release of FIFA 23 Legacy Edition
(`01001C8016B4E000`, update 1.0.3), on
[seedds/nxnative](https://github.com/seedds/nxnative) through the fork
[ohxiaoguang/nxnative-zzg](https://github.com/ohxiaoguang/nxnative-zzg). The
game's own code runs natively on Apple silicon through nxnative's NVN-to-Metal
graphics path.

Formal matches have been tested on a MacBook Air M1 and reported working on an
iPhone Air, in handheld and docked modes. Observed features include player,
stadium and crowd rendering, lighting, match audio and commentary, the control
indicator, both Radar modes and saves; iPhone testing also covers touch controls
and a gamepad. Other venues, weather, special scenes and long-term stability
remain only partially covered. See the platform-specific evidence below.

## Documentation

- [Packaging GUI](../packaging-gui.md): current four-mode workflow, English default and language menu.
- [Upstream record](../UPSTREAM.md): the commit this tree came from and how to follow later fixes.
- [Compatibility](compatibility.md): current status and known limits.
- [Build and run](build.md): prerequisites, source builds and unsigned IPA packaging.
- [Validation](validation.md): test methods, results and evidence boundaries.
- [Shader fixes](shader-fixes.md): extraction, lighting and runtime stage pairing.
- [Shadow investigation](shadow-investigation.md): indirect GPU reads and controls.
- [Audio](audio-fix.md): lifecycle, stereo downmix and queue behavior.
- [HUD and resource binding](bindless-hud-fix.md): descriptor pools and Radar.
- [Migration](migration.md): source provenance and integration boundaries.
- [Public-content audit](public-audit.md): publication checks and exclusions.
- [Research index](research-index.md): topics whose raw evidence stays outside Git.

Users supply their own game files and keys. No game assets, extracted programs,
converted shader source, keys, saves, screenshots, raw logs or GPU dumps are
included. Keep generated output in the game's external workspace.
