#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;
uniform float u_pixelRatio;
uniform float u_depth;
uniform float u_zoom;
uniform float u_dispersion;
uniform vec4 u_rect;
uniform vec2 u_viewSize;
uniform float u_pinch;
uniform sampler2D u_input;
out vec4 frag_color;

vec4 texelInput(vec2 pixel) {
  vec2 uv = clamp(pixel / u_size, 0.5 / u_size, 1.0 - 0.5 / u_size);
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(u_input, uv);
}

vec4 sampleInput(vec2 pixel) {
  // Image-filter input samplers may use nearest filtering. Explicit bilinear
  // sampling keeps magnified glyphs smooth on both GLES and Vulkan.
  vec2 coordinate = clamp(pixel, vec2(0.5), u_size - 0.5) - 0.5;
  vec2 base = floor(coordinate) + 0.5;
  vec2 fraction = fract(coordinate);
  vec4 topLeft = texelInput(base);
  if (fraction.x < 0.001 && fraction.y < 0.001) return topLeft;
  return mix(
      mix(topLeft, texelInput(base + vec2(1.0, 0.0)), fraction.x),
      mix(texelInput(base + vec2(0.0, 1.0)), texelInput(base + vec2(1.0, 1.0)), fraction.x),
      fraction.y);
}

void main() {
  vec2 pixel = FlutterFragCoord().xy;
  // A backdrop's input is the viewport texture, not the clipped pill.
  // Normalize through the logical viewport even when blur downsamples it.
  vec2 scale = u_size / max(u_viewSize, vec2(1.0));
  float pixelRatio = min(scale.y, u_pixelRatio * 2.0);
  vec2 halfSize = u_rect.zw * scale * 0.5;
  vec2 centerPosition = u_rect.xy * scale + halfSize;
  vec2 p = pixel - centerPosition;
  float radius = min(halfSize.x, halfSize.y);
  // Capsule distance and normal keep refraction confined to its curved rim.
  vec2 axis = vec2(clamp(p.x, -halfSize.x + radius, halfSize.x - radius), 0.0);
  vec2 radial = p - axis;
  float distanceToEdge = radius - length(radial);
  if (distanceToEdge < -1.0) {
    frag_color = sampleInput(pixel);
    return;
  }
  vec2 normal = radial / max(length(radial), 0.001);
  // A quarter-circle bevel has a vertical normal at its outer edge and a
  // flat face in the middle. Trace the ray through that curved glass instead
  // of painting a dark shape where a reflection is expected to appear.
  float bevel = max(min(u_depth * pixelRatio, radius), 0.001);
  float slope = clamp(1.0 - max(distanceToEdge, 0.0) / bevel, 0.0, 1.0);
  float normalZ = sqrt(max(0.0, 1.0 - slope * slope));
  vec3 surfaceNormal = vec3(normal * slope, normalZ);
  vec3 ray = refract(vec3(0.0, 0.0, -1.0), surfaceNormal, 1.0 / 1.10);
  vec2 displacement = ray.xy * bevel * (8.0 + normalZ) / max(abs(ray.z), 0.001);
  float reach = length(displacement);
  displacement *= min(1.0, radius / max(reach, 0.001));

  // The expanded indicator's pinch samples a little farther from its center.
  // Together with the inward bevel refraction this folds a real track edge
  // into a curved band. Its color/extent depend entirely on the backdrop.
  // See the upstream optical model and attribution in third_party/notices.
  vec2 centered = p / max(halfSize * 2.0, vec2(1.0));
  vec2 squared = centered * centered * 4.0;
  float roundedDistance = sqrt(sqrt(dot(squared, squared)));
  float pinchFalloff = smoothstep(0.0, 1.0, roundedDistance);
  vec2 pinchReach = min(u_viewSize * 0.025, u_rect.zw * 0.28) * scale;
  float boundaryFade = smoothstep(0.0, 1.5 * pixelRatio, distanceToEdge);
  vec2 pinch = centered * pinchReach * pinchFalloff * u_pinch * boundaryFade;
  vec2 refracted = centerPosition + p / max(u_zoom, 1.0) + displacement + pinch;
  float edgeBand = exp(-pow(max(distanceToEdge, 0.0) / max(pixelRatio * 1.8, 0.01), 2.0));
  // Keep chromatic separation on the thin glass rim so it reads as a fringe,
  // rather than producing colored copies of labels across the whole lens.
  vec2 split = displacement * (u_dispersion * 0.025);
  vec4 center = sampleInput(refracted);
  // Only light is added here. All dark or colored bands come from the sampled
  // scene; a uniform backdrop must never acquire two fabricated black slots.
  float activity = clamp((u_zoom - 1.0) / 0.035, 0.0, 1.0);
  float light = pow(abs(dot(normal, normalize(vec2(0.25, -1.0)))), 8.0);
  float reflection = edgeBand * (0.10 + light * 0.48) * activity;
  if (length(split) < 0.001) {
    center.rgb = mix(center.rgb, vec3(center.a), reflection);
    frag_color = center;
    return;
  }
  // Work in premultiplied alpha; never tint transparent samples as black.
  vec4 red = sampleInput(refracted + split);
  vec4 blue = sampleInput(refracted - split);
  vec3 rgb = vec3(red.r / max(red.a, 0.001),
                  center.g / max(center.a, 0.001),
                  blue.b / max(blue.a, 0.001));
  frag_color = vec4(rgb * center.a, center.a);
  frag_color.rgb = mix(frag_color.rgb, vec3(frag_color.a), reflection);
}
