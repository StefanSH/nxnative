# Ocarina of Time integration for Apple Silicon

This branch of [StefanSH/nxnative](https://github.com/StefanSH/nxnative/tree/codex/oot-apple-silicon) integrates Ocarina of Time fixes on upstream `865cc35f`. The target is the Switch 2 game `0400486024DEC000`, package `v131072`, running natively on an Apple Silicon Mac through Metal. The [game note](../dm/games/0400486024DEC000/README.md) owns its build identity, profile and remaining game-specific checks.

**Status: code integrated and automated checks passed; all game shaders compiled.** The host build, complete host unit suite, complete graphics suite and targeted final-source checks have passed on the Apple Silicon Mac described below. The packaged Mac app displayed its opening image with the full Metal HUD; see the [startup record](../dm/games/0400486024DEC000/README.md#validation) for cold prewarm time and remaining runtime diagnostics. Manual Ocarina gameplay will be tested by the user; no gameplay pass is recorded for this combined branch. Other-game regression runs are also pending. Upstream gameplay reports are useful evidence for selecting fixes; they do not validate this combined branch. There is no iPhone or iPad compatibility claim for this integration.

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
| [#1275](https://github.com/seedds/nxnative/pull/1275), narrow port from `6f9733800b5f` | Implement 32-bit Ampere `ATOMG.CAS` (`0x3a9`) through the existing atomic compare-and-swap IR and raw-memory ABI. All six affected Foliage compute programs translate and Metal-compile; 80 Ampere memory tests and 72 GPU CAS checks passed. Unsupported widths and uniform-address forms fail explicitly. |
| Local fix, `d2110ef6` | Compute both ISETP/UISETP/FSETP predicate results before writing either output; prepare the verified package identity and larger alias region. See [the predicate finding](reference/shaders.md#dual-predicate-outputs-read-their-original-inputs). |

A local follow-up also invalidates cached shader arguments when pool addressability changes. Its late-mark regression failed before the fix and passed after it. The memory changes need joint tests: a table which grows correctly must still retain every address reachable by a shader, and its hint indices and write bitmap must agree with its capacity. A clean text merge alone is insufficient. The working-set guard limits the consequences of excessive GPU memory; it does not establish that the game's memory use is bounded.

The final extraction check also resolved [BAHS control fields mistaken for shader descriptors](reference/shaders.md#bahs-control-and-metadata-words-mistaken-for-shader-descriptors). The complete resplit removes four false entries without changing any retained shader bytes, facts or program-pair tables.

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

The script accepts a NUP file or its folder and prints the development run command. It needs no keys for a NUP. Use `--platform mac-app` to pack a Finder-launchable app for manual testing. The shader translator, lock, chain header, stamped game libraries and host must come from the same integration; do not mix libraries from individual PRs.

| Check | Recorded result | Remaining evidence |
| --- | --- | --- |
| Package identity | Supplied `v131072` module IDs matched the profile | Recheck when changing the input build |
| Host | Final host rebuild and complete host unit suite passed on Apple M2 Pro (32 GB), macOS 27.2, Xcode 27.2; foundation validation source `2420052e`, followed by the verified BAHS/CAS changes | Manual game startup and behavior |
| Graphics suite | Complete graphics suite passed in 1,349.2 seconds; final PSO-key and live capture/replay checks passed, with both fresh replays matching the live frame | Real-game rendering and performance |
| Final targeted checks | Odd-NV12 ASan regression passed; rebuilt codec-video tests passed; native mesh rasterization passed all 8 classic/Metal 4, direct/indirect and zero/nonzero-work cases (60 checks) | Runtime coverage of the corresponding game paths |
| Shader chain | Rebuilt bundled translator and lock verified; chain `fc2372e30191`; 269 shader tests passed, 2 skipped, including 80 predicate cases and the new CAS regressions | Runtime shader and pipeline coverage |
| Profile and extraction tests | 21 focused tests and 19 final docs/profile checks passed; complete tool run: 1,287 tests, 23 skipped, one environment-table failure corrected and its targeted test passed; 32 final source checks passed | Recheck when changing the package or generated metadata |
| Lint | Python ratchet: 0 new findings; LLVM 23.1.4 C/Objective-C ratchet: 0 file/check pairs above baseline after final allocation, codec and mesh corrections | Rerun for subsequent source changes |
| Raw-memory ABI and working-set guard | GPU tests passed: pool chunks 104, raw reads/writes 73, marks 38, guard 28 plus stuck-mode 2; geometry hazards 61 in each of three modes | Gameplay memory trajectory and scene changes |
| Full shader build | 42,850/42,850 shaders built with chain `fc2372e30191`, inputs `1cde7e5d7e83`; 55,477 Metal-cache hits and six new compilations. Zero failed shaders, unknown binding kinds or losses without failure. Four false BAHS records removed; all retained shader bytes and both pair tables preserved | Runtime coverage, first-use pipelines and visual comparison |
| Ocarina startup and gameplay | Packaged app startup and visible opening image/HUD verified; user-run manual gameplay pending, with no gameplay pass recorded | Record machine, settings, route, actual duration, memory and screenshots |
| Other games | Impact analysis completed; five-game `regress.py check` stopped at discovery with exit 2 because only Ocarina has a local Mac build. No comparison report or green record was produced | Obtain Mac builds of Donkey Kong Bananza (raw pointers), Mario Kart World (task/mesh), Tears of the Kingdom (bindless/image atomics), and Breath of the Wild (ordinary NVN control), then rerun with Ocarina |
| iOS | Untested | Separate unsigned build and user-run device validation |

The manual-test app enables the Metal HUD (device, resolution, process/Metal memory, FPS, frame interval, GPU time, Metal CPU encoding time, thermal state and shader compilation, with metric ranges). Memory and per-thread CPU samples are also saved beside the build. It uses `DM_PSO_PREBUILD=0`: the profile’s warm seeds and required on-demand pipelines remain enabled, while first-use pipeline stalls can still occur. No bulk offline pipeline archive is bundled for this first run.

For manual testing, the recommended route is a new game through the opening, movement in Link's house and Kokiri Forest, house/forest transitions, save creation and reload, and focus loss and return. Follow with a longer play session when practical and record its actual duration. Observe terrain, foliage, door attributes, fog, exposure, movie reconstruction and dynamic-resolution transitions. Where available, retain GPU allocation, residency, guest footprint, alias use, frame-time percentiles and new `[RED]` lines alongside screenshots. A short high-FPS scene does not establish long-run memory behavior.

Final-run record, to fill after testing:

```text
Source / chain / profile stamp: d2e37c95 / fc2372e30191 / 1cde7e5d7e83
Mac / RAM / macOS / Xcode: Apple M2 Pro / 32 GB / 27.2 / 27.2
Game package / module IDs: v131072 / verified profile IDs (game note)
Route / duration / settings: opening and first scene transition observed; full manual route pending; HUD on; bulk PSO prebuild off
Shader failures / runtime diagnostics: 0 offline failures; two open startup diagnostics in the game note
Peak memory / alias use / frame-time percentiles: gameplay measurements pending
Save/reload / scene transitions / focus return: pending
Cross-game regression report: preflight exit 2; four requested Mac builds unavailable
```
