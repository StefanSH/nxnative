# Ocarina of Time integration for Apple Silicon

This branch of [StefanSH/nxnative](https://github.com/StefanSH/nxnative/tree/codex/oot-apple-silicon) integrates Ocarina of Time fixes on upstream `865cc35f`. The target is the Switch 2 game `0400486024DEC000`, package `v131072`, running natively on an Apple Silicon Mac through Metal. The [game note](../dm/games/0400486024DEC000/README.md) owns its build identity, profile and remaining game-specific checks.

**Status: integration and validation in progress.** The host and selected synthetic Metal tests have passed on the foundation described below. A complete shader build, gameplay on the final memory integration, and cross-game regression runs are pending. Upstream reports of gameplay are useful evidence for selecting fixes; they do not validate this combined branch. There is no iPhone or iPad compatibility claim for this integration.

## Selected fixes and provenance

The review snapshot is November 6, 2026, Moscow time. The initial profile review covered PRs created or updated in the preceding 24 hours with label `game: 0400486024DEC000`: #1297, #1299, #1386 and #1387. Other nxnative PRs were examined as dependencies. Lichii and Eglantine were inspected over their preceding 48-hour histories for relevant mechanisms, then compared with nxnative's Metal implementation.

The table identifies upstream sources. Cherry-picks and conflict resolution give this branch different local commit hashes. Contributors retain their attribution in the imported commit history.

| Source | Selected contribution |
| --- | --- |
| [#1299](https://github.com/seedds/nxnative/pull/1299), `10e53364`, `9fb44679`, `ee9b7765` | Game profile; offline eventfds and completed play reports; NDVE extraction; BNSH task/mesh extraction; raw-memory write bitmap and lookup hints; finalized-texture lifetime and incremental bindless pool tables. The duplicate virtual-audio-device hook is removed in this integration. |
| [#1300](https://github.com/seedds/nxnative/pull/1300), `e3f8ef8c6d98` | F2IP packed conversion, rounding modes and task shader reads of their own payload. |
| [#1312](https://github.com/seedds/nxnative/pull/1312), `ac0244286663` | Indirect mesh draws, atomic reinterpretation of RGBA8 storage, and linear deferred-release processing. |
| [#1329](https://github.com/seedds/nxnative/pull/1329), `c7264feebf6f` | Ampere carry predicates, PLOP3's second result, immediate POPC/FLO and LEA forms. |
| [#1343](https://github.com/seedds/nxnative/pull/1343), `6941aa847dee` | Preserve the inputs of a multi-result instruction while any result remains live. |
| [#1345](https://github.com/seedds/nxnative/pull/1345), `d7a43c2ad3cb` | Discover SDK 22's audio update lock from `UpdateImpl`. |
| [#1353](https://github.com/seedds/nxnative/pull/1353), `5ec8a62b7114`; [#1388](https://github.com/seedds/nxnative/pull/1388), `c8aeba864885` | Read NDSR shader records around short data entries and mixed constant-data pairs. |
| [#1357](https://github.com/seedds/nxnative/pull/1357), `072f8674caf0` | Compile generated Metal with sufficient bracket depth. |
| [#1359](https://github.com/seedds/nxnative/pull/1359), `34d04efbe93b` | Preserve floating-point global add atomics. |
| [#1368](https://github.com/seedds/nxnative/pull/1368), `7cd6750b3a77` | Build a required native mesh pipeline on first demand and record it for prewarming. |
| [#1376](https://github.com/seedds/nxnative/pull/1376), `2d6f86f819c4` | SIMD-group barriers around LDSM's cross-lane shared-memory reads. |
| [#1331](https://github.com/seedds/nxnative/pull/1331), `b6367705af06`; [#1377](https://github.com/seedds/nxnative/pull/1377), `d234d4f629ff`; [#1379](https://github.com/seedds/nxnative/pull/1379), `3b588ca6399b` | Metal scaling of decoded NDVE input, parallel AV1 decoding, and movie-clock presentation of decoded pictures. |
| [#1390](https://github.com/seedds/nxnative/pull/1390), `16e86fdc1754` | Track GPU-written texture storage by range so mixed CPU/GPU pools retain their CPU-written heightmaps. |
| [#1360](https://github.com/seedds/nxnative/pull/1360), `eaa7a1daed0e`; [#1394](https://github.com/seedds/nxnative/pull/1394), `a885f4be50b4` | Grow the raw-memory pool table and restrict residency to pools whose GPU addresses the game obtained. Reconcile both with #1299's write bitmap and lookup hints as one host/translator ABI. Synthetic GPU integration checks passed on M2 Pro; gameplay remains pending. |
| [#1391](https://github.com/seedds/nxnative/pull/1391), `5122c24de6ec`; [#1392](https://github.com/seedds/nxnative/pull/1392), `8cf269120187` | Guard residency commits against the working-set limit and retire replaced buffers when no submission is advancing. Synthetic GPU integration checks passed on M2 Pro; gameplay remains pending. |
| [#1374](https://github.com/seedds/nxnative/pull/1374), `9e2199cfd30e` | Repair the existing Python ratchet failure in the function-matching tests. |
| Local fix, `d2110ef6` | Compute both ISETP/UISETP/FSETP predicate results before writing either output; prepare the verified package identity and larger alias region. See [the predicate finding](reference/shaders.md#dual-predicate-outputs-read-their-original-inputs). |

A local follow-up also invalidates cached shader arguments when pool addressability changes. Its late-mark regression failed before the fix and passed after it. The memory changes need joint tests: a table which grows correctly must still retain every address reachable by a shader, and its hint indices and write bitmap must agree with its capacity. A clean text merge alone is insufficient. The working-set guard limits the consequences of excessive GPU memory; it does not establish that the game's memory use is bounded.

Local validation also corrected an independent [odd-sized H.264 NV12 scratch allocation](reference/movies.md#odd-sized-h264-nv12-scratch-pictures), capture/replay allocation failures, and compile-database parsing of continued Make commands. The H.264 overflow is proven with ASan; it is not presented as a cause of Ocarina's AV1 behavior.

## Profile choices

The [game profile](../dm/games/0400486024DEC000/README.md#profile) records the verified module IDs, selected package, larger alias region and reservation, and the reason for `render_cond on`. The alias expansion preserves the previous heap capacity and responds to observed streaming address-space fragmentation; its long-run behavior still needs validation on this branch. There are no fixed-address game rewriter cuts in this profile.

## Alternatives deliberately excluded

| Source | Decision |
| --- | --- |
| [#1297](https://github.com/seedds/nxnative/pull/1297) | Superseded by #1299. Its preliminary profile and guessed virtual-audio mixer are not part of this branch. |
| [#1387](https://github.com/seedds/nxnative/pull/1387) | Alternative bring-up snapshot with overlapping changes and opening-movie validation only. Do not combine its duplicate profile and shader implementations with this stack. |
| [#1386](https://github.com/seedds/nxnative/pull/1386) | Experimental guest-texture deduplication excluded: release/restore races can lose writes or expose partially restored pages. Reported guest-footprint savings do not solve GPU residency. Its broad local integration is not imported as a unit. |
| [#1393](https://github.com/seedds/nxnative/pull/1393) | The retired-ID dummy-texture workaround is excluded. It can change reads through handles whose storage still exists. Scene-change OOM therefore remains an explicit validation item. |
| Forced full resolution | No default patch disabling the game's dynamic-resolution controller. Establish the clocks, memory behavior and ordinary rendering first. |

## Findings from Lichii and Eglantine

[Lichii's predicate work](https://github.com/zortos293/Lichii/commit/c9ebb5c3af67) exposed a reproducible defect in nxnative's own ARM64 shader translator. The local correction preserves simultaneous predicate writes and has synthetic coverage. Whether an active Ocarina shader uses the failing encoding remains open.

Other findings supply specific checks rather than direct C++/Vulkan ports:

- [Lichii's vegetation work](https://github.com/zortos293/Lichii/pull/150): loaded pointers must address their target allocation, and grass records can lie 11.7–17.7 MiB past their base. Validate those addresses with the integrated raw-memory table. nxnative also has a 64 MiB heuristic for unknown-length large-pool bindings; full raw global memory uses a different path. Keep readable range and proven GPU-write range separate.
- [GPU timestamp domains](https://github.com/zortos293/Lichii/pull/84): check units and epochs across raw reports, conversion APIs, current-GPU time and VI. nxnative's hooked conversion differs from Eglantine's driver path; a unit change is not justified without an Ocarina trace.
- [Occlusion query accumulation](https://github.com/zortos293/Lichii/pull/121): retain the count through host submissions until the guest resets it. nxnative already retains this state. Do not import the fallback reset after 256 query slots.
- [A full clear overwriting initial texture contents](https://github.com/zortos293/Lichii/commit/27226d2568c9): a possible later Metal optimization, after proving subresource, channel, layer and scissor coverage. No local speedup has been measured.
- [Eglantine's scheduler fix](https://github.com/Djihads80/Eglantine/pull/639): draining an encoding queue must also wait for an active submission. nxnative already waits for the queue and encoder busy state.
- [Eglantine's memory release on Stop](https://github.com/Djihads80/Eglantine/pull/634): relevant to a reusable in-process frontend, while the ordinary nxnative host releases its mappings when its process exits. It does not reduce in-game GPU memory.
- [Eglantine's storage-buffer reversions](https://github.com/Djihads80/Eglantine/pull/571): the DLSS-only size gate is a performance stopgap. It supplies no verified Apple Silicon fix and is not imported.

Reports on other GPU backends are diagnostic evidence, not Apple Silicon validation. No AMD, NVIDIA or Intel backend implementation is added by this integration.

## Upscaling

The profile's extracted shader map contains NDSR and NDVE packs. No FSR/FidelityFX path has been established as the active in-game upscaler. Shader names alone do not prove the absence of another path; capture the actual dispatches before selecting a replacement.

Apple Silicon does not expose NVIDIA's desktop DLSS runtime. Existing nxnative can instead map [NVN2 DLSS evaluations to MetalFX Temporal](reference/rendering.md#nvn2s-dlss-on-metalfx), or translate a game's own shader network to Metal matrix operations. The separate optional [NDSR-to-MetalFX spatial substitution](reference/rendering.md#a-games-own-upscaler-drawn-by-metalfx) changes the image and must be verified for this game's bindings, color space and sizes. This branch does not label that substitution DLSS, or change Ocarina's upscaler default without a runtime comparison.

## Building and verification

Use Xcode 27.2 and its Metal compiler, Python 3.12 or newer, and the dependencies in the [build instructions](../README.md#build-from-the-command-line). Keep game files, extracted data, shader outputs and saves outside Git, in the game's own folder. Do not reuse another game's shader output directory.

```sh
git clone --branch codex/oot-apple-silicon https://github.com/StefanSH/nxnative.git
cd nxnative
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
GAME_FOLDER=/path/to/OcarinaOfTime
python3 scripts/build_ipa_from_nsp.py "$GAME_FOLDER" --package v131072 --platform mac --no-seen-shaders
```

The script accepts a NUP file or its folder and prints the development run command. It needs no keys for a NUP. After the full build and gameplay checks pass, `--platform mac-app` packs a Finder-launchable app. The shader translator, lock, chain header, stamped game libraries and host must come from the same integration; do not mix libraries from individual PRs.

| Check | Recorded result | Remaining evidence |
| --- | --- | --- |
| Package identity | Supplied `v131072` module IDs matched the profile | Recheck when changing the input build |
| Host | Foundation and combined-memory host builds and complete host unit suites passed on Apple M2 Pro, macOS 27.2, Xcode 27.2 | Final rebuild after lint-only and capture allocation corrections |
| Synthetic Metal foundation | Eight targets passed: mesh indirect, image usage, deferred release, pipeline warm/key, NDVE movie, CPU texture and CPU storage | Full Metal suite on the final integration |
| Shader chain | Rebuilt bundled translator and lock verified; chain `ac48fdb87d7c`; 265 shader tests passed, 2 skipped, including 80 predicate cases | Full game library build and runtime shader coverage |
| Profile and extraction tests | 21 focused tests and 19 final docs/profile checks passed; complete tool run: 1,287 tests, 23 skipped, one environment-table failure corrected and its targeted test passed | Final Python/C lint after remaining validation corrections |
| Raw-memory ABI and working-set guard | GPU tests passed: pool chunks 104, raw reads/writes 73, marks 38, guard 28 plus stuck-mode 2; geometry hazards 61 in each of three modes | Gameplay memory trajectory and scene changes |
| Full shader build | Complete extraction: 42,854 shaders, including three newly discovered compute programs; offline compilation running | Record input stamp, compiled totals and every failed key |
| Ocarina gameplay | Pending on this combined branch | Record machine, settings, route, duration, memory and screenshots |
| Other games | Impact analysis completed; other game files are not available locally | Check Ocarina, Donkey Kong Bananza (raw pointers), Mario Kart World (task/mesh), Tears of the Kingdom (bindless/image atomics), and Breath of the Wild (ordinary NVN control), with a harness report |
| iOS | Untested | Separate unsigned build and user-run device validation |

The gameplay route must cover a new game, the full opening, movement in Link's house and Kokiri Forest, repeated house/forest transitions, save creation and reload, focus loss and return, and at least 45–60 minutes of play. Record GPU allocation, residency, guest footprint, alias high-water marks, frame-time percentiles and new `[RED]` lines. Confirm terrain, foliage, door attributes, fog, exposure, movie reconstruction and dynamic-resolution transitions. A short high-FPS scene is not sufficient for acceptance.

Final-run record, to fill after testing:

```text
Commit / chain / profile stamp: pending
Mac / RAM / macOS / Xcode: pending
Game package / module IDs: pending
Route / duration / settings: pending
Shader failures / new RED / GPU errors: pending
Peak memory / alias use / frame-time percentiles: pending
Save/reload / scene transitions / focus return: pending
Cross-game regression report: pending
```
