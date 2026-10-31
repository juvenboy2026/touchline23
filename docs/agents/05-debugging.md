# 05 — FIFA 23 debugging

Start with the exact registered FIFA build, matching rewritten modules and stamped
Shader libraries. Preserve the current save; use a copied save and a new run folder
on the game drive. [Build and run](../fifa23/build.md#isolated-runtime-check) gives
the supported isolated-run recipe. Diagnostics and captures are private, not Git inputs.

## Reproduce and identify the build

Record source commit, host/library chain, profile input stamp, main/sdk Build IDs,
base/update version, device/OS, resource mode and the route to the symptom. Current
gameplay records concern 1.0.3; profile registration alone does not validate 1.0.0.
Read startup lines before comparing logs so an older sideloaded App is not mistaken
for the latest build. Never carry a probe offset between module builds unchecked.

Use the existing DM_CTL control file for repeatable button/stick sequences and
screenshots. Prefer observed frame ranges and scene landmarks to elapsed-time-only
scripts, which drift with load. A timed graceful exit is not a visual success.

## Crash reports and symbols

The host reports signal, fault address, module-relative pc/lr, registers, backtrace,
near-stack scan and guest thread state. Module offsets match a decompressed NSO
image; an ELF analysis tool may add its own image base. Identify that base before
using an address. Examine pointers, indices and saved LR as well as the failing
instruction; a corrupted index is not fixed by skipping the crashing load.

SIGKILL/exit 137 may have no host crash line. Inspect the operating-system report
and memory-pressure evidence rather than assuming a renderer failure. On macOS,
DiagnosticReports and `sample <pid>` can supplement the private run log. A missing
frame-pointer trace can still have useful return addresses in the stack scan.

`dm/tools/nso.py`, `nso2elf.py`, `sdis.py`, `nso_fnmap.py` and
`dm/tools/ghidra/Decompile.java` provide image, ELF, disassembly, function mapping
and targeted decompilation. Keep Ghidra projects and extracted binaries outside
Git. The Decompile script accepts module offsets; its @ prefix recreates a function.

## Temporary probes and race diagnosis

The shared Mac DM_PROBE facility accepts module:offset entries. Determine every
offset from the selected build first; no other game's numeric examples are FIFA
configuration. Probe at safe instruction boundaries with x16 available; PC-relative
instructions require special handling. Instrumentation can change timing and heap
layout, so repeat controls without it.

| Probe option | Purpose / caution |
| --- | --- |
| `@off`, `@*off`, `@xN+off`, dereference/add suffixes | Inspect data reached from registers |
| Register/memory conditions after `?` | Restrict reports to the relevant call |
| `DM_PROBE_ALL`, `DM_PROBE_X2` | Additional registers and bounded pointed data |
| `!xN`, `DM_PROBE_HEAP*` | Engine-layout-dependent heap inspection; inherited default offsets are not a FIFA heap ABI |
| `DM_PROBE_WATCH` | Protect/watch selected bytes; unsupported atomic forms may leave observation gaps |
| `DM_HITCH_DUMP` | Guest thread state after a presentation gap |
| `DM_SPIN_LIST`, `DM_SPIN_POLL`, `DM_SPIN` | Observe rewritten spin loops; disabling waits is a diagnostic control, not a shipped fix |

A repeated address from one run is not automatically valid in another. Resolve
current module bases and object identity. Guest signal handlers and the host's
scheduler use signals, so an attached LLDB session must pass the relevant signals
through; debugger stops can create a false deadlock. Attach/probe methods from
generic engine history are not proof they work with every FIFA scene.

For a timing-dependent failure, hold the route and load conditions constant and
record occurrence rates. Observation gates belong behind the exact build ID in
a temporary profile patch. Keep hot-path event capture bounded, avoid synchronous
per-hit logging, and remove diagnostic gates after the investigation. The shipped
FIFA profile currently requires no CUTS/OBS/FRAME_STEP entries.

## Shader/pipeline and rendering failures

Use the [graphics guide](../../dm/gfx/README.md), [Shader fixes](../fifa23/shader-fixes.md)
and [shadow controls](../fifa23/shadow-investigation.md) for the actual FIFA chain.

- Confirm the global chain and profile stamp before investigating a missing library.
- Record exact vertex/pixel keys and pipeline error text. A pairing/link check tests
  stage compatibility, not visual correctness, blending or every attachment state.
- Lookahead predictions are bounded and demanded pipelines take priority, but an
  intrinsic first-use compile can still stall. Compare pipeline misses with live
  stacks and resource reads before calling a hitch an I/O failure.
- Establish a visual detector/control before bisection of intermittent failures.
  Sparse screenshots without the symptom are not a passing regression.
- Use pass dumps and draw isolation to locate producers, bindings and reads.
  `DM_NVN_PASSDUMP`, `DM_NVN_PASSDUMP_ALL`, `DM_NVN_PASSGPU`,
  `DM_NVN_CBDUMP`, `DM_NVN_TEXINFO` and `DM_NVN_TEXRAW` are shared diagnostics.
- GPU-completed readback matters. A CPU encode-time dump can differ from what a
  draw read; later work in a submission can also overwrite the evidence. Track
  copies, inline updates and pending writes in command order.

Use [selected GPU/reflection regression tests](../fifa23/build.md#regression-checks)
and the matching external library. Legacy other-title fixtures are not shipped;
a missing fixture is a limitation, not a passing suite or new game support.
Do not replace a Shader or regenerate all 520 libraries to conceal a host-side bug.

## Memory, power and frame pacing

Compare host memory reports, `footprint -p <pid>`, `vmmap -summary <pid>`, replay
allocation counters and resource lifetime statistics across the same route.
`DM_NVN_ALLOCPROF` can distinguish growing objects from retained GPU resources;
autorelease pools, retired textures and serial tables are different mechanisms.

FIFA reserves 5 GiB of guest address space; physical footprint and iOS jetsam are
separate limits. Do not infer another title's allocator/alias layout from a generic
probe. `DM_ALIAS_WINDOWS` and thread/heap reports are diagnostic tools, not a reason
to change the verified memory partition during a documentation or UI task.

Frame reports distinguish CPU/submission work, GPU time, missed display ticks,
dropped frames, p99 timing and physical footprint. Record focus, thermal/load state
and background work. Energy and apparent FPS comparisons need repeated matched
controls; a few favorable frame samples do not prove stable 60 FPS.
This profile has no validated 30/60-FPS setting. General engine frame-step,
preemption or GPU barrier controls must not become undocumented user defaults.

## Saves and on-device diagnosis

Save-transaction fault injection (`DM_TEST_FS_FAILAT`) is a synthetic regression
facility. Run it against disposable fixtures, never a user's original save.
The generic transaction tests cover fallback/read-only behavior without modifying
FIFA game logic.

On iPhone/iPad the user signs and sideloads the unsigned IPA. Read Documents/log.txt
and log.prev.txt, verify the installed build and selected resource mode, then
reproduce. Documents/env.txt applies explicit diagnostic overrides; a baked env
file is another build input and applied settings are logged. Relative captures
land in Documents, where Files can retrieve them. Do not sign or install on the
user's devices yourself. Keep logs, screenshots, recordings and memory dumps out
of public source and redact private paths before sharing findings.

[Validation](../fifa23/validation.md) explains which Mac and iPhone results exist,
which were reported by users, and which current UI/build paths remain untested on
a device. Preserve that distinction in any new report.
