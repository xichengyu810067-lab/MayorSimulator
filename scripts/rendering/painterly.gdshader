shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 tex_size = vec2(textureSize(screen_texture, 0));
    vec2 inv_size = 1.0 / tex_size;
    
    vec4 base_color = texture(screen_texture, uv);
    
    vec4 paint_color = base_color;
    float max_luma = 0.0;
    vec2 offsets[9] = {
        vec2(-1,-1), vec2(0,-1), vec2(1,-1),
        vec2(-1, 0), vec2(0, 0), vec2(1, 0),
        vec2(-1, 1), vec2(0, 1), vec2(1, 1)
    };
    
    for (int i=0; i<9; i++) {
        vec4 col = texture(screen_texture, uv + offsets[i] * inv_size * 3.5);
        float luma = dot(col.rgb, vec3(0.299, 0.587, 0.114));
        if (luma > max_luma) {
            max_luma = luma;
            paint_color = col;
        }
    }
    
    vec4 bloom = vec4(0.0);
    for (int i=0; i<9; i++) {
        bloom += texture(screen_texture, uv + offsets[i] * inv_size * 6.0);
    }
    bloom /= 9.0;
    
    vec3 color = mix(paint_color.rgb, bloom.rgb, 0.35);
    
    float r = texture(screen_texture, uv + vec2(inv_size.x * 2.5, inv_size.y * 1.5)).r;
    float b = texture(screen_texture, uv - vec2(inv_size.x * 2.5, inv_size.y * 1.5)).b;
    color.r = mix(color.r, r, 0.4);
    color.b = mix(color.b, b, 0.4);
    
    color = mix(vec3(0.5), color, 1.25);
    float luma2 = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(vec3(luma2), color, 1.45);
    color *= vec3(1.10, 0.95, 0.85);
    
    vec2 center_dist = uv - vec2(0.5);
    float vignette = 1.0 - dot(center_dist, center_dist) * 1.2;
    color *= smoothstep(0.0, 1.0, vignette);
    
    COLOR = vec4(color, 1.0);
}
