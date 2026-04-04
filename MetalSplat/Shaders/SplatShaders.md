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

---

## Step 2 — Project to Screen (EWA Splatting)

A 3D Gaussian projects to a 2D Gaussian on screen — but the shape changes due to
perspective. The math uses the **Jacobian J** of the perspective projection at the
splat's view-space position `t`:

```
J = | fx/tz       0    -fx·tx/tz² |
    |  0       fy/tz  -fy·ty/tz² |
```

`fx`, `fy` are focal lengths (from the projection matrix). `J` tells us how a small
displacement in view space maps to a displacement in screen pixels.

Combined with `W` (the rotation part of the view matrix):

```
T = J · W            (2×3 matrix)
Σ2D = T · Σ3D · Tᵀ  (2×2 matrix)
```

`Σ2D` is the screen-space covariance — a 2×2 matrix describing the projected ellipse
in pixel units. A small epsilon (0.3) is added to the diagonal to prevent degenerate
zero-area splats.

---

## Step 3 — Eigen-decompose Σ2D

`Σ2D` is a 2×2 symmetric matrix. Its eigenvectors give the **directions** of the
ellipse axes; eigenvalues give the **size²** of each axis.

For a 2×2 symmetric matrix `[[a, c], [c, b]]`:

```
mid  = (a + b) / 2
disc = sqrt(mid² - (ab - c²))

λ₁ = mid + disc    ← major axis variance (pixels²)
λ₂ = mid - disc    ← minor axis variance (pixels²)
```

The major eigenvector is `normalize(c, λ₁ - a)`, the minor is perpendicular to it.

---

## Step 4 — Position the Quad Corner

The **3-sigma radius** covers ~99.7% of the Gaussian's mass:

```
r₁ = 3√λ₁    (major axis, pixels)
r₂ = 3√λ₂    (minor axis, pixels)
```

Each of the 6 vertices gets a `corner` value in `[-1,+1]²`. The screen-space offset is:

```
offset_pixels = corner.x · r₁ · axis₁ + corner.y · r₂ · axis₂
```

Converted to NDC (divide by viewport/2) and added to the projected splat center.

---

## Step 5 — Fragment Shader

The `uv` passed to the fragment shader is the `corner` value — it ranges `[-1,+1]`
across the quad. The Gaussian evaluated at `uv`:

```
gauss = exp(-0.5 · |uv|²)
```

| Location | `\|uv\|` | gauss |
|----------|--------|-------|
| Center   | 0      | 1.0   |
| 1σ edge  | 1      | 0.61  |
| Quad corner | √2  | 0.37  |

The final output is pre-multiplied alpha: `color.rgb * opacity * gauss`.
