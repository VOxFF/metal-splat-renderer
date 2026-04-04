# Splat Vertex Shader Math

## Goal
Take a 3D Gaussian (an ellipsoid in world space) and figure out what 2D ellipse it
projects to on screen, then position a quad corner on that ellipse's boundary.

---

## Step 1 — 3D Covariance Matrix

A Gaussian splat is an ellipsoid defined by rotation `R` and scale `S`. Its covariance
matrix describes the shape:

```
Σ3D = R · S² · Rᵀ
```

`S` is a diagonal matrix of the splat's half-axes (scale values). `R` comes from the
stored quaternion. The result is a 3×3 matrix encoding how stretched and in which
direction the ellipsoid is.

In code: `RS = R * S`, then `Σ3D = RS * RSᵀ`.

---

## Step 2 — Project to Screen (EWA Splatting)

A 3D Gaussian projects to a 2D Gaussian on screen — but the shape changes due to
perspective. The math uses the **Jacobian J** of the perspective projection at the
splat's view-space position `t`:

```
J = | fx/tz       0    -fx·tx/tz² |
    |  0       fy/tz  -fy·ty/tz² |
```

`fx`, `fy` are focal lengths in pixels: `fx = projection[0][0] · viewport.x / 2`.
`J` tells us how a small displacement in view space maps to a displacement in screen pixels.

Combined with `W` (the rotation part of the view matrix — upper-left 3×3):

```
T = J · W            (2×3 matrix)
Σ2D = T · Σ3D · Tᵀ  (2×2 matrix)
```

**Computing T explicitly** (since Metal's matrix types don't directly give a 2×3):

```
T[:,j] = J · W[:,j]
T0 = J[0]·W[0][0] + J[1]·W[0][1] + J[2]·W[0][2]   // column 0 of T
T1 = J[0]·W[1][0] + J[1]·W[1][1] + J[2]·W[1][2]   // column 1
T2 = J[0]·W[2][0] + J[1]·W[2][1] + J[2]·W[2][2]   // column 2
```

**Computing Σ2D = T · Σ3D · Tᵀ correctly:**

```
A = T · Σ3D:
  col0 = T0·Σ3D[0][0] + T1·Σ3D[1][0] + T2·Σ3D[2][0]
  col1 = T0·Σ3D[0][1] + T1·Σ3D[1][1] + T2·Σ3D[2][1]
  col2 = T0·Σ3D[0][2] + T1·Σ3D[1][2] + T2·Σ3D[2][2]

Σ2D[i,j] = sum_k  A[i,k] · T[j,k]

Ax = (col0.x, col1.x, col2.x)   // row 0 of A
Ay = (col0.y, col1.y, col2.y)   // row 1 of A
Tx = (T0.x,  T1.x,  T2.x)      // row 0 of T
Ty = (T0.y,  T1.y,  T2.y)      // row 1 of T

cov00 = dot(Ax, Tx) + ε         // ε = 0.3 prevents degenerate splats
cov11 = dot(Ay, Ty) + ε
cov01 = dot(Ax, Ty)             // off-diagonal (symmetric)
```

A small epsilon (0.3) is added to the diagonal to prevent degenerate zero-area splats.

---

## Step 3 — Eigen-decompose Σ2D

`Σ2D` is a 2×2 symmetric matrix. Its eigenvectors give the **directions** of the
ellipse axes; eigenvalues give the **size²** of each axis in pixels².

For a 2×2 symmetric matrix `[[cov00, cov01], [cov01, cov11]]`:

```
mid  = (cov00 + cov11) / 2
disc = sqrt(max(0, mid² - (cov00·cov11 - cov01²)))

λ₁ = mid + disc    ← major axis variance (pixels²)
λ₂ = max(0, mid - disc)    ← minor axis variance (pixels²)
```

The major eigenvector direction: `v = (cov01, λ₁ - cov00)`.
If `|v| < ε` (isotropic splat), fall back to `(1, 0)` to avoid normalising a zero vector.

```
axis1 = |v| > 1e-4 ? normalize(v) : float2(1, 0)
axis2 = float2(-axis1.y, axis1.x)
```

---

## Step 4 — Position the Quad Corner

The **3-sigma radius** covers ~99.7% of the Gaussian's mass:

```
rad1 = 3√λ₁    (major axis, pixels)
rad2 = 3√λ₂    (minor axis, pixels)
```

Each of the 6 vertices gets a `corner` value in `[-1,+1]²`. The screen-space offset in
NDC units is:

```
ndcOffset = (corner.x · rad1 · axis1 + corner.y · rad2 · axis2) / (viewport / 2)
```

**Output must stay in clip space** (not NDC) so the GPU clips and interpolates correctly:

```
outPos.xy = clipCenter.xy + ndcOffset · clipCenter.w
outPos.w  = clipCenter.w
```

Multiplying by `clipCenter.w` converts the NDC offset back to clip-space units.
After the hardware perspective divide (`÷ w`), the vertex lands at `ndc_center + ndcOffset`. ✓

---

## Step 5 — Fragment Shader

The `uv` passed to the fragment shader is the `corner` value — it ranges `[-1,+1]`
across the quad. Since `±1` corresponds to the **3σ edge**, the Gaussian must be scaled
accordingly:

```
gauss = exp(-0.5 · 9 · |uv|²)     // 9 = 3²
```

| Location    | `\|uv\|` | gauss        |
|-------------|--------|--------------|
| Center      | 0      | 1.0          |
| 1σ edge     | 0.333  | 0.61         |
| 3σ quad edge| 1.0    | exp(-4.5) ≈ 0.011 |
| Quad corner | √2     | exp(-9) ≈ 0.0001 |

The final output is pre-multiplied alpha: `color.rgb * opacity * gauss`.
Fragments below `1/255` alpha are discarded.

---

## GPU Struct Layout Note

The `GaussianSplat` struct uses `float4` for every field group to avoid implicit
alignment padding. Using `vector_float3` (16-byte aligned) next to a `float` would
cause the compiler to insert 12 bytes of padding before the next `float4`, making the
Metal struct 112 bytes while the Swift buffer holds 64-byte entries — reading garbage.

```c
typedef struct {
    float4 positionAndOpacity;  // xyz = position, w = opacity
    float4 rotation;            // xyzw quaternion
    float4 scaleAndPad;         // xyz = scale,    w = unused
    float4 colorAndPad;         // xyz = RGB,       w = unused
} GaussianSplat;  // exactly 64 bytes, no implicit padding
```
