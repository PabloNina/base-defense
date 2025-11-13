shader_type canvas_item;

uniform sampler2D TILE_DATA;
varying flat ivec2 tile_coord;

void vertex() {
	tile_coord = ivec2(INSTANCE_CUSTOM.xy);
}

void fragment() {
	// Fetch the custom data.
	vec4 ooze_modulate = texelFetch(TILE_DATA, tile_coord, 0);
    
    // DEBUG: Directly output the custom data color.
    // If data is passed correctly, this should be purple with some alpha.
    // If it's black, the data is zero. If it's white, the data is the default.
	COLOR = ooze_modulate;
}
