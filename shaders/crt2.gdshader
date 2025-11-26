// built upon:
// https://www.youtube.com/watch?v=E401x98N6iA&t=907s&pp=ygUgdGVybWluYWwgZGlzdG9ydGlvbiBlZmZlY3QgZ29kb3Q%3D
shader_type canvas_item;
render_mode unshaded;

const float curvature = 6.2;
const float vignette_multiplier = 0.5;

uniform sampler2D screen_texture: hint_screen_texture, filter_linear_mipmap;
uniform vec3 tint_color : source_color = vec3(0.5, 1.0, 0.5);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.3;

// New scanline animation controls
uniform float scan_freq = 240.0;     // how many lines across the screen height
uniform float scan_speed = 2.0;      // how fast they move
uniform float scan_strength = 0.08;  // contrast of the lines
uniform float scan_base = 1.0;       // baseline brightness

void fragment() {
    // --- the only functional change: base the effect on mesh-local UV ---
    vec2 centered_uv = UV * 2.0 - 1.0;

    vec2 uv_offset = centered_uv.yx / curvature;
    vec2 warped_uv = centered_uv + centered_uv * uv_offset * uv_offset;
    vec3 cutoff = vec3(step(abs(warped_uv.x), 1.0) * step(abs(warped_uv.y), 1.0));

    // animated scanlines
    float phase = TIME * scan_speed;
    float s = sin(warped_uv.y * scan_freq + phase);
    vec3 scanlines = vec3(s * scan_strength + scan_base);

    vec3 vignette = vec3(length(pow(abs(centered_uv), vec2(4.0)) / 3.0));

    // sample the real screen at this pixel (keeps it see-through)
    vec3 screen_color = textureLod(screen_texture, SCREEN_UV, 0.1).rgb * cutoff * scanlines;

    screen_color -= vignette * vignette_multiplier;
    screen_color = mix(screen_color, screen_color * tint_color, tint_strength);
    COLOR = vec4(screen_color, 1.0);
}
