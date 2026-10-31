# Public source release audit

Review date: 2026-10-31. This audit covers the actual source distribution prepared
for the initial `main` commit to [ohxiaoguang/touchline23](https://github.com/ohxiaoguang/touchline23).
All six former publication blockers are resolved with the evidence below.
The earlier launcher-review hold is superseded, not treated as automatic clearance.
Game runtime coverage remains in [validation](validation.md).

## Disposition of each former blocker

| Former blocker | Current conclusion and evidence |
| --- | --- |
| Humanizer license and attribution | Resolved. Main DLL and 51 satellites match exact 3.0.10 NuGet members and package hashes. Original MIT text, .NET Foundation, Inflector and ByteSize attributions retained. License bytes rechecked directly against fixed source revision 90f0cb1d7427635f38b46350bb1dc5fca2164f2d. |
| RecyclableMemoryStream license | Resolved. Exact 3.0.1 package/member identity; original Microsoft MIT text rechecked at source revision e29a28387da9018fa9605a1dcb3f7a0435aa9974. |
| MsgPack.Cli license/copyright | Resolved. Exact 1.0.1 package/member identity; original Apache-2.0 full text rechecked at tag 1.0.1; package copyright retained: Copyright 2010-2016 FUJIWARA, Yusuke, all rights reserved. Reference review found no separate NOTICE at that tag. The DLL is unmodified and is not relicensed under MIT. |
| Four source-backed translator DLLs | Resolved. All match original producer commit 674c2e141cf87917271858c455657aa8637f22d0, the fixed Touchline 27 evidence and this tree's snapshot. 364 source/configuration/license files match producer Git objects; source tree and build relationships identified. Exact historical command/SDK recipe is not claimed. |
| Native .NET apphost | Resolved. Same producer/reference bytes; .NET 10.0.13 and source commit identified. Independent normalized SDK-template comparison repeated. Original package LICENSE and full third-party notices re-downloaded and verified. Not described as byte-identical to the NuGet native apphost. |
| Final public file collection | Reviewed through actual Git index blobs, isolated index export, content/type inventory and manual dispositions below. No game payload, keys, generated shaders, personal credential, PDB, App/IPA or build output is permitted. Normal initial commit/push only after these checks. |

## Identity, licenses and source evidence

[Runtime README](../../dm/third_party/translator-runtime/README.md) links all eight
unchanged original license/notice texts and explains the producer and native-host
comparisons. [binary-provenance.json](../../dm/third_party/translator-runtime/binary-provenance.json)
records versions, fixed NuGet URLs, full package/member SHA-256, source references
and material hashes. [binaries.tsv](../../dm/third_party/translator-runtime/binaries.tsv)
contains all 61 binary/reference comparisons; **61 identical, zero different**.
The two runtime JSON files are identical to the reference too.

The reference is Touchline 27 commit
`7ff172ea582dedea1f09cd4f3c98f681ca1c1cd0`. Its final report and R3 supplement,
rather than its superseded early unresolved assessment, supply the relevant prior
conclusions. No title-specific frame-rate or other-game copyright conclusion was
imported into this review. Touchline 23's shader chain remains `a885c56c665a`;
Touchline 27's later chain is not substituted.

The 56 external DLL/package matches were independently repeated against complete
cached NuGet packages, not inferred from filenames. Source-backed outputs and
364 non-README source/configuration/license files were independently compared with
original producer Git objects. [source-provenance.tsv](../../dm/third_party/translator-runtime/source-provenance.tsv)
records each SHA-256 and Git blob. Ryujinx src tree:
`eb03ac436a486e3bf4e003af125be706eea7e403`. Original MIT/Khronos licenses and
project references are retained. Original repository links may require authorized
access; no access credentials are included. Public reference evidence is linked
from the runtime README.

The native apphost's normalized SDK-template match accounts only for generated
application-name, link-edit size and code-signature fields. Full original .NET
third-party notices accompany the MIT license. Full-source attribution and package
identity are established; a bit-reproducible compiler invocation is a separate,
unproven property, not a remaining unidentified-origin or missing-license issue.

## Final distribution boundary and manual review

[THIRD_PARTY_NOTICES](../../THIRD_PARTY_NOTICES.md) preserves nxnative, Ryujinx,
Spv.Generator and all other component authorship. The source distribution selects
the Vulkan headers' permitted MIT alternative and includes its original full text.
The deko3d adaptation now has the complete original zlib notice; its exact original
import revision remains unrecorded, without inventing one. The reference's 15
Vulkan headers match this tree byte-for-byte. Existing original source notices,
patent grants and license files remain unchanged.

| File class / scanner finding | Manual disposition |
| --- | --- |
| Apphost and 60 DLLs | Exact, complete binary manifest and independent source/package checks above; original terms included. No other native executable, DLL or opaque binary is approved. |
| DLL historical build path | The unchanged dmsh_xlate.dll retains its historical absolute build/PDB path marker. It is disclosed build metadata, not a key or credential. The standalone PDB remains ignored; binary bytes were not rewritten for this audit. |
| Two PNG icons | Project artwork with assets/app-icon/make_icon.swift retained, not game images. These are the only published raster assets. |
| Four unityfs.py 16-byte constants | Type-tree signatures used as lookup identifiers, not AES decryption keys. Existing source disposition retained. |
| Assembly, renderer include fragments, GLSL helpers | Authored host/translator source, with original notices; not converted game shader output. |
| Large Vulkan header | Third-party text with retained copyright/SPDX and selected MIT full license. |
| Project/props, YAML, NuGet.Config, nuspec and JSON | Build configuration, dependency/attribution evidence or title-name metadata, reviewed as text as well as by file type. Original terms are not rewritten to silence scanners. |
| LICENSE, notices, AUTHORS, PATENTS | Retained original attribution/terms. Review warnings about extensions or source formatting do not imply permission to drop these files. |
| Game profile TSVs | Public identity/build IDs, compatibility settings, hashes and index/pairing metadata; no shader instructions or constant blobs. Generated c1_full/cb_extent tables remain excluded. |
| Root sources/docs and localization | Source, user-requested bilingual UI/docs and synthetic tests; no game ROMs, firmware, private endpoints or credentials. |

The final index is exported to an ignored isolated directory and scanned independently
of the working copy. A local manifest records every staged path, Git blob, SHA-256,
size and file type. Broad content checks include UTF-8 formats that the conservative
scanner marks for manual review. Scanner findings receive path/hash-specific manual
dispositions; its nonzero exit for retained third-party file types is not called a
clean automatic pass. Tests verify staged blob scanning before the first commit.
Exact-path .gitattributes rules preserve the existing whitespace of reviewed
upstream files and verbatim license/metadata texts, as for the pre-existing ZBIC
rule; affected inherited files were byte-compared with the snapshot. No vendored
source or original license was reformatted. Conflict-marker checks remain enabled.
One extra terminal blank line in the packaging workflow was removed; code is unchanged.

.gitignore excludes XCI/NSP and compressed containers, original NSO/NRO, RomFS/ExeFS,
keys/tickets, saves, logs/dumps/captures, generated metallibs/AIR, converted shaders,
PDBs and all build/App/IPA products. The final staged set is checked directly; ignore
rules alone are not publication clearance. Runtime packages remain present.

No game container, key, extracted executable, generated shader, image capture,
font, save, raw log, GPU dump, IPA/App or cache is part of the source publication.
Locally built artifacts can contain rewritten game code and derived assets; source
publication does not grant rights to distribute those artifacts. Release products
are not uploaded to GitHub by this task.

## Verification and limits

Run before committing:

```sh
python3 -m unittest scripts.tests.test_fifa23_public scripts.tests.test_translator_provenance
python3 scripts/check_fifa23_public.py
python3 scripts/check_fifa23_public.py --staged
DM_GAME=01001C8016B4E000 python3 dm/gfx/tools/dmsh_chain.py --check-tools
git diff --cached --check
```

A Homebrew .NET apphost may require DOTNET_ROOT as explained in the build guide.
Do not regenerate the lock or rebuild the 520 libraries to satisfy these checks.
Normal Git push and a remote commit/tree check complete publication; never force
push or upload ignored products. The initial commit SHA is reported in the release
receipt, not self-embedded in this commit.

No runtime/renderer/audio/resource/touch implementation, binary, chain lock/header
or Release artifact changed in this audit. No new gameplay or device test is claimed.
Source traceability and fulfilled notice requirements are evidenced here; this is
not a blanket guarantee of rights to user-supplied game content or every possible
future distribution.
