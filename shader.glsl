extern number maxIter;

vec4 effect(vec4 color, Image tex, vec2 texCoord, vec2 screenCoord)
{
    float iter = Texel(tex, texCoord).r * maxIter;
    float t = iter / maxIter;

    float r = 9.0 * (1.0 - t) * t * t * t;
    float g = 15.0 * (1.0 - t) * (1.0 - t) * t * t;
    float b = 8.5 * (1.0 - t) * (1.0 - t) * (1.0 - t) * t;

    return vec4(r, g, b, 1.0);
}
