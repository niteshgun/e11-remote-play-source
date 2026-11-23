// e11 "photo looks" pass for the stream: sharpen, clarity (local contrast), vibrance,
// teal & orange split-toning, vignette and film grain. All strengths are dynamic so the
// quick menu can change them live without recompiling. 0 = effect off.

//!PARAM sharpen
//!TYPE DYNAMIC float
//!MINIMUM 0.0
//!MAXIMUM 2.0
0.0

//!PARAM clarity
//!TYPE DYNAMIC float
//!MINIMUM 0.0
//!MAXIMUM 2.0
0.0

//!PARAM vibrance
//!TYPE DYNAMIC float
//!MINIMUM 0.0
//!MAXIMUM 1.5
0.0

//!PARAM split
//!TYPE DYNAMIC float
//!MINIMUM 0.0
//!MAXIMUM 1.5
0.0

//!PARAM vignette
//!TYPE DYNAMIC float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.0

//!PARAM grain
//!TYPE DYNAMIC float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.0

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC e11 photo looks

vec4 hook()
{
    vec4 c = HOOKED_texOff(vec2(0.0));
    vec3 col = c.rgb;
    const vec3 W = vec3(0.2126, 0.7152, 0.0722);

    // Sharpen: small-radius unsharp mask (crisper edges on a Retina screen)
    if (sharpen > 0.0) {
        vec3 n = HOOKED_texOff(vec2( 1.0, 0.0)).rgb + HOOKED_texOff(vec2(-1.0, 0.0)).rgb
               + HOOKED_texOff(vec2( 0.0, 1.0)).rgb + HOOKED_texOff(vec2( 0.0,-1.0)).rgb;
        col += (col - n * 0.25) * sharpen;
    }

    // Clarity: wide-radius local contrast on the midtones (the "DSLR punch")
    if (clarity > 0.0) {
        vec3 b = HOOKED_texOff(vec2( 5.0, 0.0)).rgb + HOOKED_texOff(vec2(-5.0, 0.0)).rgb
               + HOOKED_texOff(vec2( 0.0, 5.0)).rgb + HOOKED_texOff(vec2( 0.0,-5.0)).rgb
               + HOOKED_texOff(vec2( 3.5, 3.5)).rgb + HOOKED_texOff(vec2(-3.5,-3.5)).rgb
               + HOOKED_texOff(vec2( 3.5,-3.5)).rgb + HOOKED_texOff(vec2(-3.5, 3.5)).rgb;
        b *= 0.125;
        float l = dot(col, W);
        float midtones = 1.0 - abs(clamp(l, 0.0, 1.0) * 2.0 - 1.0);
        col += vec3((l - dot(b, W)) * clarity * midtones);
    }

    // Vibrance: boosts muted colours more than already-saturated ones (skin stays natural)
    if (vibrance > 0.0) {
        float l = dot(col, W);
        float sat = max(col.r, max(col.g, col.b)) - min(col.r, min(col.g, col.b));
        col = mix(vec3(l), col, 1.0 + vibrance * (1.0 - clamp(sat, 0.0, 1.0)));
    }

    // Teal & orange split-toning: cool shadows, warm highlights (blockbuster look)
    if (split > 0.0) {
        float l = clamp(dot(col, W), 0.0, 1.0);
        vec3 shadows = vec3(-0.04, 0.05, 0.10) * (1.0 - l) * (1.0 - l);
        vec3 highlights = vec3(0.10, 0.04, -0.06) * l * l;
        col += split * (shadows + highlights);
    }

    // Vignette: gently darkens the corners like a camera lens
    if (vignette > 0.0) {
        vec2 uv = (HOOKED_pos - 0.5) * vec2(1.0, 0.85);
        float v = 1.0 - smoothstep(0.30, 0.85, length(uv));
        col *= mix(1.0, v, vignette * 0.6);
    }

    // Film grain: fine animated noise (cinema feel, hides banding)
    if (grain > 0.0) {
        vec2 p = HOOKED_pos * HOOKED_size + vec2(float(frame) * 17.0, float(frame) * 7.0);
        float n = fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
        col += vec3(n * grain * 0.07);
    }

    return vec4(clamp(col, 0.0, 1.0), c.a);
}
