#version 460 core
#include <flutter/runtime_effect.glsl>

// Globo terrestre: proiezione ortografica di una foto satellitare (NASA Blue Marble)
uniform vec2 uCenter;   // centro del globo in pixel
uniform float uRadius;  // raggio in pixel
uniform float uLat0;    // latitudine al centro (radianti)
uniform float uLng0;    // longitudine al centro (radianti)
uniform float uNight;   // 1 = foto notturna (meno ombra)
uniform sampler2D uTex;

out vec4 fragColor;

const float PI = 3.14159265359;

void main() {
  vec2 p = (FlutterFragCoord().xy - uCenter) / uRadius;
  float r2 = min(dot(p, p), 1.0);
  float inside = step(dot(p, p), 1.0);
  float x = p.x;
  float y = -p.y;
  float z = sqrt(1.0 - r2);
  float s0 = sin(uLat0);
  float c0 = cos(uLat0);
  float lat = asin(clamp(z * s0 + y * c0, -1.0, 1.0));
  float lng = uLng0 + atan(x, z * c0 - y * s0);
  float u = fract((lng + PI) / (2.0 * PI));
  float v = clamp((PI * 0.5 - lat) / PI, 0.0, 1.0);
  vec3 col = texture(uTex, vec2(u, v)).rgb;
  // luce morbida verso il bordo, e un velo azzurro di atmosfera
  float light = mix(0.45 + 0.55 * z, 0.75 + 0.25 * z, uNight);
  col *= light;
  float rim = pow(1.0 - z, 3.0);
  col = mix(col, vec3(0.35, 0.6, 1.0), rim * 0.55);
  // bordo senza scalini
  float edge = 1.0 - smoothstep(1.0 - 1.5 / uRadius, 1.0, sqrt(r2));
  edge *= inside;
  fragColor = vec4(col * edge, edge);
}
