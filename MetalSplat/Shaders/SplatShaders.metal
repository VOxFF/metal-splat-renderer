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
    float2 uv;        // [-1,+1] maps to ±3σ on the ellipse axes
    float4 color;     // rgb + pre-multiplied alpha
};

vertex SplatVaryings splatVertexShader(
    uint                          vid           [[ vertex_id ]],
    device const GaussianSplat*   splats        [[ buffer(BufferIndexSplats) ]],
    device const uint*            sortedIndices [[ buffer(BufferIndexSplatIndices) ]],
    constant SplatUniforms&       u             [[ buffer(BufferIndexSplatUniforms) ]])
{
    uint splatIdx  = sortedIndices[vid / 6];
    uint cornerIdx = vid % 6;

    GaussianSplat s = splats[splatIdx];
    float2 corner   = quadCorners[cornerIdx];

    float3 sPosition = s.positionAndOpacity.xyz;
    float  sOpacity  = s.positionAndOpacity.w;
    float3 sScale    = s.scaleAndPad.xyz;
    float3 sColor    = s.colorAndPad.xyz;

    // --- Build 3x3 covariance in world space: Sigma = R * S^2 * R^T ---

    // Quaternion (xyzw) → rotation matrix (column-major)
    float4 q = normalize(s.rotation);
    float x = q.x, y = q.y, z = q.z, w = q.w;
    float3x3 R = float3x3(
        float3(1 - 2*(y*y + z*z),     2*(x*y + w*z),     2*(x*z - w*y)),
        float3(    2*(x*y - w*z), 1 - 2*(x*x + z*z),     2*(y*z + w*x)),
        float3(    2*(x*z + w*y),     2*(y*z - w*x), 1 - 2*(x*x + y*y))
    );

    float3x3 S = float3x3(
        float3(sScale.x, 0,       0),
        float3(0,        sScale.y, 0),
        float3(0,        0,        sScale.z)
    );

    float3x3 RS   = R * S;
    float3x3 Sig3 = RS * transpose(RS);  // 3D covariance

    // --- Project covariance to 2D screen space (EWA splatting) ---

    float4 posView = u.viewMatrix * u.modelMatrix * float4(sPosition, 1.0);
    float3 t = posView.xyz;

    // Reject splats behind or too near the camera
    SplatVaryings out;
    if (t.z > -0.1) {
        out.position = float4(0, 0, 0, 0);
        out.uv       = 0;
        out.color    = 0;
        return out;
    }

    // Focal lengths in pixels
    float fx = u.projectionMatrix[0][0] * u.viewportSize.x * 0.5;
    float fy = u.projectionMatrix[1][1] * u.viewportSize.y * 0.5;

    // 2x3 Jacobian of perspective projection at t (columns are float2)
    float3x2 J = float3x2(
        float2(fx / t.z,          0),
        float2(0,          fy / t.z),
        float2(-fx * t.x / (t.z * t.z), -fy * t.y / (t.z * t.z))
    );

    // Upper-left 3x3 rotation from view matrix
    float3x3 W = float3x3(
        u.viewMatrix[0].xyz,
        u.viewMatrix[1].xyz,
        u.viewMatrix[2].xyz
    );

    // T = J * W  (2x3, as three float2 columns)
    float2 T0 = J[0]*W[0][0] + J[1]*W[0][1] + J[2]*W[0][2];
    float2 T1 = J[0]*W[1][0] + J[1]*W[1][1] + J[2]*W[1][2];
    float2 T2 = J[0]*W[2][0] + J[1]*W[2][1] + J[2]*W[2][2];

    // A = T * Sig3
    float2 col0 = T0*Sig3[0][0] + T1*Sig3[1][0] + T2*Sig3[2][0];
    float2 col1 = T0*Sig3[0][1] + T1*Sig3[1][1] + T2*Sig3[2][1];
    float2 col2 = T0*Sig3[0][2] + T1*Sig3[1][2] + T2*Sig3[2][2];

    // Sigma2D = A * T^T  (Sigma2D[i,j] = sum_k A[i,k] * T[j,k])
    float3 Ax = float3(col0.x, col1.x, col2.x);
    float3 Ay = float3(col0.y, col1.y, col2.y);
    float3 Tx = float3(T0.x, T1.x, T2.x);
    float3 Ty = float3(T0.y, T1.y, T2.y);

    float cov00 = dot(Ax, Tx) + 0.3;  // epsilon prevents degenerate splats
    float cov11 = dot(Ay, Ty) + 0.3;
    float cov01 = dot(Ax, Ty);

    // --- Eigendecompose 2x2 covariance ---

    float mid  = 0.5 * (cov00 + cov11);
    float disc = sqrt(max(0.0, mid*mid - (cov00*cov11 - cov01*cov01)));
    float lam1 = mid + disc;
    float lam2 = max(0.0, mid - disc);

    // Major axis direction; fall back to x-axis for isotropic splats
    float2 ev = float2(cov01, lam1 - cov00);
    float2 axis1 = (length(ev) > 1e-4) ? normalize(ev) : float2(1.0, 0.0);
    float2 axis2 = float2(-axis1.y, axis1.x);

    // 3-sigma radii in pixels — clamp to prevent nearby splats blowing up to full screen
    float rad1 = min(3.0 * sqrt(lam1), 256.0);
    float rad2 = min(3.0 * sqrt(lam2), 256.0);

    // --- Build clip-space output position ---

    float4 clipCenter = u.projectionMatrix * posView;

    // Pixel offset → NDC offset → clip-space offset (multiply by w to stay in clip space)
    float2 ndcOffset = (corner.x * rad1 * axis1 + corner.y * rad2 * axis2)
                       / (u.viewportSize * 0.5);
    float4 outPos  = clipCenter;
    outPos.xy     += ndcOffset * clipCenter.w;

    outPos.x     = -outPos.x;  // flip horizontally so scene is not mirrored
    out.position = outPos;
    out.uv       = corner;  // ±1 corresponds to ±3σ

    out.color    = float4(sColor * sOpacity, sOpacity);  // pre-multiplied alpha

    return out;
}

fragment float4 splatFragmentShader(SplatVaryings in [[stage_in]])
{
    // uv=±1 is the 3σ quad edge, so scale exponent by 9 (= 3²)
    float d2    = dot(in.uv, in.uv);
    float gauss = exp(-0.5 * 9.0 * d2);

    float4 col = in.color * gauss;
    if (col.a < 1.0 / 255.0) discard_fragment();
    return col;
}
