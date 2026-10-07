/*{
  "CREDIT": "Scenic",
  "CATEGORIES": [ "Utility" ],
  "DESCRIPTION": "Scenic destination hub: 8-input additive mixer",
  "INPUTS": [
    { "NAME": "in1", "TYPE": "image" },
    { "NAME": "in2", "TYPE": "image" },
    { "NAME": "in3", "TYPE": "image" },
    { "NAME": "in4", "TYPE": "image" },
    { "NAME": "in5", "TYPE": "image" },
    { "NAME": "in6", "TYPE": "image" },
    { "NAME": "in7", "TYPE": "image" },
    { "NAME": "in8", "TYPE": "image" }
  ]
}*/

void main()
{
  vec2 uv = isf_FragNormCoord;
  vec4 c = IMG_NORM_PIXEL(in1, uv)
         + IMG_NORM_PIXEL(in2, uv)
         + IMG_NORM_PIXEL(in3, uv)
         + IMG_NORM_PIXEL(in4, uv)
         + IMG_NORM_PIXEL(in5, uv)
         + IMG_NORM_PIXEL(in6, uv)
         + IMG_NORM_PIXEL(in7, uv)
         + IMG_NORM_PIXEL(in8, uv);
  gl_FragColor = clamp(c, 0.0, 1.0);
}
