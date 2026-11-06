# The Legend of Zelda: Ocarina of Time

Switch 2 title `0400486024DEC000`, SDK 22.2.8, NVN API 231.40, Nintendo sead / agl / gsys. This profile is part of the [Apple Silicon integration](../../../docs/fork-ocarina.md). The selected package is `v131072`; its module identities have been checked against the supplied NUP. All 42,850 shaders compile; manual gameplay validation of the combined branch is pending.

## Profile

The loaded modules are `main`, `subsdk0` (NintendoSDK_movie) and `sdk`:

| Module | Registered build ID |
| --- | --- |
| `main` | `e0f3ccfaf50065ae4ea01eb5aeb13b1a` |
| `subsdk0` | `b0110087a7b339ef74588d3bd0b4dd5d` |
| `sdk` | `1643a838814f9c10c696f930ed681e7f` |

The `v0` and `v131072` rows name the same registered module identities. The profile selects `v131072` for packaging and shader extraction. No fixed-address game rewriter cuts are installed.

The NPDM declares 48 MiB of system resources; startup requests a 6.20 GiB heap. The alias region is 8 GiB and the total reservation is 17.625 GiB. Both were increased together so the heap region retains its previous capacity. Upstream Kokiri Forest traces showed streaming mappings spread nearly 5 GiB into the alias region, exhausting the old 2.375 GiB region after several minutes. A 45-minute run with the larger values was reported on another integration stack; the combined branch still needs its own long run. Reservation size is virtual address space, not a measurement of physical memory use.

`render_cond on` is required: agl conditionally clears the copy of its prepass depth. Executing that clear unconditionally makes the main opaque pass's `EQUAL` test reject geometry, leaving the sky visible instead. The [general replay mechanism](../../../docs/reference/rendering.md#conditional-rendering-evaluated-at-replay) explains the behavior.

## Build and run on the Mac

Use the [fork build instructions](../../../docs/fork-ocarina.md#building-and-verification), selecting the complete shader map rather than a previously seen subset:

```sh
GAME_FOLDER=/path/to/OcarinaOfTime
python3 scripts/build_ipa_from_nsp.py "$GAME_FOLDER" --package v131072 --platform mac --no-seen-shaders
```

The packer prints the run command and keeps extraction, rewritten modules, shader outputs, saves and logs in the game's folder. A NUP needs no `prod.keys`. Follow the generated command rather than reusing old `patched_v0` paths or libraries from another PR's chain. `DM_METAL_HUD=1` enables the performance HUD; `DM_NVN_SHDUMP` records a program missing from the shader map.

Start a new game to test the full opening, then create and reload a save through the game's UI. Saves are user data and are not committed here. Old frame-number input scripts depend on the movie and presentation timing and need to be recorded again for this combined branch.

## Found on this game

These source fixes are integrated in the fork. Their individual upstream runs are provenance, while the final combined game run remains pending.

- Startup: local [eventfds](../../../docs/reference/services.md#eventfds-served-offline), the [virtual audio input list](../../../docs/reference/audio.md#no-virtual-audio-input-devices-sdk-22), and the completed [play report](../../../docs/reference/services.md#an-asynchronous-play-report-opens-prepou). The duplicate virtual-input hook introduced alongside main is removed.
- Movie programs: the [NDVE pack](../../../docs/reference/shaders.md#the-movie-librarys-ndve-shader-pack) contains 22 compute programs. [Raw-memory write logging](../../../docs/reference/frame-rate.md#a-full-frame-shader-overflows-the-raw-write-log), [LDSM barriers](../../../docs/reference/shaders.md#ldsm-reads-rows-other-lanes-stored), parallel decoding and movie-clock presentation address separate CPU/GPU timing and reconstruction failures. The opening is AV1; VideoToolbox and dav1d are available decode paths.
- Missing models: [NVN2 task and mesh extraction](../../../docs/reference/shaders.md#task-and-mesh-shaders-in-nvn2-bnsh-program-slots-7-and-8), [F2IP and payload reads](../../../docs/reference/shaders.md#f2ip-two-floats-into-two-bytes), and [indirect mesh arguments](../../../docs/reference/rendering.md#indirect-mesh-arguments) replace the earlier missing-stage and unimplemented-draw state. Native mesh pipelines are built before their first required draw.
- Foliage and lighting: preserved multi-result shader inputs and [float add atomics](../../../docs/reference/shaders.md#float-add-atomics). The previous failures on opcode `0x243` are addressed in source; a complete stamped build must establish current shader coverage.
- Six remaining Foliage compute failures on `0x3a9` are resolved by [ATOMG.CAS](../../../docs/reference/shaders.md#ampere-global-atomic-compare-exchange): `c144d8f734fbe228` and `13002657609092b4` belong to `foliage_mesh_turf`; `7d1481cf3458b690`, `49d003551e7dcaf1`, `de5a4f469cb990b2` and `3b8ecb1aa4207240` belong to `foliage_mesh_leaf`. All use the supported 32-bit nonuniform form. The original translator fails all six; the corrected translator translates all six and their generated MSL independently compiles with Metal. The Ampere memory suite passes 80 tests, and bound/raw CAS GPU probes pass 72 checks on the M2 Pro with Metal validation, including source/destination aliases and the write bitmap. These are genuine BAHS compute variants; whether a tested scene dispatches them remains open.
- Texture storage: [atomic RGBA8 reinterpretation](../../../docs/reference/rendering.md#atomic-reinterpretation-of-rgba8), [CPU-written uncompressed storage](../../../docs/reference/nvn-objects.md#uncompressed-storage-the-cpu-wrote-where-the-gpu-has-not-written), and range-based GPU-write tracking address different content paths. The mixed pool's terrain heightmaps must be checked in gameplay.
- Resource lifetime: [finalized textures retained through a submission](../../../docs/reference/nvn-objects.md#a-bindless-pool-churns-finalized-textures-within-a-submission) and [incremental bindless pool tables](../../../docs/reference/frame-rate.md#a-bindless-pool-table-rebuilt-for-every-registration). Dynamic raw-memory tables, address marks, a residency guard and idle buffer retirement are integrated in the [fork's memory integration](../../../docs/fork-ocarina.md#selected-fixes-and-provenance).
- Audio: the SDK 22 [update lock](../../../docs/reference/audio.md#the-update-lock-read-off-updateimpl-sdk-22) is read from the SDK code rather than assumed at the older offset.
- Validation also found an independent [odd-sized H.264 scratch-picture overflow](../../../docs/reference/movies.md#odd-sized-h264-nv12-scratch-pictures), resolved in the general decoder. The game uses AV1; no game symptom is attributed to this finding.
- A synthetic translator regression found during this bring-up: [dual predicate outputs](../../../docs/reference/shaders.md#dual-predicate-outputs-read-their-original-inputs) must retain the original accumulator. The correction passes 80 cases; actual use by an active game shader remains open.
- Shader extraction: [BAHS descriptor bounds](../../../docs/reference/shaders.md#bahs-control-and-metadata-words-mistaken-for-shader-descriptors) remove four scan false positives: `68bbe98b3bfd9876` in `agl_common`, `18be578dfdaaffa0` in `agl_technique`, `7a4936fccf82094e` in `agl_technique_pfx`, and `ce0eba6c3584814d` in `AglShader`. None is a descriptor in its resource's proven binary array. The full corrected resplit preserves every retained control/code record, fact and provenance; both pair tables remain byte-identical. The rejected compute candidate paired a vertex SPH with a compute control, causing the apparent unsupported opcode `0x481`.

## Validation

The final host compiled on an Apple M2 Pro (32 GB), macOS 27.2, Xcode 27.2 (Metal compiler `32023.922`). The complete host and graphics suites passed, followed by final targeted memory, codec, capture/replay and native-mesh checks. Shader tests: 269 passed, 2 skipped. The corrected full build produces all 42,850 shaders with chain `fc2372e30191`, inputs `1cde7e5d7e83`, with no failed shader, unknown binding kind or loss without failure. Manual gameplay validation is assigned to the user and remains pending.

Historical upstream #1299 reports reached controllable Kokiri Forest and Link's house on an Apple M5 with short high-FPS runs; later reports on smaller Macs exposed alias exhaustion, pool-table overflow and excessive GPU residency. Those reports motivated the selected fixes. Their frame times and memory values are not measurements of this fork. See the [verification matrix](../../../docs/fork-ocarina.md#building-and-verification) for current results and pending work.

**Local startup, November 6, 2026:** source `d2e37c95`, chain `fc2372e30191`, inputs `1cde7e5d7e83`, on the M2 Pro above. The packaged Mac app passed the system's first-launch assessment, prepared its 11 NDVE compute pipelines in 174.33 seconds, and displayed the rendered opening image with the Metal HUD at 2560x1440. Memory and per-thread CPU diagnostics are being collected. The HUD showed about 2.4 GB of process memory and 2.49 GB allocated by Metal in that opening; these are observations of the movie, not a gameplay benchmark. No game buttons were injected. The next cold/warm startup comparison and manual gameplay remain untested.

Two runtime diagnostics remain open: four AV1 packet refusals with 12 pictures waiting for released buffers, and one unimplemented `nvnCommandBufferSetComputeWorkloadPriority` call with priority `0x20`. Rendering continued; no host crash or GPU error was observed during this startup. The [decoder protocol](../../../docs/reference/movies.md#nncodec-video-decoders-taken-over) describes buffer readiness; determine the actual event/packet ordering before changing its queue limits.

**First scene transition:** the user reported an apparent freeze after the cutscene, then confirmed that loading advanced. Frame 5545 took 58.01 seconds: 54.32 seconds in 306 new pipelines plus 31 shader libraries, and 2.42 seconds uploading 1,262 MB of textures. Frames continued afterward. This is a measured cold pipeline/loading stall with bulk prebuild disabled, not evidence of a completed gameplay route. The host writes the newly created pipeline bases to its persistent archive; repeat-load behavior still needs measurement.

## Open

- **Runtime shader coverage:** all 42,850 shaders compile with the final ATOMG.CAS translator and corrected packages/profile tables; `d17eefaff4f0bc23` is present in `agl_ndsr_vr.pck`. Record first-use pipeline failures or runtime-missing keys. Offline compilation does not establish visual correctness or a gameplay pass.
- **Long-run memory and transitions:** exercise repeated house/forest transitions, save/reload and focus loss, recording the route and duration. Check alias usage, raw-memory table growth, address marks, write-bitmap capacity, GPU residency, deferred releases and guard behavior. Retired-ID dummy textures and experimental guest-texture deduplication are excluded; scene-change OOM is not declared resolved.
- **Picture:** validate terrain height, foliage stability, door attributes, volumetric fog, sky exposure and the full-resolution depth-copy path. The earlier incomplete shader build is not a visual reference. Compare the same scene and settings with the console where possible.
- **Startup diagnostics:** investigate the AV1 buffer-pressure messages and compute-workload-priority call recorded above. Their effect on complete movie playback and gameplay is not established.
- **Physics:** upstream testers reported a gameplay problem, but its cause and behavior on this branch remain unknown.
- **Upscaling and clocks:** the map contains NDSR and NDVE. Active FSR use has not been established. Trace actual dispatches and GPU timestamp conversions before selecting a replacement upscaler or disabling dynamic resolution.
- **Performance:** measure cold/warm pipeline preparation, GPU pass times and frame-time percentiles on the final build. Verify both low and high internal-resolution paths. No sustained frame-rate target has been established for this branch.
- **Other games and iOS:** the broad host/translator changes need cross-game regression coverage. No iPhone or iPad build or gameplay validation is recorded.
