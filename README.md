# Playing with Metal Gaussian Splats

A Metal renderer for 3D Gaussian Splatting (3DGS) on macOS, built as a learning project.

## What it does

Renders Gaussian splats alongside traditional mesh geometry in a shared scene graph. Each splat is a 3D Gaussian ellipsoid projected to a 2D screen-space ellipse using EWA splatting, sorted back-to-front per frame for correct alpha compositing.

## Architecture

- **Scene graph** — `Node` / `Transform` hierarchy with breadth-first traversal
- **Geometry protocol** — `MeshGeometry` (indexed mesh) and `SplatGeometry` (gaussian splats) share a common `draw(encoder:context:)` interface via `RenderContext`
- **Render state cache** — pipeline states keyed by material + vertex descriptor, built once at load time
- **Two-pass rendering** — opaque mesh nodes first (depth write), splat nodes second (no depth write, alpha blend)

## Splat rendering pipeline

1. **GPU sort** — splats sorted back-to-front by squared distance to camera each frame on the GPU
2. **Vertex shader** — EWA projection: builds 3D covariance from quaternion + scale, projects to 2D screen-space ellipse via perspective Jacobian, eigendecomposes to get ellipse axes and radii; screen-space radius clamped to prevent nearby splats from covering the view
3. **Fragment shader** — Gaussian falloff `exp(-4.5 * |uv|²)` where `uv = ±1` corresponds to the 3σ quad edge; pre-multiplied alpha output

## Current state

- PLY loader for real 3DGS scenes (binary little-endian format)
- Orbit / pan / dolly camera controls
- Live sliders for zoom speed and minimum dolly distance

## Controls

| Gesture | Action |
|---------|--------|
| Drag | Orbit |
| Middle drag | Pan |
| Scroll | Dolly |

## References

- [3D Gaussian Splatting for Real-Time Radiance Field Rendering](https://repo-sam.inria.fr/fungraph/3d-gaussian-splatting/) — Kerbl et al., SIGGRAPH 2023
- [EWA Splatting](https://www.cs.umd.edu/~zwicker/publications/EWASplatting-TVCG02.pdf) — Zwicker et al., 2002
- [`SplatShaders.md`](MetalSplat/Shaders/SplatShaders.md) — vertex shader math walkthrough
