/*{
  "CREDIT": "Scenic",
  "CATEGORIES": [ "Generator" ],
  "DESCRIPTION": "Scenic test pattern: SMPTE-style colour bars",
  "INPUTS": []
}*/

// EBU/SMPTE bar order, 100% amplitude.
const vec3 bars[7] = vec3[7](
  vec3(1.0, 1.0, 1.0),
  vec3(1.0, 1.0, 0.0),
  vec3(0.0, 1.0, 1.0),
  vec3(0.0, 1.0, 0.0),
  vec3(1.0, 0.0, 1.0),
  vec3(1.0, 0.0, 0.0),
  vec3(0.0, 0.0, 1.0)
);

// Castellations under the bars: the near-black steps are what an operator
// reads to set black level.
const vec3 pluge[7] = vec3[7](
  vec3(0.0, 0.0, 0.294),
  vec3(1.0, 1.0, 1.0),
  vec3(0.235, 0.0, 0.392),
  vec3(0.0, 0.0, 0.0),
  vec3(0.031, 0.031, 0.031),
  vec3(0.0, 0.0, 0.0),
  vec3(0.071, 0.071, 0.071)
);

void main()
{
  vec2 uv = isf_FragNormCoord;
  int col = int(clamp(uv.x * 7.0, 0.0, 6.999));
  vec3 c = uv.y > 0.25 ? bars[col] : pluge[col];

  // A moving band proves the source is live, not a frozen frame.
  float sweep = fract(uv.x - TIME * 0.15);
  c = mix(c, vec3(1.0) - c, step(0.985, sweep) * step(0.47, uv.y)
                            * step(uv.y, 0.53));

  gl_FragColor = vec4(c, 1.0);
}
