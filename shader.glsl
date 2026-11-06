uniform vec2 center;
uniform vec2 span;
uniform vec2 screenSize;
uniform float maxiter;
uniform float aa;

vec3 palette(float t)
{
    float om = 1.0 - t;
    return vec3(9.0 * om * t * t * t,
                15.0 * om * om * t * t,
                8.5 * om * om * om * t);
}

vec3 mandelColor(vec2 c)
{
    vec2 z = vec2(0.0);
    vec2 z2 = vec2(0.0);
    float it = 0.0;

    for (int i = 0; i < 2048; i++) {
        if (float(i) >= maxiter || z2.x + z2.y >= 4.0) break;
        z = vec2(z2.x - z2.y + c.x, 2.0 * z.x * z.y + c.y);
        z2 = z * z;
        it = it + 1.0;
    }

    float t;
    if (z2.x + z2.y >= 4.0) {
        t = it / maxiter;
    } else {
        t = 1.0;
    }
    return palette(t);
}

vec4 effect(vec4 color, Image tex, vec2 texCoord, vec2 screenCoord)
{
    vec2 c = center + (screenCoord - 0.5 * screenSize) * (span / screenSize);

    if (aa > 0.5) {
        vec3 total = vec3(0.0);
        for (int sy = 0; sy < 2; sy++) {
            for (int sx = 0; sx < 2; sx++) {
                vec2 off = (((vec2(float(sx), float(sy)) + 0.25) * 0.5) - 0.5) * (span / screenSize);
                total += mandelColor(c + off);
            }
        }
        return vec4(total * 0.25, 1.0);
    }

    return vec4(mandelColor(c), 1.0);
}
