# Shaders

`mixer8.fs` and `passthrough.fs` are Scenic's own.

`crop.fs`, `transform.fs` and `colorcontrols.fs` come from the shaders of
ossia score's default library
([score-user-library](https://github.com/ossia/score-user-library),
`Presets/GLSL_shaders`), under the MIT license in `LICENSE-ISF`, with two
deliberate deviations described below:

| here | there |
|---|---|
| `crop.fs` | `utility/Crop.fs` |
| `transform.fs` | `utility/Transform.fs` |
| `colorcontrols.fs` | `basic/filter/Color Controls.fs` (VIDVOX, by zoidberg) |

They are vendored rather than loaded from the score library because that
package is installed per user and the app has to run without it.

Deviations from the originals:

- `crop.fs`: the local `vec2 half` is renamed `halfSize`. `half` is a reserved
  word, and the shader does not compile on the SPIR-V path - it fails with
  "'half' : Reserved word" and the source renders nothing. The upstream file
  still uses `half`.
- `colorcontrols.fs`: saturation is applied as a luma-preserving mix in RGB
  (Rec.709) instead of scaling S in HSV. The original holds V, so a pure red at
  saturation 0 comes out white; an operator matching cameras expects the grey
  of the same brightness. Hue still rotates through HSV, and the control names
  are unchanged, so presets and the routing test are unaffected.

A video source's chain is `device → crop → transform → colour → matrix`, so
all three are per-source stages and the inspector shows them in that order.

`hdr/HDR Color Pipeline.fs` in the same package is the HDR-aware alternative
to `colorcontrols.fs` (EOTF, gamut, exposure, tonemap, OETF). It is not
vendored: it carries 14 controls and is the wrong default for every source.
