# XCI external-reader report

> Scoped historical validation record, not a current all-game support matrix. Keep its original games, versions, commits and device limits. Current packaging and later FIFA-only feedback are recorded separately in the [validation records](../fifa23/validation.md).

Branch `feature/xci-external-reader`, based on `d1fd026`. Code commit: `a07febd`
(this report is a separate commit on top). All validation was read-only against the
original files; no container was converted, extracted wholesale, renamed or deleted,
and no key value or game data entered Git.

Goal met: the original XCI gamecard plus an optional NSP update is now mounted
directly, on macOS and iOS, through the same on-demand read path as NSPs — no NSP
conversion, no RomFS extraction, no disk cache, no full-container memory load.

## 1. Architecture and changed files

The change is one container layer inside the existing reader. `nxrom_open()` still
has one entry point; after `nr_file(base)` it detects a gamecard by content ("HEAD"
at 0x100) and either opens it as XCI or falls through to the unchanged PFS0 path.
Everything below the container — NCA selection, key-area decryption, IVFC, BKTR,
RomFS indexing, ExeFS build checks — is the existing NSP code, untouched.

```
guest read -> IVFC -> (BKTR) -> CTR/CTREx -> NCA range
    -> XCI: secure-partition HFS0 member range (new)
    -> XCI: root HFS0 slice of the card file (new)
    -> pread of the original .xci
```

| File | Change |
|---|---|
| `dm/resource/nxrom.c` | `nr_hfs0()` (partition member parser), `nr_xci()`/`nr_xci_probe()` (card header, root table, secure partition), content dispatch and `.xcz` early rejection in `nxrom_open()` |
| `dm/resource/tests/fixture.py` | `hfs0()`, `hfs0_fixed()`, `gamecard()`, `xci()` synthetic builders |
| `dm/resource/tests/test_nxrom.py` | XCI base+update+identity group, NSP/XCI byte parity, malformed-variant group |
| `dm/resource/tests/malformed.py` | gamecard corruption cases; 95 cases total (was 24) |
| `dm/resource/tests/test_resourcefs.py` | XCI mount through the Python wrapper, with and without update |
| `dm/resource/tests/test_nsp_prepare.py` | XCI-base preparation; XCI update refused |
| `dm/resource/tests/Makefile` | HLE and Mac checks now also run an XCI base and XCI+update |
| `dm/resource/tests/generate.py` | writes `base.xci` fixtures |
| `dm/resource/tests/oracle/Oracle.cs` | LibHac oracle opens gamecards for differential validation |
| `dm/resource/tests/validate_real.py` | globs `.xci` bases |
| `dm/resource/tests/bench_real.py` | new: container vs raw vs directory throughput/latency |
| `tools/nxrom/prepare.py`, `build_pipeline.py`, `mac_build.py` | accept `.nsp`/`.xci` base, NSP-only update |
| `scripts/build_ipa_from_nsp.py` | `--resource-backend nsp` accepts an XCI base |
| `dm/host/front_mac.m` | picker wording "NSP or XCI" |
| `docs/development/external-nsp.md` | gamecard subset, limitations and validation record |

No signature/API change: `nxrom.h` is unmodified. `hle_fs.c`, `hle_resource.c`,
`resource_check.c`, `resourcefs.py`, `inspect.c`, the iOS launcher and `main.m`
needed no change — detection is by content, and `.xci` was already in
`FORBIDDEN_SUFFIXES`/`pack_ipa.py --external-resources` audits.

## 2. Reused existing functionality

- `nr_store` layering (`nr_file`/`nr_sub`/`nr_ctr`/`nr_hash`/indirect): the secure
  partition and its members are ordinary slices of the card file descriptor.
- `nr_select` (Program NCA choice, key-area decryption, title identity),
  `nr_section`, `nr_patch` (BKTR), `nr_ivfc`, `nr_code`/`nxrom_check_build`,
  `nr_index` and the whole directory/path/enumeration API.
- ResourceFS Python wrapper, HLE mount dispatch (`DM_RESOURCE_BACKEND=nsp`),
  `dm_external_resource_check`, the Mac/iOS launchers, packaging audits.
- The `nsp` backend id remains the single external-container mode, as the design
  note in `docs/development/external-nsp.md` prescribed.

## 3. New container parsing

Gamecard layout was established from two independent retail dumps (see §6) before
implementation:

- Card header: magic at 0x100; root partition offset/header size at 0x130/0x138;
  SHA-256 of the root HFS0 header at 0x140 (verified to match on both dumps).
- Root HFS0: entries `update`/`logo`/`normal`/`secure`, entry-relative data offsets;
  only `secure` is located (unique by name); the firmware-update, normal and logo
  partitions are never read.
- Secure partition: HFS0 member table of the NCAs; members become `nr_pfs` members
  and flow into the unchanged NCA machinery.

Strictness: header hash mismatch, header/table size disagreement, truncated card,
root offset out of range, missing or duplicate `secure`, corrupt secure-prefix hash
(root entry hash verified up to 1 MiB), bad member names (empty, `..`, separators,
duplicates), member ranges past the bytes that exist, overlapping members,
`hashed > size`, `.ncz` members — all rejected with `EBADMSG`/`ENOTSUP`. All parsed
sizes are range-checked against the physical file (64-bit safe); the parser reads
only headers and the mounted byte ranges. Root-declared partition sizes are
deliberately advisory: both retail dumps' secure partitions claim bytes past the
trimmed file end, so member data — not declarations — is bounds-checked.

## 4. XCI + NSP update support

Implemented through the existing update path: the update stays an NSP (PFS0), its
Program NCA must be the same title or base+0x800, and its BKTR layer maps over the
gamecard's decrypted base storage. Verified:

- synthetic XCI base + NSP update: full updated view byte-exact, boundary offsets,
  wrong-title update refused (native reader, Python wrapper, HLE mount, Mac check);
- real: XCI + wrong-title update NSP refused (`EINVAL`), XCI + NSZ update refused.
- **Not verified**: a real XCI with its real matching NSP update — no such pair
  exists locally (the FIFA 23 update is NSZ, deliberately unsupported; Rhythm
  Heaven Groove 1.0.0 has no update). This remains fixture-level evidence only.
- NSP base + NSP update behaviour is unchanged (all prior tests pass unmodified).

## 5. Unit and regression tests

| Suite | Result |
|---|---|
| `test_nxrom.py` | 11/11 (2 new XCI groups) |
| `test_resourcefs.py` | 7/7 (1 new XCI group) |
| `malformed.py` under ASan/UBSan | 95 cases, no findings (24 prior + 71 new XCI) |
| `test_profile_resource.py`, `test_shader_stream.py`, `test_shader_package.py`, `test_nsp_prepare.py` (7, incl. new XCI case), `test_prepared_build.py`, `test_mac_prepared_build.py`, `test_shader_compile.py`, `test_build_pipeline.py`, `test_packaging.py`, `test_mac_packaging.py`, `test_build_modes.py`, `test_smoke_runner.py` | all OK |
| HLE `t_hle_nsp` (real `hle_fs.c` mount) | 4/4: NSP, NSP+update, **XCI, XCI+update** |
| `t_mac_check` (`resource_check.c`) | OK for NSP and XCI (+update) |
| iOS cross-compile (`make platform`) | arm64 iOS object builds clean |
| `dm/tools/tests`: `test_nsp_chain`, `test_nsp_mac`, `test_nsp_progress` | OK |
| macOS host build (`make dmhost`) | builds (pre-existing gfx warnings only) |

Concurrent reads, EOF, zero-length files, random offsets and cross-block reads are
covered both on synthetic XCI fixtures and on the real cards (§7).

## 6. Real XCI test results (read-only)

Inputs (never modified; paths contain spaces/brackets/CJK and are quoted):

- `<game folder>/[Rhythm Heaven Groove][0100D9F01D474000][1.0.0][HK][21.0.0].xci` (3.8 GB, SHA-checked content)
- `<game folder>/EA SPORTS FIFA 23 Nintendo Switch™ Legacy Edition [01001C8016B4E000] (US).xci` (15 GB)
- keys beside each card; the FIFA 1.0.3 update is **NSZ** — rejected by design, no decompression attempted.

- Mount: both cards open from the original path in ~9-11 ms (index build) with the
  expected title ID; wrong title refused.
- Enumeration: Rhythm 7,902 entries (7,237 files / 665 dirs, 3.17 GB); FIFA 71
  entries (62 files, 13.49 GB — EA's large `.big`/`.cbac` archives visible).
- Full `--verify` (every byte read, IVFC-checked, SHA-256 per file): Rhythm
  3,819,575,808-byte card in 7.0 s; FIFA in 28.2 s; exit 0, no integrity failures.
- Negative: wrong title, wrong-title update, NSZ update, `.xcz` suffix, `.nsz`
  suffix — each refused with a clear stage message.

**Not verified (no conditions to do so):** a real XCI paired with its real NSP
update (§4); physical iOS execution/import of an XCI; an actual game running from
an XCI mount (the Rhythm Heaven Groove Mac App on disk carries an older host binary
and its own layout; rebuilding its prepared modules/shaders was out of scope, and
FIFA 23 shader support is explicitly excluded). No FPS claims are made.

## 7. Hash-consistency verification

Differential oracle: `Oracle.cs` was extended to open gamecards through the
project's existing MIT LibHac assembly (the same `Xci`/secure-partition code path
`nx_extract` already uses). For both cards the complete listings — every directory,
file path, file size and full-content SHA-256 — are **byte-for-byte identical**
between the native reader and LibHac (sorted `diff` empty: 7,902 and 71 lines).
Additionally 496 random and block-boundary reads (sizes 1 B / 17 B / 4 KiB / 33,333
B at offsets including 16-byte CTR and 4/16/64 KiB IVFC boundaries, smallest and
largest files, 8 random files) matched between two independent I/O paths (Python
stream API vs inspector binary). One 23.8 MB file extracted as a directory-mode
sample matched its in-container SHA-256 (`f8c5dd0c…`).

## 8. Performance (resource-read layer only; no FPS conclusions)

Same volume, external SSD; the container path includes AES-CTR + IVFC SHA-256:

| Measurement | Result |
|---|---|
| Full-card sequential verify, Rhythm 3.8 GB | 545 MiB/s (7.04 s) |
| Full-card sequential verify, FIFA 15 GB | 530 MiB/s (28.2 s) |
| Raw card file sequential (`dd`, ceiling) | 893 MiB/s (936 MB/s decimal) |
| Mount/index time, 7,237 files | ~9-11 ms |
| Random 64 KiB, warm cache: container vs directory | 0.068 ms vs 0.026 ms mean (2.6x) |
| Random 4 KiB, warm cache: container vs directory | 0.026 ms vs 0.269 ms mean (container faster: the directory backend re-opens the file per read) |

Overhead of decryption+verification at sequential saturation is ~1.7x versus the
raw device; warm-cache small-read latency stays well under 0.1 ms. Frame-rate
impact was not measured and cannot be inferred from these numbers.

## 9. Unsupported formats and limitations

- NSZ/NCZ/XCZ (and FIFA 23's NSZ update): refused; a block-NCZ backend is future
  work. Renaming a compressed file is detected by content/suffix and refused.
- Gamecard Program NCAs with a rights ID: refused (`EACCES` path) — the title key
  exists only in the per-console encrypted InitialData region; no `.tik` exists on
  a card. Both tested retail cards use key-area keys and need only `prod.keys`.
- Card fields beyond the parsed set (card size code, InitialData, certificate,
  the header hashes after 0x140) are not validated; the RSA header signature is
  not verified (unchanged stance for NSP authenticity).
- The on-card `update` partition is the console firmware, not a game update; it is
  never read. Game updates come only as NSPs.
- XCI variants not covered by the two retail dumps (e.g. unusual card header
  versions, multi-program cards, homebrew images) are untested; the parser fails
  closed (`EBADMSG`/`ENOTSUP`) rather than guessing. A "secure" prefix larger than
  1 MiB is not hash-verified at open (no such retail case observed).
- No DLC from an XCI (unchanged: DLC NSP mounting is not implemented in any mode).

## 10. Historical source identity

The original reader implementation is recorded as `a07febd` in the earlier
maintainer development line. That ID and the original baseline `d1fd026` are
historical source evidence, not commits or branch instructions for this independent
repository. No current merge/unpushed status is implied.

## 11. Current maintenance

The former feature-branch merge recipe is obsolete. Follow this repository's
[maintenance principles](../UPSTREAM.md#following-nxnative-fixes), use the current
FIFA profile and select local resource tests with synthetic fixtures. The reader's
content-detection and integrity contracts remain useful independent of the original
other-title experiments. Preserve those contracts when importing a general fix.

## 12. Historical FIFA EASF follow-up

The following list describes the original reader task, before the dedicated EASF
provider was integrated. It is not the current missing-feature list. Current
External XCI/NSP and Directory recipes are in the [packaging guide](../packaging-gui.md).

The XCI side is ready for it: FIFA 23's card mounts, enumerates and hash-verifies
(§6/§7), and `.big`/`.cbac`/`.bh` assets are ordinary seekable streams through
`ResourceFS(library, base=<xci>, keys=..., title=01001C8016B4E000)`. What the EASF
path still needs beyond this task:

- an EA `.big`/`.bh` stream adapter in `shader_scan.py`/`shader_split.py` (the
  current scanner refuses them as engine archives), reading shader entries
  bounded-range through the existing stream API — no RomFS materialization;
- a standard NSP (not NSZ) of the update, or an NSZ policy decision, before
  XCI+update runtime can be exercised on this title;
- the game profile, rewriter cuts and EASF shader translation belong to the FIFA
  integration branch, not here.

Interface contract for that work: `ResourceFS.open(path)` returns a read-only
seekable stream; per-call transfers cap at 1 MiB; `check_build` enforces module
identity against the card's ExeFS; `--title 01001C8016B4E000` is the gate that
prevents any other container from mounting as this game.
