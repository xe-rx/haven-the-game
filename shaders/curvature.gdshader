shader_type canvas_item;
render_mode unshaded;

const float curvature = 9.2;

void fragment() {
    vec2 centered_uv = UV * 2.0 - 1.0;

    vec2 uv_offset = centered_uv.yx / curvature;
    vec2 warped_uv = centered_uv + centered_uv * uv_offset * uv_offset;

    float mask = step(abs(warped_uv.x), 1.0) * step(abs(warped_uv.y), 1.0);

    vec2 sample_uv = warped_uv * 0.5 + 0.5;

    // 🔽 ADD THIS LINE
    sample_uv.y = 1.0 - sample_uv.y;

    vec4 col = texture(TEXTURE, sample_uv);

    COLOR = vec4(col.rgb * mask, col.a * mask);
}
