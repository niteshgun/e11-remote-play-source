// e11 "photo looks" for the stream: bloom, light shafts, sharpen, clarity (local contrast),
// vibrance, teal & orange split-toning, vignette and film grain. All strengths are dynamic so
// the quick menu can change them live without recompiling. 0 = effect off.
//
// Lighting passes work at quarter resolution: bright-pass -> blur H -> blur V (bloom), and a
// radial blur of the bright-pass toward the upper middle of the frame (light shafts).

//!PARAM shadows
//!TYPE DYNAMIC float
//!MINIMUM 0.0
//!MAXIMUM 2.0
0.0

//!PARAM bloom
//!TYPE DYNAMIC float
//!MINIMUM 0.0
//!MAXIMUM 2.0
0.0

//!PARAM rays
//!TYPE DYNAMIC float
//!MINIMUM 0.0
//!MAXIMUM 2.0
0.0

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
//!SAVE E11BRIGHT
//!WIDTH HOOKED.w 4 /
//!HEIGHT HOOKED.h 4 /
//!DESC e11 lighting: bright pass

vec4 hook()
{
    // Average a 2x2 block of the full-res image, keep only the bright parts
    vec2 q = HOOKED_pt * 1.0;
    vec3 c = 0.25 * (HOOKED_tex(HOOKED_pos + vec2(-q.x, -q.y)).rgb + HOOKED_tex(HOOKED_pos + vec2(q.x, -q.y)).rgb
                   + HOOKED_tex(HOOKED_pos + vec2(-q.x, q.y)).rgb + HOOKED_tex(HOOKED_pos + vec2(q.x, q.y)).rgb);
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    float k = smoothstep(0.62, 0.98, l);
    return vec4(c * k, 1.0);
}

//!HOOK OUTPUT
//!BIND E11BRIGHT
//!SAVE E11BLURH
//!WIDTH E11BRIGHT.w
//!HEIGHT E11BRIGHT.h
//!DESC e11 lighting: bloom blur H

vec4 hook()
{
    const float w[5] = float[5](0.2270, 0.1945, 0.1216, 0.0541, 0.0162);
    vec3 acc = E11BRIGHT_tex(E11BRIGHT_pos).rgb * w[0];
    for (int i = 1; i < 5; i++) {
        vec2 o = vec2(float(i) * 2.0 * E11BRIGHT_pt.x, 0.0);
        acc += (E11BRIGHT_tex(E11BRIGHT_pos + o).rgb + E11BRIGHT_tex(E11BRIGHT_pos - o).rgb) * w[i];
    }
    return vec4(acc, 1.0);
}

//!HOOK OUTPUT
//!BIND E11BLURH
//!SAVE E11BLOOM
//!WIDTH E11BLURH.w
//!HEIGHT E11BLURH.h
//!DESC e11 lighting: bloom blur V

vec4 hook()
{
    const float w[5] = float[5](0.2270, 0.1945, 0.1216, 0.0541, 0.0162);
    vec3 acc = E11BLURH_tex(E11BLURH_pos).rgb * w[0];
    for (int i = 1; i < 5; i++) {
        vec2 o = vec2(0.0, float(i) * 2.0 * E11BLURH_pt.y);
        acc += (E11BLURH_tex(E11BLURH_pos + o).rgb + E11BLURH_tex(E11BLURH_pos - o).rgb) * w[i];
    }
    return vec4(acc, 1.0);
}

//!HOOK OUTPUT
//!BIND E11BRIGHT
//!SAVE E11RAYS
//!WIDTH E11BRIGHT.w
//!HEIGHT E11BRIGHT.h
//!DESC e11 lighting: light shafts

vec4 hook()
{
    // March from this pixel toward the light origin (upper middle, where sun and sky usually are),
    // gathering bright pixels with falloff: streaks of light radiate out from bright areas.
    const vec2 origin = vec2(0.5, 0.30);
    vec2 delta = (E11BRIGHT_pos - origin) * (1.0 / 28.0) * 0.85;
    vec2 p = E11BRIGHT_pos;
    float decay = 1.0;
    vec3 acc = vec3(0.0);
    for (int i = 0; i < 28; i++) {
        p -= delta;
        acc += E11BRIGHT_tex(p).rgb * decay;
        decay *= 0.93;
    }
    return vec4(acc * (1.0 / 9.0), 1.0);
}

//!HOOK OUTPUT
//!BIND HOOKED
//!BIND E11BLOOM
//!BIND E11RAYS
//!DESC e11 photo looks

vec4 hook()
{
    vec4 c = HOOKED_texOff(vec2(0.0));
    vec3 col = c.rgb;
    const vec3 W = vec3(0.2126, 0.7152, 0.0722);

    // Shadow detail: lifts dark and lower-mid tones (like a photo editor's Shadows slider).
    // Pure black stays black and highlights are untouched; colour is preserved by scaling RGB.
    if (shadows > 0.0) {
        float l = max(dot(clamp(col, 0.0, 1.0), W), 1e-4);
        float lifted = l + shadows * 0.55 * l * pow(1.0 - l, 3.0);
        col *= lifted / l;
    }

    // Bloom + light shafts: screen-blend the glow so highlights never clip harshly
    if (bloom > 0.0 || rays > 0.0) {
        vec3 glow = E11BLOOM_tex(HOOKED_pos).rgb * (bloom * 1.4) + E11RAYS_tex(HOOKED_pos).rgb * (rays * 0.8);
        col = 1.0 - (1.0 - clamp(col, 0.0, 1.0)) * (1.0 - clamp(glow, 0.0, 1.0));
    }

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
