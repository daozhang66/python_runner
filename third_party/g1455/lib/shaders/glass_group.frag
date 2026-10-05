// The package's glass, drawn for a *blend group*: N shapes fused into one
// silhouette by one draw.
//
// **Why it is a second binary rather than a mode of `glass_surface.frag`.** B5
// measured that adding a path to a runtime effect reprices every mode already
// in it by 52-62%, and the single surface is the overwhelmingly common case —
// a loop and a uniform array charged to every panel on every screen would be
// the whole shader's budget (9% of the addition over the floor, D63) spent on
// a feature most screens do not use. The two programs pay for that separation
// with an obligation instead: at `uCount = 1` this one must reproduce
// `glass_surface.frag` **exactly**, and `test/glass/glass_group_test.dart`
// renders the same geometry through both and requires zero differing pixels.
// That is the same arrangement `glass_preview.frag` is under, for the same
// reason: two binaries drifting apart would ship optics nobody graded.
//
// **Why one draw and not N.** The bridge between two fused shapes belongs to
// neither of them — there is no fragment of either surface's own box where it
// lives — so a group that let its members draw themselves could not draw it at
// all. One draw over the group's box, one distance field, one silhouette.
// The price is the dead area of that box: fragments outside every shape are
// shaded and discarded by coverage. Named rather than hidden, because it is the
// quantity a group trades against the fragmentation excess it saves (D26).
//
// **The field is a polynomial smooth minimum, and its gradient is exact.**
// `smin(a, b, k) = min(a, b) - h^2*k/4` with `h = max(k - |a-b|, 0)/k`, whose
// partials are `1 - h/2` towards the nearer shape and `h/2` towards the other
// — a convex combination, so the fused normal is a `mix` of the members' own
// normals and needs no derivative. It is deliberately **not** renormalised: the
// field's gradient really is shorter than one in the saddle, the surface really
// is flatter there, and a renormalised vector would refract the bridge as hard
// as a rim. At the exact centre of a symmetric bridge the two normals cancel
// and the gradient is zero, which is what the field does there — it is a
// critical point.
//
// `smin` is not associative, so the fold order is the order of the uniforms and
// the caller keeps it stable. Two orders differ only in the saddle and only in
// the last code value or so, but "only a little, and differently every frame"
// is the description of a shimmer.
//
// M3 warned that `smin` needs *real* distances — it mixes two fields by their
// values, so an error in either moves the bridge, and the bridge lives where
// both shapes are far from their own contours, which is where approximations
// are worst. The single-Newton estimator invents bridges up to 81 px wide
// between shapes that do not touch. `sdRoundedBox` is not an estimator: it is
// exact outside the shape, which is where the whole bridge is.

#version 460 core

#include <flutter/runtime_effect.glsl>

// Twelve because that is where the cost corpus stops: the fragmentation excess
// (D26) is measured at 2 and at 12 surfaces and everything past it is an
// extrapolation of a curve nobody took. A group larger than this is refused by
// the caller rather than truncated here — a truncated group would draw a
// picture with shapes silently missing.
#define kMaxShapes 12

uniform vec2 uTexSize;     // atlas size, texels
uniform vec2 uMapOrigin;   // draw space -> texels: p * uMapScale + uMapOrigin
uniform float uMapScale;   // texels per logical pixel
uniform vec2 uSlotMin;     // the slot's own bounds in texels, inclusive
uniform vec2 uSlotMax;
uniform float uCount;      // shapes in force, 1..kMaxShapes
uniform float uBlend;      // smin radius k, draw-space px; 0 is a plain union
uniform vec4 uBox[kMaxShapes];     // centre.xy, half extent.xy, draw space
uniform float uRadius[kMaxShapes]; // corner radius, px
uniform float uThickness;  // how far in from the rim refraction reaches, px
uniform float uStrength;   // peak sample displacement at the rim, px
uniform float uEdgePower;  // falloff exponent
uniform float uShoulder;   // shoulder exponent on the depth, 1.0 = no shoulder
uniform vec4 uTint;        // straight alpha, laid over the refracted sample
uniform float uRimWidth;   // width of the outline inside the edge, px
uniform vec4 uRim;         // rgb is the colour, a is how much it *adds*
uniform float uPixel;      // one device pixel, in this geometry's own units

// The distance past which a shape is skipped. `k` in every draw the package
// makes, and a uniform rather than `k` itself for one reason: skipping is
// supposed to be *bit-identical*, and the only way to see that is to render the
// same fragment twice with the branch present and the threshold out of reach.
// A constant would have made the claim unfalsifiable from outside the shader.
// It costs a register; the comparison it feeds was going to be there anyway.
uniform float uCullK;

// How much the outline *replaces* rather than adds: 0 is the calibrated
// additive rim, 1 lays uRim.rgb on at the band's coverage — the platform's
// increase-contrast switch (D203). A uniform rather than a second shader
// because at 0 the line below is `col * 1.0 + …`, the same bits as before,
// and that is enforced rather than hoped for.
uniform float uRimMix;

uniform sampler2D uTex;

out vec4 fragColor;

// Further than any shape can be, and inside fp16.
//
// The seed for the fold, chosen so the first shape needs no branch: `smin` of
// anything with this returns that thing and its gradient, bit for bit, because
// `h` is exactly zero. 65504 is where fp16 stops and Adreno's fragment stage is
// fp16, so the seed is four orders of magnitude below it and `abs(d - kFar)`
// still lands on a grid fine enough to be exactly zero after the `max`.
const float kFar = 1.0e4;

float sdRoundedBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

// Analytic gradient, transliterated from bench/model/refraction.dart together
// with the SDF above. Kept branchy: D15 measured the branchless rewrite of this
// exact function 53% dearer, because its branches separate large connected
// regions rather than neighbouring pixels.
vec2 sdRoundedBoxNormal(vec2 p, vec2 b, float r) {
    vec2 s = vec2(p.x < 0.0 ? -1.0 : 1.0, p.y < 0.0 ? -1.0 : 1.0);
    vec2 q = abs(p) - b + r;
    if (q.x > 0.0 || q.y > 0.0) {
        vec2 m = max(q, vec2(0.0));
        float len = length(m);
        return len == 0.0 ? vec2(0.0) : s * m / len;
    }
    return q.x > q.y ? vec2(s.x, 0.0) : vec2(0.0, s.y);
}

void main() {
    vec2 p = FlutterFragCoord().xy;

    // A blend radius of zero is a declaration — "share the capture, keep the
    // silhouettes" — and not a clamp. The epsilon turns it into a plain union
    // by arithmetic rather than by a branch: `h` can only be non-zero within
    // 1e-4 px of a tie, and the deepest it can then pull the field is 2.5e-5 px.
    float k = max(uBlend, 1.0e-4);

    float d = kFar;
    vec2 n = vec2(0.0);
    for (int i = 0; i < kMaxShapes; i++) {
        if (float(i) >= uCount) {
            break;
        }
        vec2 rel = p - uBox[i].xy;
        float di = sdRoundedBox(rel, uBox[i].zw, uRadius[i]);
        // A shape at least `k` farther than the field so far contributes
        // nothing, and skipping it is bit-identical rather than close: `h` is
        // then exactly zero, so the fold leaves `d` at `min(di, d) = d`, and
        // `mix(n, ni, 0)` is exactly `n` because `mix` is `x*(1-a) + y*a`.
        // What it skips is the branchy normal and the two mixes — the half of
        // the per-shape cost that a fragment far from the shape has no use for.
        // The test is against the *running* `d` and not against the union's
        // minimum, and that is the difference between exact and nearly: the
        // fold is order-dependent, so a shape excluded by a quantity the loop
        // has not finished computing can still have been folded.
        //
        // Worth a branch because the per-shape term is what the fragment is:
        // 0.0441 cycles per device pixel each against 0.0343 fixed, so at
        // twelve shapes the fold is 94% of the fragment (D169, Adreno 830).
        if (di - d >= uCullK) {
            continue;
        }
        vec2 ni = sdRoundedBoxNormal(rel, uBox[i].zw, uRadius[i]);

        float h = max(k - abs(di - d), 0.0) / k;
        float w = h * 0.5;
        float fused = min(di, d) - h * h * k * 0.25;
        // The weight belongs to the *farther* shape, so which way the `mix`
        // runs depends on which is nearer. Written as two `mix` calls rather
        // than as a signed weight because the pair has to stay a convex
        // combination: with the wrong sign the fused normal leaves the cone of
        // its inputs and the bridge refracts outward.
        n = di < d ? mix(ni, n, w) : mix(n, ni, w);
        d = fused;
    }

    // The rim bends the sample inward; the flat middle reads straight through.
    // Identical to the single-surface path, including the shoulder exponent
    // (D106) — the whole difference between the two programs is the field.
    float t = clamp(-d / uThickness, 0.0, 1.0);
    float bend = pow(1.0 - pow(t, uShoulder), uEdgePower);
    vec2 src = p + n * (uStrength * bend);

    // Clamped to the slot rather than left to the sampler's tile mode. In a
    // group the neighbour a stray sample would land in is a *member* — the
    // invariant puts the whole group in one slot — so the clamp is what keeps
    // the sample inside the captured region rather than what keeps surfaces
    // apart. Both halves still matter at the screen's edge.
    vec2 texel = clamp(src * uMapScale + uMapOrigin, uSlotMin, uSlotMax);
    vec2 uv = texel / uTexSize;
    vec3 base = texture(uTex, uv).rgb;

    vec3 col = mix(base, uTint.rgb, uTint.a);

    float band = uRimWidth <= 0.0 ? 0.0 : clamp((d + uRimWidth) / uPixel + 0.5, 0.0, 1.0);
    col = col * (1.0 - uRimMix * band) + uRim.rgb * (uRim.a * band);

    float coverage = clamp(0.5 - d / uPixel, 0.0, 1.0);
    fragColor = vec4(col, 1.0) * coverage;
}
