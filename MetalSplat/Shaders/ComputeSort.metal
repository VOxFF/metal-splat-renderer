//  ComputeSort.metal
//  Bitonic sort for Gaussian splat back-to-front ordering.
//
//  Two kernels:
//    computeDepthKeys  — resets indices to identity and writes squared camera
//                        distance per splat into keysBuffer (must run every frame
//                        before bitonicSortStep, because the sort scrambles both
//                        buffers and the mapping must be rebuilt each frame)
//    bitonicSortStep   — one (k, j) pass of a bitonic sort over (keys, indices)

#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

// ------------------------------------------------------------------ //
// Kernel 1: reset indices + compute squared distance keys
//
// Dispatched over paddedCount threads every frame.
// Real slots  [0, splatCount):  key = dist², index = i
// Padding slots [splatCount, paddedCount): key = -1, index = 0
//   (key -1 < any dist² → padding sorts to end in descending order)
// ------------------------------------------------------------------ //

kernel void computeDepthKeys(
    constant GaussianSplat* splats      [[ buffer(0) ]],
    device   float*         keys        [[ buffer(1) ]],
    device   uint*          indices     [[ buffer(2) ]],
    constant float3&        camPos      [[ buffer(3) ]],
    constant float3&        camForward  [[ buffer(4) ]],
    constant uint&          splatCount  [[ buffer(5) ]],
    constant uint&          paddedCount [[ buffer(6) ]],
    uint gid [[ thread_position_in_grid ]])
{
    if (gid >= paddedCount) return;

    if (gid < splatCount) {
        float3 delta = splats[gid].positionAndOpacity.xyz - camPos;
        // View-space depth: splats in the same visual plane share the same key,
        // eliminating ordering flips between neighbouring grid layers.
        keys[gid]    = dot(delta, camForward);
        indices[gid] = gid;
    } else {
        keys[gid]    = -MAXFLOAT;  // padding sorts to end (descending)
        indices[gid] = 0;
    }
}

// ------------------------------------------------------------------ //
// Kernel 2: one step of bitonic sort
//
// Dispatched once per (k, j) pair:
//   for k in [2, 4 … paddedCount]:
//     for j in [k/2, k/4 … 1]:
//       dispatch bitonicSortStep(k, j, paddedCount/2 threads)
//
// Descending: larger key (farther splat) at lower index → drawn first.
// ------------------------------------------------------------------ //

struct SortParams {
    uint k;
    uint j;
    uint n;  // paddedCount — full range, one thread per element
};

// Each thread is responsible for one index i in [0, n).
// The XOR partner ixj = i ^ j is always in the same range.
// The guard (ixj <= i) ensures each pair is processed exactly once.
kernel void bitonicSortStep(
    device float*          keys    [[ buffer(0) ]],
    device uint*           indices [[ buffer(1) ]],
    constant SortParams&   p       [[ buffer(2) ]],
    uint gid [[ thread_position_in_grid ]])
{
    if (gid >= p.n) return;

    uint i   = gid;
    uint ixj = i ^ p.j;
    if (ixj <= i) return;

    float ki = keys[i];
    float kj = keys[ixj];

    // ascending bit == 0 → this slot belongs to the "want-larger-first" half
    bool ascending = (i & p.k) == 0;
    bool doSwap    = ascending ? (ki < kj) : (ki > kj);

    if (doSwap) {
        keys[i]      = kj;  keys[ixj]    = ki;
        uint ti      = indices[i];
        indices[i]   = indices[ixj];
        indices[ixj] = ti;
    }
}
