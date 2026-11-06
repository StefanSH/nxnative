// The NVN mesh argument is produced on the GPU, not in CPU-visible command
// memory at record time. Check the real replay converter's grid and base.
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }


static int checks, failed;
#define CHECK(label, condition) do { checks++; if (!(condition)) { failed++; fprintf(stderr, "FAIL: %s (line %d)\n", label, __LINE__); } } while (0)

// Apple8's mesh path must draw with the converted GPU arguments too. Exercise
// both encoder APIs without inferring support from a later GPU-family number.
// The mesh shader also reads the converted first task at the production slot.
static void raster_mesh(id<MTLBuffer> converted, size_t offset, size_t first_offset, int metal4, int indirect, int zero) {
    NSError *error = nil;
    NSString *source = @"#include <metal_stdlib>\nusing namespace metal;\n"
        "struct V { float4 position [[position]]; };\n"
        "using T = mesh<V, void, 3, 1, topology::triangle>;\n"
        "[[mesh]] void ms(T out, constant uint& first [[buffer(29)]]) {\n"
        " if (first != 17) { out.set_primitive_count(0); return; }\n"
        " out.set_primitive_count(1);\n"
        " out.set_vertex(0, V{float4(-1,-1,0.5,1)}); out.set_index(0,0);\n"
        " out.set_vertex(1, V{float4(3,-1,0.5,1)}); out.set_index(1,1);\n"
        " out.set_vertex(2, V{float4(-1,3,0.5,1)}); out.set_index(2,2);\n"
        "}\nfragment float4 fs() { return float4(1,0,1,1); }\n";
    id<MTLLibrary> library = [g_dev newLibraryWithSource:source options:nil error:&error];
    CHECK("mesh raster library", library != nil);
    if (!library) { fprintf(stderr, "%s\n", error.description.UTF8String); return; }
    MTLMeshRenderPipelineDescriptor *pd = [MTLMeshRenderPipelineDescriptor new];
    pd.meshFunction = [library newFunctionWithName:@"ms"]; pd.fragmentFunction = [library newFunctionWithName:@"fs"];
    CHECK("mesh and fragment functions", pd.meshFunction && pd.fragmentFunction);
    if (!pd.meshFunction || !pd.fragmentFunction) return;
    pd.maxTotalThreadsPerMeshThreadgroup = 1; pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
    id<MTLRenderPipelineState> pipeline = [g_dev newRenderPipelineStateWithMeshDescriptor:pd options:MTLPipelineOptionNone reflection:nil error:&error];
    CHECK("mesh raster pipeline", pipeline != nil);
    if (!pipeline) { fprintf(stderr, "%s\n", error.description.UTF8String); return; }
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];
    td.storageMode = MTLStorageModeShared; td.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> target = [g_dev newTextureWithDescriptor:td];
    CHECK("mesh raster target", target != nil); if (!target) return;
    MTLSize grid = MTLSizeMake(zero ? 0 : 3, 1, 1), one = MTLSizeMake(1, 1, 1);
    if (metal4) {
        MTLResidencySetDescriptor *rd = [MTLResidencySetDescriptor new]; rd.initialCapacity = 2;
        id<MTLResidencySet> resident = [g_dev newResidencySetWithDescriptor:rd error:&error];
        MTL4CommandQueueDescriptor *qd = [MTL4CommandQueueDescriptor new];
        id<MTL4CommandQueue> queue = [g_dev newMTL4CommandQueueWithDescriptor:qd error:&error];
        id<MTL4CommandAllocator> allocator = [g_dev newCommandAllocator];
        id<MTL4CommandBuffer> cb = [g_dev newCommandBuffer];
        MTL4ArgumentTableDescriptor *ad = [MTL4ArgumentTableDescriptor new]; ad.maxBufferBindCount = DMSH_MESH_FIRST_SLOT + 1;
        id<MTL4ArgumentTable> arguments = [g_dev newArgumentTableWithDescriptor:ad error:&error];
        CHECK("Metal4 raster resources", resident && queue && allocator && cb && arguments);
        if (!resident || !queue || !allocator || !cb || !arguments) return;
        [resident addAllocation:target]; [resident addAllocation:converted]; [resident commit]; [queue addResidencySet:resident];
        [arguments setAddress:converted.gpuAddress + first_offset atIndex:DMSH_MESH_FIRST_SLOT];
        [cb beginCommandBufferWithAllocator:allocator];
        MTL4RenderPassDescriptor *rp = [MTL4RenderPassDescriptor new]; rp.colorAttachments[0].texture = target;
        rp.colorAttachments[0].loadAction = MTLLoadActionClear; rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
        id<MTL4RenderCommandEncoder> encoder = [cb renderCommandEncoderWithDescriptor:rp];
        CHECK("Metal4 raster encoder", encoder != nil); if (!encoder) return;
        [encoder setRenderPipelineState:pipeline]; [encoder setViewport:(MTLViewport){0,0,8,8,0,1}];
        [encoder setArgumentTable:arguments atStages:MTLRenderStageMesh];
        if (indirect) [encoder drawMeshThreadgroupsWithIndirectBuffer:converted.gpuAddress + offset threadsPerObjectThreadgroup:one threadsPerMeshThreadgroup:one];
        else [encoder drawMeshThreadgroups:grid threadsPerObjectThreadgroup:one threadsPerMeshThreadgroup:one];
        [encoder endEncoding]; [cb endCommandBuffer];
        dispatch_semaphore_t done = dispatch_semaphore_create(0); __block NSError *gpu_error = nil;
        MTL4CommitOptions *options = [MTL4CommitOptions new];
        [options addFeedbackHandler:^(id<MTL4CommitFeedback> feedback) { gpu_error = feedback.error; dispatch_semaphore_signal(done); }];
        [queue commit:&cb count:1 options:options];
        long timed_out = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
        CHECK("Metal4 raster completed", !timed_out && !gpu_error);
        if (timed_out || gpu_error) { fprintf(stderr, "Metal4 raster timeout=%ld error=%s\n", timed_out, gpu_error.description.UTF8String); return; }
    } else {
        id<MTLCommandQueue> queue = [g_dev newCommandQueue]; id<MTLCommandBuffer> cb = [queue commandBuffer];
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor new]; rp.colorAttachments[0].texture = target;
        rp.colorAttachments[0].loadAction = MTLLoadActionClear; rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
        id<MTLRenderCommandEncoder> encoder = [cb renderCommandEncoderWithDescriptor:rp];
        CHECK("classic raster resources", queue && cb && encoder); if (!queue || !cb || !encoder) return;
        [encoder setRenderPipelineState:pipeline]; [encoder setViewport:(MTLViewport){0,0,8,8,0,1}];
        [encoder setMeshBuffer:converted offset:first_offset atIndex:DMSH_MESH_FIRST_SLOT];
        if (indirect) [encoder drawMeshThreadgroupsWithIndirectBuffer:converted indirectBufferOffset:offset threadsPerObjectThreadgroup:one threadsPerMeshThreadgroup:one];
        else [encoder drawMeshThreadgroups:grid threadsPerObjectThreadgroup:one threadsPerMeshThreadgroup:one];
        [encoder endEncoding]; [cb commit]; [cb waitUntilCompleted];
        CHECK("classic raster completed", cb.status == MTLCommandBufferStatusCompleted && !cb.error);
        if (cb.status != MTLCommandBufferStatusCompleted || cb.error) return;
    }
    uint32_t pixels[64]; [target getBytes:pixels bytesPerRow:8 * sizeof(uint32_t) fromRegion:MTLRegionMake2D(0,0,8,8) mipmapLevel:0];
    unsigned matching = 0; uint32_t expected = zero ? 0xff000000u : 0xffff00ffu;
    for (unsigned i = 0; i < 64; i++) matching += pixels[i] == expected;
    printf("mesh raster %s %s %s: %u/64 expected pixels\n", metal4 ? "Metal4" : "classic", indirect ? "indirect" : "direct", zero ? "zero" : "nonzero", matching);
    CHECK("converted mesh arguments produce the expected pixels", matching == 64);
}

int main(void) { @autoreleasepool {
    mtl_init(); size_t bytes = (size_t)getpagesize();
    uint32_t *guest = mmap(NULL, bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    assert(guest != MAP_FAILED); mtl_pool_add(guest, bytes);
    id<MTLBuffer> seed = [g_dev newBufferWithLength:16 options:MTLResourceStorageModeShared];
    const uint32_t input[] = {3, 17, 0, 23}; memcpy(seed.contents, input, sizeof input); res_add(seed);
    void *buffer; uint64_t offset;
    assert(mtl_addr((uintptr_t)guest, sizeof input, &buffer, &offset));
    mtl_sub_begin();
    enc_b_copy_buffer(blit(), seed, 0, (__bridge id<MTLBuffer>)buffer, offset, sizeof input);
    const p_draw draw_3 = {.prim=DM_PRIM_MESH_TASKS, .ind=(uintptr_t)guest};
    const p_draw draw_0 = {.prim=DM_PRIM_MESH_TASKS, .ind=(uintptr_t)(guest + 2)};
    ixc_run(&draw_3, NULL); ixc_run(&draw_0, NULL);
    const ixc_ent *a = ixc_find(&draw_3, NULL), *b = ixc_find(&draw_0, NULL);
    assert(a && a->args && b && b->args && guest[0] == 0);
    id<MTLBuffer> converted = g_cur_arena->buf;
    size_t ao = (size_t)(a->args - converted.gpuAddress), bo = (size_t)(b->args - converted.gpuAddress);
    assert(ao + 20 <= converted.length && bo + 20 <= converted.length);
    // A deferred write to a third argument must be landed before snapshotting
    // the conversion epoch, so the GPU result is still found by the draw.
    const p_draw draw_queued = {.prim=DM_PRIM_MESH_TASKS, .ind=(uintptr_t)(guest + 4)};
    g_ubd[g_nubd++] = (ubd_ent){draw_queued.ind, draw_queued.ind + 8, seed.gpuAddress, 0, seed};
    ixc_run(&draw_queued, NULL);
    const ixc_ent *queued = ixc_find(&draw_queued, NULL);
    assert(queued && queued->args && !g_nubd);
    size_t qo = (size_t)(queued->args - converted.gpuAddress);
    assert(qo + 20 <= converted.length);
    mtl_sub_commit(); mtl_drain();
    const uint32_t expected_3[] = {3, 1, 1, 0, 17}, expected_0[] = {0, 1, 1, 0, 23};
    assert(!memcmp((const uint8_t *)converted.contents + ao, expected_3, sizeof expected_3));
    assert(!memcmp((const uint8_t *)converted.contents + bo, expected_0, sizeof expected_0));
    assert(!memcmp((const uint8_t *)converted.contents + qo, expected_3, sizeof expected_3));
    for (int metal4 = 0; metal4 < 2; metal4++) for (int indirect = 0; indirect < 2; indirect++) {
        raster_mesh(converted, ao, ao + 16, metal4, indirect, 0);
        // A spurious zero-grid dispatch must paint magenta and fail: keep a valid first task, independent of the zero-work record's base of 23.
        raster_mesh(converted, bo, ao + 16, metal4, indirect, 1);
    }
    res_remove(seed); mtl_pool_del(guest); mtl_drain(); munmap(guest, bytes);
    printf("GPU-written mesh arguments: %d raster checks, %d failed\n", checks, failed);
} return failed != 0; }
