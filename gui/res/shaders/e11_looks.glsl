// e11 "Game" look, Mac edition: one cheap full-screen pass.
// Colour (brightness/contrast/saturation/warmth) is applied by libplacebo's own colour
// adjustment for free; this pass only lifts shadow detail, because MacBook panels crush
// dark tones compared with a TV. No blur, bloom or light-ray passes: they cost frames.

//!PARAM shadows
//!TYPE DYNAMIC float
//!MINIMUM 0.0
//!MAXIMUM 2.0
0.0

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC e11 game look (shadow detail)

vec4 hook()
{
    vec4 c = HOOKED_texOff(vec2(0.0));
    vec3 col = c.rgb;
    const vec3 W = vec3(0.2126, 0.7152, 0.0722);
    // Lifts dark and lower-mid tones; pure black stays black, highlights untouched,
    // colour preserved by scaling RGB.
    float l = max(dot(clamp(col, 0.0, 1.0), W), 1e-4);
    float lifted = l + shadows * 0.55 * l * pow(1.0 - l, 3.0);
    col *= lifted / l;
    return vec4(clamp(col, 0.0, 1.0), c.a);
}
