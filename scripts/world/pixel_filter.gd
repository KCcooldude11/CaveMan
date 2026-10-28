extends CanvasLayer
## Optional "retro" post-process: snaps the 3D view to big chunky pixels so
## the 3D geometry matches the pixel-art sprites. The HUD and menus draw on a
## higher layer, so they stay crisp. F2 cycles the block size (off = 1).

const SIZES := [1, 2, 3, 4]

var _rect: ColorRect
var _mat: ShaderMaterial
var _index := 0


func _ready() -> void:
	layer = -1  # above the 3D world, below every UI layer
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float block = 1.0;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * block;
	COLOR = texture(screen_tex, (floor(SCREEN_UV / px) + 0.5) * px);
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	set_block(1)


func set_block(size: int) -> void:
	_index = maxi(0, SIZES.find(size))
	_mat.set_shader_parameter("block", float(SIZES[_index]))
	_rect.visible = SIZES[_index] > 1


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pixel_filter"):
		set_block(SIZES[(_index + 1) % SIZES.size()])
		EventBus.notify.emit("Retro pixel filter: %s" % ("off" if SIZES[_index] == 1 else "%dx" % SIZES[_index]))
