shader_type canvas_item;

uniform vec3 key_color : source_color = vec3(0.0, 1.0, 0.0); // green
uniform float threshold = 0.4;
uniform float softness = 0.1;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    float dist = distance(tex.rgb, key_color);
    float alpha = smoothstep(threshold, threshold + softness, dist);
    COLOR = vec4(tex.rgb, tex.a * alpha);
}
