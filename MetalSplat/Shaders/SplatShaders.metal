#include <metal_stdlib>
#include "ShaderTypes.h"

using namespace metal;

// Quad corner offsets in splat-local [-1,+1] space — two triangles per splat
constant float2 quadCorners[6] = {
    {-1, -1}, {+1, -1}, {-1, +1},
    {-1, +1}, {+1, -1}, {+1, +1}
};

struct SplatVaryings {
    float4 position [[position]];
    float2 uv;        // [-1,+1] within the quad
    float4 color;     // rgb + pre-multiplied alpha
};

vertex SplatVaryings splatVertexShader(
    uint                     vid           [[ vertex_id ]],
    constant GaussianSplat*  splats        [[ buffer(BufferIndexSplats) ]],
    constant uint*           sortedIndices [[ buffer(BufferIndexSplatIndices) ]],
    constant SplatUniforms&  u             [[ buffer(BufferIndexSplatUniforms) ]])
{
    uint splatIdx  = sortedIndices[vid / 6];
    uint cornerIdx = vid % 6;

    GaussianSplat s = splats[splatIdx];
    float2 corner   = quadCorners[cornerIdx];

    // --- Build 3x3 covariance in world space: Sigma = R * S^2 * R^T ---

    // Quaternion (xyzw) → rotation matrix
    float4 q = normalize(float4(s.rotation));
    float x = q.x, y = q.y, z = q.z, w = q.w;
    float3x3 R = float3x3(
        float3(1 - 2*(y*y + z*z),     2*(x*y + w*z),     2*(x*z - w*y)),
        float3(    2*(x*y - w*z), 1 - 2*(x*x + z*z),     2*(y*z + w*x)),
        float3(    2*(x*z + w*y),     2*(y*z - w*x), 1 - 2*(x*x + y*y))
    );

    float3 sc = s.scale;
    float3x3 S = float3x3(
        float3(sc.x, 0,    0),
        float3(0,    sc.y, 0),
        float3(0,    0,    sc.z)
    );

    float3x3 RS   = R * S;
    float3x3 Sig3 = RS * transpose(RS);  // 3D covariance

    // --- Project covariance to 2D screen space (EWA splatting) ---

    float4 posView = u.viewMatrix * u.modelMatrix * float4(s.position, 1.0);
    float3 t = posView.xyz;

    // Focal lengths from projection matrix
    float fx = u.projectionMatrix[0][0] * u.viewportSize.x * 0.5;
    float fy = u.projectionMatrix[1][1] * u.viewportSize.y * 0.5;

    // 2x3 Jacobian of the perspective projection at t
    float3x2 J = float3x2(
        float2(fx / t.z,          0),
        float2(0,          fy / t.z),
        float2(-fx * t.x / (t.z * t.z), -fy * t.y / (t.z * t.z))
    );

    // 3x3 rotation part of the view matrix
    float3x3 W = float3x3(
        u.viewMatrix[0].xyz,
        u.viewMatrix[1].xyz,
        u.viewMatrix[2].xyz
    );

    // 2x2 screen-space covariance: Sigma2D = J * W * Sig3 * (J * W)^T
    // Add a small epsilon on the diagonal to prevent degenerate splats
    float3x2 JW   = J * W;  // wait, need (2x3) * (3x3) — use transpose trick
    // Note: metal float3x2 is 3 columns of float2, i.e. a 2-row x 3-col matrix.
    // So JW = J (2x3) * W (3x3) — we compute as W^T * J^T then transpose.
    float2x2 Sig2 = float2x2(
        float2(
            JW[0].x * (Sig3[0][0]*JW[0].x + Sig3[1][0]*JW[1].x + Sig3[2][0]*JW[2].x) +
            JW[1].x * (Sig3[0][0]*JW[0].y + Sig3[1][0]*JW[1].y + Sig3[2][0]*JW[2].y),   // [0][0] wrong, redo below
            0),
        float2(0, 0)
    );

    // Cleaner explicit 2x2 computation:
    // T = J * W  (stored col-major as float3x2 where each column is a float2)
    // T[0] = J*W[:,0], T[1] = J*W[:,1], T[2] = J*W[:,2]
    float2 T0 = J[0]*W[0][0] + J[1]*W[0][1] + J[2]*W[0][2];
    float2 T1 = J[0]*W[1][0] + J[1]*W[1][1] + J[2]*W[1][2];
    float2 T2 = J[0]*W[2][0] + J[1]*W[2][1] + J[2]*W[2][2];

    // Sigma2D = T * Sig3 * T^T  (2x2)
    float2 col0 = T0*Sig3[0][0] + T1*Sig3[1][0] + T2*Sig3[2][0];
    float2 col1 = T0*Sig3[0][1] + T1*Sig3[1][1] + T2*Sig3[2][1];
    float2 col2 = T0*Sig3[0][2] + T1*Sig3[1][2] + T2*Sig3[2][2];

    float cov00 = dot(col0, T0) + 0.3;  // epsilon on diagonal
    float cov11 = dot(col2, T2) + 0.3;
    float cov01 = dot(col1, T1);  // off-diagonal (symmetric)

    // --- Eigendecompose 2x2 covariance to get ellipse axes ---

    float mid   = 0.5 * (cov00 + cov11);
    float disc  = sqrt(max(0.0, mid*mid - (cov00*cov11 - cov01*cov01)));
    float lam1  = mid + disc;  // major eigenvalue (pixels²)
    float lam2  = mid - disc;  // minor eigenvalue (pixels²)

    float2 axis1 = normalize(float2(cov01, lam1 - cov00));
    float2 axis2 = float2(-axis1.y, axis1.x);

    // 3-sigma coverage radius in pixels
    float r1 = 3.0 * sqrt(lam1);
    float r2 = 3.0 * sqrt(lam2);

    // --- Position the quad corner in NDC ---

    float4 clipCenter = u.projectionMatrix * posView;
    float2 ndc = clipCenter.xy / clipCenter.w;

    // Offset in NDC: convert pixel radius to NDC units
    float2 offset = (corner.x * r1 * axis1 + corner.y * r2 * axis2) /
                    (u.viewportSize * 0.5);

    SplatVaryings out;
    out.position = float4(ndc + offset, clipCenter.z / clipCenter.w, 1.0);
    out.uv       = corner;

    float alpha = s.opacity;
    out.color   = float4(s.color * alpha, alpha);  // pre-multiplied

    return out;
}

fragment float4 splatFragmentShader(SplatVaryings in [[stage_in]])
{
    // Gaussian falloff in splat-local UV space
    float r2    = dot(in.uv, in.uv);
    float gauss = exp(-0.5 * r2);

    // Modulate pre-multiplied color by Gaussian weight
    float4 col = in.color * gauss;

    // Discard nearly-transparent fragments for performance
    if (col.a < 1.0 / 255.0) discard_fragment();

    return col;
}
