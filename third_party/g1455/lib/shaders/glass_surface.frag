// The package's glass. The optics are M13's, calibrated against Apple's own
// frames rather than chosen. The displacement is inward and its *shape* is
// D106 (`(1 - (u/t)^0.6)^1.9`, reach 21, amplitude -58.2 at the rim); the rim
// is D86-D88 (an additive neutral step 0.79 logical px wide with no light
// direction); the edge's coverage is one device pixel because that is what the
// reference measures. Nothing here disperses, and that is measured rather than
// left out: Apple's own material sends the three channels to the same place to
// within 0.155 logical px (D103), so one `texture()` is the reference.
//
// A separate binary from `bench/shaders/glass_refract.frag` on purpose, and not
// for tidiness. That one is a *cost probe*: three configurations share it so
// their timings differ in one thing, and B5 measured that adding a path to a
// program reprices every mode already in it by 52-62%. It is also a separate
// binary from `bench/shaders/glass_preview.frag`, which is the instrument the
// M11 ladder grades through: this one samples an **atlas slot** and that one
// samples a full-screen proxy, so their uniform blocks differ — and
// `test/glass/glass_optics_test.dart` renders the same geometry through both
// and requires them to agree, because otherwise the package would be shipping
// optics the ladder never graded.
//
// **The sampling map is the whole difference, and it is three numbers.** The
// proxy is one slot of an atlas, so a draw-space point reaches its texel as
// `texel = p * uMapScale + uMapOrigin` — the scale being texels per logical
// pixel, the origin folding together the surface's place on the screen, the
// slot's source origin and the slot's place in the texture. The clamp is to the
// **slot**, not to the texture: a displaced sample that ran past its own slot
// would read the neighbouring surface's backdrop, which is a real picture of
// somewhere else and looks like a refraction rather than a bug.
//
// The coordinate contract, measured rather than assumed (probe, 2026-09-03):
// FlutterFragCoord() is the coordinate of the *geometry as handed to the draw*
// — `canvas.scale` and `canvas.translate` do not enter it, and a rect drawn at
// (100, 0) reads x = 100 at its left edge. Same answer on Impeller (where it is
// the vertex position, runtime_effect.vert:19) and on Skia in flutter_tester.
// So the caller draws `offset & size` and passes uCenter in that same space,
// and uSrcOrigin carries whatever translation separates it from the space the
// proxy was captured in.

#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uTexSize;     // atlas size, texels
uniform vec2 uMapOrigin;   // draw space -> texels: p * uMapScale + uMapOrigin
uniform float uMapScale;   // texels per logical pixel
uniform vec2 uSlotMin;     // the slot's own bounds in texels, inclusive
uniform vec2 uSlotMax;
uniform vec2 uHalf;        // half extent of the surface, draw-space px
uniform vec2 uCenter;      // centre of the surface, draw space
uniform float uRadius;     // corner radius, px
uniform float uThickness;  // how far in from the rim refraction reaches, px
uniform float uStrength;   // peak sample displacement at the rim, px
uniform float uEdgePower;  // falloff exponent
uniform float uShoulder;   // shoulder exponent on the depth, 1.0 = no shoulder
uniform vec4 uTint;        // straight alpha, laid over the refracted sample
uniform float uRimWidth;   // width of the outline inside the edge, px
uniform vec4 uRim;         // rgb is the colour, a is how much it *adds*
uniform float uPixel;      // one device pixel, in this geometry's own units
// How much the outline *replaces* rather than adds: 0 is the calibrated
// additive rim, 1 lays uRim.rgb on at the band's coverage — the platform's
// increase-contrast switch (D203). A uniform rather than a second shader
// because at 0 the line below is `col * 1.0 + …`, the same bits as before,
// and that is enforced rather than hoped for.
uniform float uRimMix;
// The optics' `widen` over the half-box, per axis: the sample walks out from
// the centre by this fraction of its distance, so the shape shows its box
// grown by `widen` on every side (D218). Last, so every index above it stays
// where Dart has always set it; and at zero the term below adds an exact zero.
uniform vec2 uWiden;
// A fade across the surface: f = clamp(dot(rel, uFade.xy) + uFade.z), and the
// glass is drawn at 1 - smoothstep's f — whole where f is 0, gone where it is
// 1, so what is under the surface shows through by that much. The scroll edge
// effect's blur ramp is this (spike 31). Last again, and at zero it is
// `coverage * 1.0`: f is 0, `f * f * (3 - 2f)` is 0, and 1 - 0 is exactly 1.
uniform vec3 uFade;

// The ripple: a viscous wave from where the glass was touched (D229). Compiled
// into `glass_surface_ripple.frag` only, which is this file behind a define,
// and never into this binary — B5 measured that a path a program carries and
// does not take reprices the modes that do not take it by 52-62%, so a panel
// that is not rippling must not be running a program that could. The host
// swaps programs for exactly the frames a wave is alive.
//
// Every time-dependent quantity is computed in Dart once per frame; the
// fragment only evaluates the profile. Per wave:
//   uWave.xy   the touch, relative to uCenter, draw-space px
//   uWave.z    radius of the travelling front, px
//   uWave.w    half-width of the front, px
//   uWaveAmp.x the front's amplitude, pre-divided by its profile's bound so
//              that |displacement| <= |amplitude| exactly
//   uWaveAmp.y oscillation of the front, radians per half-width (0 is one bump)
//   uWaveAmp.z the held dimple's amplitude, likewise pre-normalised
//   uWaveAmp.w 1 / sigma^2 of the dimple
#ifdef GLASS_RIPPLE
#define kMaxWaves 4
uniform float uWaveCount;
uniform vec4 uWave[kMaxWaves];
uniform vec4 uWaveAmp[kMaxWaves];
// The sum of every amplitude above: a bound on the displacement's length.
uniform float uRippleReach;
// How much a slope facing up brightens, and one facing down darkens.
uniform float uRippleLight;
#endif

uniform sampler2D uTex;

out vec4 fragColor;

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
    vec2 rel = p - uCenter;

    float d = sdRoundedBox(rel, uHalf, uRadius);
    vec2 n = sdRoundedBoxNormal(rel, uHalf, uRadius);

    // The rim bends the sample inward; the flat middle reads straight through.
    //
    // The shoulder exponent is M13's ninth arm (D106). `(1 - t)^p` alone is not
    // Apple's curve: it fits the profile inside the reading's floor from 4
    // logical px in and misses by 0.52 px at the rim, with a residual that
    // alternates in sign rather than scattering. Bending the depth as well —
    // `(1 - t^a)^b` — lands at 0.254 against a floor of 0.464 and generalises
    // to bins it was not fitted to, where the two-parameter form does not.
    // At `uShoulder = 1` this is exactly the expression it replaces, which is
    // what makes the constant a measurement rather than a rewrite.
    float t = clamp(-d / uThickness, 0.0, 1.0);
    float bend = pow(1.0 - pow(t, uShoulder), uEdgePower);
    vec2 src = p + n * (uStrength * bend) + rel * uWiden;

#ifdef GLASS_RIPPLE
    // The displacement is the height field's gradient, so a crest magnifies
    // and a trough minifies, as a lens of that shape would. Both terms are
    // radial: `q / r` for the front, `q` itself for the dimple, whose
    // normalisation already carries the `2 / sigma^2`.
    //
    // The front's radius is softened by its own half-width, `sqrt(r^2 + w^2)`.
    // With the plain one a young front — radius under its width — has a slope
    // at the touch itself, and `q / r` turns it into a vector field that is
    // discontinuous there: a four-pointed pinch on the first frames, the first
    // render of this. Softened, the gradient is zero at the touch, the bound
    // is untouched (`r / r_s <= 1`), and a front that has left is where it was
    // to within `w^2 / 2r`.
    vec2 rd = vec2(0.0);
    for (int i = 0; i < kMaxWaves; i++) {
        if (float(i) >= uWaveCount) {
            break;
        }
        vec2 q = rel - uWave[i].xy;
        float r2 = dot(q, q);
        float r = sqrt(r2 + uWave[i].w * uWave[i].w);
        float u = (r - uWave[i].z) / uWave[i].w;
        float ku = uWaveAmp[i].y * u;
        float front = uWaveAmp[i].x * exp(-u * u) * (-2.0 * u * cos(ku) - uWaveAmp[i].y * sin(ku));
        rd += q * (front / r + uWaveAmp[i].z * exp(-r2 * uWaveAmp[i].w));
    }
    // Damped into the rim over the displacement's own bound, so a ripple alone
    // never samples outside the shape: a fragment at depth -d moves at most
    // -d. The rim then reads as the thick edge that absorbs the wave. With no
    // wave `rd` is +0 and this line and the next add exact zeros.
    rd *= clamp(-d / uRippleReach, 0.0, 1.0);
    src += rd;
#endif

    // Clamped to the slot rather than left to the sampler's tile mode. Two
    // reasons and they are different. A surface at a screen edge samples past
    // the proxy, and "what happens there" would otherwise be a property of the
    // backend rather than of the picture. And a sample that ran past its own
    // slot would land in a *neighbour's*, which in an atlas is one texel away
    // by construction — a real backdrop from elsewhere on the screen, which is
    // the worst kind of wrong because it looks plausible.
    vec2 texel = clamp(src * uMapScale + uMapOrigin, uSlotMin, uSlotMax);
    vec2 uv = texel / uTexSize;
    vec3 base = texture(uTex, uv).rgb;

    vec3 col = mix(base, uTint.rgb, uTint.a);

#ifdef GLASS_RIPPLE
    // Lit from above, and signed: `rd` points uphill, a normal (-grad h, 1)
    // faces up where rd.y > 0. Added and neutral, like the rim.
    col += uRippleLight * (rd.y / uRippleReach);
#endif

    // The outline, measured on Apple's own frames rather than chosen (M13's
    // fourth arm, D86-D88). Four things about it, and every one of them was a
    // guess here until the symmetric half of the inverted pair was read:
    //
    //  * it is a band of **constant** amplitude, not a ramp — a step beats a
    //    ramp, a smoothstep and a gaussian by 4.7x on the same twenty-one
    //    readings;
    //  * it is **0.79 logical px** wide, which is why this is a coverage
    //    expression and not a smoothstep: the band is narrower than a device
    //    pixel on any real screen, so what is drawn is the fraction of the
    //    fragment it covers;
    //  * it has **no light direction** — Apple's four rims agree to 1.04x,
    //    where the `0.35 + 0.65 * dot(n, L)` this replaces spanned 2.49x;
    //  * it is **added**, not mixed, and neutral. A mix toward any colour is
    //    necessarily weaker on the brighter material, and `Glass.clear`'s
    //    outline is not weaker than `Glass.regular`'s; the three channels of
    //    both agree to 2-5%.
    //
    // The outer side of the band is the shape's own edge and is left to the
    // coverage term below, so only the inner one is resolved here.
    float band = uRimWidth <= 0.0 ? 0.0 : clamp((d + uRimWidth) / uPixel + 0.5, 0.0, 1.0);
    col = col * (1.0 - uRimMix * band) + uRim.rgb * (uRim.a * band);

    // Box coverage over one device pixel, which is what the reference's edge
    // measures: fitting Apple's outermost device row returns a coverage of
    // 1.019 against a predicted 1, so their shape is opaque from the first row.
    // The `smoothstep(-0.75, 0.75, d)` this replaces spread the edge over three
    // device pixels at dpr 2 and returned 0.741 there.
    float coverage = clamp(0.5 - d / uPixel, 0.0, 1.0);
    float fade = clamp(dot(rel, uFade.xy) + uFade.z, 0.0, 1.0);
    fragColor = vec4(col, 1.0) * (coverage * (1.0 - fade * fade * (3.0 - 2.0 * fade)));
}
