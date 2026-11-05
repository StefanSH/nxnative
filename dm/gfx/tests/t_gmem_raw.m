// A translated load at an address the shader read from memory (GlobalToStorage.TryGenerateRawStorageOp), run on the GPU against the host's own pool table (nvn_mtl.m gmem_map_gpu) with more
// pools than its least count: each probe must read its pool's word, including the pools past entry 4,096, and an address in no pool reads 0. The shader is test_dmsh_ampere_mem.py's
// RawGlobal one: it loads the address from words 0 and 1 of storage slot 0 and stores what it read at word 2.
// Usage: t_gmem_raw <metallib>
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, failed;
#define CHECK(label, c) do { checks++; if (!(c)) { failed++; fprintf(stderr, "FAIL: %s (line %d)\n", label, __LINE__); } } while (0)
int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 3) { fprintf(stderr, "usage: t_gmem_raw <load metallib> <store metallib>\n"); return 2; }
    mtl_init();
    enum { MANY = 5000, PG = 16384 };
    const uint64_t MB = 1ull << 20;
    uint8_t *many = mmap(NULL, (size_t)MANY * 2 * PG + 8 * MB, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0), *large = mmap(NULL, 64 * MB, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (many == MAP_FAILED || large == MAP_FAILED) abort();
    for (int i = 0; i < MANY; i++) { uint8_t *p = many + (size_t)i * 2 * PG; mtl_pool_add(p, PG); mtl_pool_buffer_addr(p, PG); uint32_t v = 0x10000u + (unsigned)i; memcpy(p + (size_t)(i * 8 % PG), &v, 4); }
    mtl_pool_add(large, 64 * MB); mtl_pool_buffer_addr(large, 64 * MB); { uint32_t v = 0xb16b00b5u; memcpy(large + 40 * MB + 12, &v, 4); }
    uint8_t *hinted = (uint8_t *)(((uintptr_t)many + (size_t)MANY * 2 * PG + (2 * MB - 1)) & ~(uintptr_t)(2 * MB - 1));
    mtl_pool_add(hinted, 4 * MB); mtl_pool_buffer_addr(hinted, 4 * MB);
    *(uint32_t *)(hinted + 4096) = 0xabcdef01u;
    mtl_sub_begin(); uint64_t map_gpu = gmem_map().gpuAddress; CHECK("submission completes", mtl_wait(mtl_sub_commit(), 5000000000ull));
    id<MTLBuffer> map = g_gmem_buf; unsigned entries = (unsigned)(map.length / DMSH_GMEM_MAP_ENTRY);
    CHECK("the table holds more than the least count", entries > DMSH_GMEM_MAP_ENTRIES && map_gpu == map.gpuAddress);
    NSError *error = nil;
    id<MTLLibrary> lib = [g_dev newLibraryWithURL:[NSURL fileURLWithPath:@(argv[1])] error:&error]; if (!lib) { fprintf(stderr, "library: %s\n", error.description.UTF8String); return 1; }
    id<MTLComputePipelineState> pso = [g_dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"main0"] error:&error]; if (!pso) { fprintf(stderr, "pipeline: %s\n", error.description.UTF8String); return 1; }
    id<MTLBuffer> slot = [g_dev newBufferWithLength:16 options:MTLResourceStorageModeShared], args = [g_dev newBufferWithLength:16 options:MTLResourceStorageModeShared];
    uint64_t *a = args.contents; a[0] = slot.gpuAddress; a[1] = map.gpuAddress;   // the argument buffer: storage slot 0 [[id(0)]], the pool table [[id(1)]]
    uint32_t (^probe)(uint64_t) = ^uint32_t(uint64_t addr) {
        uint32_t *w = slot.contents; memcpy(w, &addr, 8); w[2] = 0xdeadbeefu;
        id<MTLCommandBuffer> cb = q_cb(); id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoder];
        [ce setComputePipelineState:pso]; [ce setBuffer:args offset:0 atIndex:0];
        [ce useResource:slot usage:MTLResourceUsageRead | MTLResourceUsageWrite]; [ce useResource:map usage:MTLResourceUsageRead];
        [ce dispatchThreadgroups:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(32, 1, 1)];
        [ce endEncoding]; [cb commit]; [cb waitUntilCompleted];
        CHECK("the dispatch completes", cb.status == MTLCommandBufferStatusCompleted);
        return w[2];
    };
    int hits = 0, n = 0;
    for (int i = 0; i < MANY; i += 97) { n++; uint64_t p = (uint64_t)(uintptr_t)(many + (size_t)i * 2 * PG); hits += probe(p + (uint64_t)(i * 8 % PG)) == 0x10000u + (unsigned)i; }
    { int i = MANY - 1; n++; uint64_t p = (uint64_t)(uintptr_t)(many + (size_t)i * 2 * PG); hits += probe(p + (uint64_t)(i * 8 % PG)) == 0x10000u + (unsigned)i; }
    CHECK("small pools: each probe reads its pool", hits == n);
    { uint64_t last = (uint64_t)(uintptr_t)(many + (size_t)(MANY - 1) * 2 * PG); unsigned e = 0;
      for (unsigned k = 1; k < entries; k++) if (((const uint64_t *)map.contents)[k * (DMSH_GMEM_MAP_ENTRY / 8)] == last) e = k;
      CHECK("the last small pool lies past the least table", e >= DMSH_GMEM_MAP_ENTRIES); }
    uint64_t chunk = (uint64_t)(uintptr_t)hinted >> DMSH_GMEM_HINT_SHIFT;
    uint32_t *hint = (uint32_t *)map.contents + (chunk & (DMSH_GMEM_MAP_ENTRIES - 1)) * (DMSH_GMEM_MAP_ENTRY / 4) + 6;
    CHECK("a whole-chunk hint retains its full high index", hint[0] >= DMSH_GMEM_MAP_ENTRIES && hint[0] < entries && hint[1] == chunk);
    CHECK("a high-index hinted load reaches its pool", probe((uint64_t)(uintptr_t)hinted + 4096) == 0xabcdef01u);
    uint32_t saved_tag = hint[1], saved_index = hint[0]; hint[1] ^= DMSH_GMEM_MAP_ENTRIES;
    CHECK("a colliding hint tag falls back to search", probe((uint64_t)(uintptr_t)hinted + 4096) == 0xabcdef01u);
    hint[1] = saved_tag; hint[0] = entries + 1;
    CHECK("an out-of-range hint index falls back to search", probe((uint64_t)(uintptr_t)hinted + 4096) == 0xabcdef01u);
    hint[0] = saved_index;
    CHECK("a large pool", probe((uint64_t)(uintptr_t)large + 40 * MB + 12) == 0xb16b00b5u);
    CHECK("an address in no pool reads 0", probe((uint64_t)(uintptr_t)many + PG + 8) == 0);
    // The dynamic table's last pool must be writable too: a fixed 4096-bit log would corrupt memory here.
    id<MTLLibrary> wlib = [g_dev newLibraryWithURL:[NSURL fileURLWithPath:@(argv[2])] error:&error];
    id<MTLComputePipelineState> wpso = wlib ? [g_dev newComputePipelineStateWithFunction:[wlib newFunctionWithName:@"main0"] error:&error] : nil;
    CHECK("raw write pipeline", wpso != nil); if (!wpso) return 1;
    id<MTLBuffer> bitmap = [g_dev newBufferWithLength:gml_bytes(map) options:MTLResourceStorageModeShared];
    memset(bitmap.contents, 0, bitmap.length); res_add(bitmap); res_commit();
    id<MTLBuffer> wa = [g_dev newBufferWithLength:24 options:MTLResourceStorageModeShared];
    uint64_t *wb = wa.contents; wb[0] = slot.gpuAddress; wb[1] = map.gpuAddress; wb[2] = bitmap.gpuAddress;
    uint64_t target = (uint64_t)(uintptr_t)(many + (size_t)(MANY - 1) * 2 * PG); memcpy(slot.contents, &target, 8);
    id<MTLCommandBuffer> cbw = q_cb(); id<MTLComputeCommandEncoder> we = [cbw computeCommandEncoder];
    [we setComputePipelineState:wpso]; [we setBuffer:wa offset:0 atIndex:0];
    [we useResource:slot usage:MTLResourceUsageRead]; [we useResource:map usage:MTLResourceUsageRead]; [we useResource:bitmap usage:MTLResourceUsageRead | MTLResourceUsageWrite];
    [we dispatchThreadgroups:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(32, 1, 1)]; [we endEncoding]; [cbw commit]; [cbw waitUntilCompleted];
    CHECK("raw write completed", cbw.status == MTLCommandBufferStatusCompleted);
    CHECK("raw write reaches the pool past 4095", *(const uint32_t *)(uintptr_t)target == 0x13579bdfu);
    unsigned written = 0; const uint32_t *bits = bitmap.contents;
    for (unsigned i = DMSH_GMEM_MAP_ENTRIES; i < entries; i++) if (bits[i / 32] & (1u << (i % 32))) written++;
    CHECK("the write marks a bitmap bit past 4095", written == 1);
    gml_read(bitmap, map, -1, 0);
    CHECK("the high write bit resolves against its bound map", g_gml_n == 1 && g_gml_lo[0] == target);
    printf("t_gmem_raw: %d checks, %d failed (%u table entries, %d probes)\n", checks, failed, entries, n + 2);
    return failed != 0;
}}
