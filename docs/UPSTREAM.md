# Project origin and attribution

Touchline 23 is an independently maintained project for **FIFA 23 Legacy Edition**
on Apple silicon macOS, iOS and iPadOS. Its public upstream is
[nxnative](https://github.com/seedds/nxnative); its home and release history are
[ohxiaoguang/touchline23](https://github.com/ohxiaoguang/touchline23).
No private repository is required to build or run the published source.

## Engine and FIFA adaptation

The inherited nxnative engine provides native ARM64 execution, kernel/service
emulation, program rewriting, NVN-to-Metal translation, graphics infrastructure
and platform integration. Original author notices and the seedds MIT grant remain.
This project does not claim to have written those components from scratch.

FIFA 23 bring-up, EA EASF archive handling, descriptor/indirect-read compatibility,
audio corrections, the external-container resource path and packaging work were
developed on that engine in the maintainer's earlier development line. They are
retained and maintained here, not all attributed to official nxnative. Technical
decisions and scoped evidence are in the [FIFA notes](fifa23/README.md) and
[historical integration record](fifa23/migration.md).

The imported development snapshot is identified by commit
`6dcf9868582388173f81f4f02385cd4cdb125b3e` (2026-10-29). This is a historical
maintainer-source identifier, **not a claim of a direct clone from an official
nxnative commit with that SHA**. Detailed private checkout/migration records are
maintainer material. The independent public history begins at
`81cfdd50cb4e85f768b648c54b3ee9173ae7929b`; those earlier source IDs are not
revision ranges in this repository.

## Independently maintained product

The current project carries one profile, `dm/games/01001C8016B4E000`, with the
registered 1.0.0 and 1.0.3 builds. It supplies single-game build wrappers,
Touchline 23 branding and original icon artwork, a dedicated packaging UI,
bilingual launchers and About pages, resource selection and user/developer guides.
The App identity is `com.ohxiaoguang.touchline23`; the tool is
`com.ohxiaoguang.touchline23.packaging`.

Shared engine facilities and their tests remain where useful. Their presence is
not support for another game; no other profile should be introduced automatically.

## Third-party source and translator provenance

[THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md) indexes original licenses,
notices, authors and the boundaries of this project's MIT grant. Those texts must
remain intact. Ryujinx/Spv.Generator, libvpx, stb, MacNativeGames, deko3d, Vulkan
headers and other components retain their own authorship and applicable terms.

The retained translator's [runtime review](../dm/third_party/translator-runtime/README.md)
records exact package identities, producer commit, source tree and per-file hashes.
Original-source Git comparisons were performed by the maintainer; some original
objects are not publicly browsable. Public reference evidence, copied original
license texts and the full hash manifests remain available. This is source/build
traceability, not an independently reproduced historical compiler invocation.
The public documentation does not replace unavailable evidence with unrelated
upstream SHAs or claim that private historical logs are public tests.

## Following nxnative fixes

Review general fixes from [the public upstream](https://github.com/seedds/nxnative)
in a separate checkout. Compare the affected semantics and source; bring across
selected changes with attribution and appropriate local tests. This tree does not
share the upstream repository's complete history, so do not copy historical Git
range or three-way merge commands that assume its objects exist here.

Prefer Horizon/NVN/SDK semantics and binary evidence over game-name branches.
Fixed addresses must be gated by the exact NSO build ID and rechecked by disassembly
when a new build appears. Preserve the single-game profile, names and bundle IDs.
A generic fix must not restore unrelated profiles or change FIFA settings silently.

Only a deliberate translator/tool or profile-input change warrants new Shader
libraries. For chain changes follow [AGENTS.md](../AGENTS.md): regenerate the chain
header, rebuild both platform libraries with matching stamps, then rebuild the
host. Documentation and launcher-only edits reuse the existing libraries.

## Build and publication boundary

Build with the [documented local tools](fifa23/build.md) and user-supplied inputs.
No game, key, extracted module, generated Shader, App/IPA, save or raw diagnostic
belongs in the source commit. The [publication audit](fifa23/public-audit.md)
records the retained binaries' clearance and the checks for later changes.

Use local tests and source review; this project does not use GitHub Actions.
Keep the existing `main` history, repository-local author identity and normal
push workflow. Source publication does not authorize distribution of proprietary
material embedded in locally built artifacts.
