# Independent-project cleanup review

Date: 2026-10-31. Baseline: public commit
`81cfdd50cb4e85f768b648c54b3ee9173ae7929b`. This is a normal follow-up to that
commit, not a new import or rewritten history.

## Scope and findings

The baseline scan covered **1,108 tracked files**, including 38 Markdown files.
Remediation was recorded as 32 actionable items, with each item assigned one
primary category; a file may have more than one issue:

| Category | Items | Treatment |
| --- | --- | --- |
| README | 2 | Matching user-first English/Chinese structure, version/platform evidence and resource/build boundaries |
| Documentation | 17 | Origin/attribution, current technical guides, historical evidence scope and obsolete instructions |
| UI | 4 | Remove browser, show FIFA/versions directly, remove stale DLC input, correct Chinese XCI/NSP label |
| Script help | 1 | Compile helper describes a local check rather than CI |
| Configuration/policy | 2 | Remove workflow; update agent language, single-game and attribution policy |
| Local links | 6 | Missing document targets repaired by current guides and valid anchors |

The old predecessor name appeared 18 times in tracked text across eight files;
all 18 were removed. No current public text links to that private repository.
Necessary producer/source IDs remain unchanged and unlinked, with their verification
boundary explained. Detailed old maintenance notes were preserved outside the
checkout. Original history is untouched.

## User documentation and technical records

Both READMEs now introduce Touchline 23, provide first-use/build/packaging steps,
separate Mac/iPhone/iPad evidence and retain limitations. The public upstream is
nxnative; credits follow the user workflow. Earlier maintainer FIFA adaptations
are not misattributed to the official upstream. All original author/license texts
and exact translator provenance manifests remain intact.

The graphics and profile guides describe the actual EASF -> NVN -> Metal path,
386 source programs, 520 libraries per platform and separate global-chain/profile
stamps. The generic profile fields remain documented. Extraction/debugging now
focus on FIFA, common container/program tools, build gates and controlled tests,
without copying another game's memory/probe/FPS settings into FIFA instructions.

Migration is explicitly historical, with no invalid old-baseline Git command.
The launcher/UI guide describes current behavior. Older container/discovery
engineering reports retain useful format, integrity, streaming and synthetic-test
evidence, clearly separated from the current single-game support list; obsolete
branch/merge/workspace instructions were removed or scoped as historical records.

## Retained names and evidence categories

- **A: incorrect product information** was corrected in the README, profile/graphics
  guides and packaging UI. No additional game is advertised as supported.
- **B: obsolete instructions** were rewritten, including old Git ranges, feature
  merge steps, CI claims and multi-game/DLC user guidance.
- **C: useful general mechanisms** remain in the shared engine, command-line schemas
  and synthetic tests. Other-title names in comments/fixtures and explicitly
  historical resource-reader cases are not product profiles. Generic catalog
  sorting/search code is retained internally, without a user-facing browser.
- **D: attribution and provenance** retain actual authors, third-party TitleID data,
  source/project identities and original legal citations. Touchline 27 appears only
  where needed for the translator audit/reference contract, not as a build or
  product dependency. Its fixed public R3 evidence remains linked. The unchanged
  translator DLL's disclosed historical debug-path marker is not rewritten.

Private historical objects are maintainer-verified evidence, not claimed to be
publicly retrievable or bit-reproducible builds. Their SHAs were not relabeled as
commits from another repository.

## Link and workflow checks

All six confirmed missing relative-link occurrences were fixed. The local checker
validates current tracked/new Markdown paths and GitHub-style heading anchors,
including encoded paths and reference definitions, and excludes fenced examples.
Current active documentation links and original citations were checked separately:
15 external Markdown URLs and 58 distinct GitHub URLs across tracked text.
Availability was verified with HTTP checks and browser-source fallback for transient
transport failures. The remaining old source citations are accurate retained
references, not private product entry points. No unresolved confirmed broken
local link or private repository hyperlink remains.

The sole workflow `.github/workflows/tests.yml` was removed; no workflows remain.
Tests, build scripts, source-publication checks and third-party material remain.
`check_markdown_links.py` and its failure controls are now local checks.

## UI and validation

Touchline 23 Packaging shows FIFA 23, base 1.0.0 and optional update 1.0.3 directly.
The browse/search/sort sheet and DLC editor are removed. A restored legacy add-on
path is cleared before forming GUI requests; the shared bridge/resource schema is
unchanged. macOS/iOS selection, External XCI/NSP, Directory, caching, approval,
progress, cancellation and diagnostics remain.

| Check | Result |
| --- | --- |
| Python scripts suite | 148 passed, zero failures/skips |
| Swift GUI/model suite and executable compilation | 101 passed, zero failures/skips |
| Resource discovery/build modes/macOS packaging subset | 55 passed, zero failures/skips; synthetic fixtures |
| Launcher Settings executable | Passed defaults, persistence, independent touch switches and platform filter |
| Markdown paths and local anchors | Zero unresolved errors |
| Translator/source/license provenance tests | Passed, included in the Python suite |
| Locked toolchain check | Passed; no fingerprint change |
| GUI interaction | English/Chinese fixed game/version display, both platform selection, Directory update-lock behavior and advanced form without DLC verified |

The interactive check used a local source-built UI shell, not a newly bundled
standalone Python/runtime distribution or a real game packaging run. No new game,
iOS/iPad device or individual MOD validation is claimed. No game App/IPA or 520-library
Shader rebuild was performed. Renderer, audio, resource reading/decryption, saves,
thread/memory behavior and Shader rules were not changed. Existing Release products,
translator binaries, lock/header, original license texts and provenance hashes
remain byte-identical.

## Publication

Review the exact staged delta and content scan before the normal commit/push.
The conservative scanner's known third-party file-type findings are manually
reviewed rather than treated as a zero-warning automatic certificate. Keep all
private game inputs, generated outputs, local audit logs, caches and the review
App outside the commit. The final Git commit/remote SHA and clean-worktree result
are supplied in the delivery receipt; this document does not self-embed its own SHA.
