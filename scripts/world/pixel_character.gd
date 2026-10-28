class_name PixelCharacter
extends AnimatedSprite3D
## A 2D pixel-art character standing in the 3D world (HD-2D / EthrA style).
##
## Loads a sheet from res://assets/sprites/<name>.png laid out as:
##   rows    = front, back, side (facing right; left is the same row flipped)
##   columns = idle0, idle1, walk0, walk1, walk2, walk3
## Each frame is FRAME_SIZE pixels. The sprite always turns to face the camera
## (Y-axis billboard). Call face(direction) each frame and it picks the right
## row based on which way the character moves *relative to the camera*.

const FRAME_SIZE := Vector2i(32, 40)
const PIXELS_PER_METER := 16.0   # keep in sync with the world textures
const VIEWS := ["front", "back", "side"]

var view := "front"
var moving := false


func setup(sheet_name: String) -> void:
	var tex := load("res://assets/sprites/%s.png" % sheet_name) as Texture2D
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for row in VIEWS.size():
		for anim in ["idle", "walk"]:
			var anim_name: String = "%s_%s" % [anim, VIEWS[row]]
			frames.add_animation(anim_name)
			frames.set_animation_speed(anim_name, 2.0 if anim == "idle" else 8.0)
			var cols := [0, 1] if anim == "idle" else [2, 3, 4, 5]
			for col in cols:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(col * FRAME_SIZE.x, row * FRAME_SIZE.y, FRAME_SIZE.x, FRAME_SIZE.y)
				frames.add_frame(anim_name, at)
	sprite_frames = frames
	pixel_size = 1.0 / PIXELS_PER_METER
	billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD   # crisp edges + casts shadows
	shaded = true
	double_sided = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Feet on the ground: the frame's bottom row sits at y = 0.
	position.y = FRAME_SIZE.y * pixel_size / 2.0 - pixel_size
	play("idle_front")


## Pick the animation row from a world-space movement direction.
## Pass Vector3.ZERO when standing still (keeps the last facing).
func face(world_dir: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	moving = world_dir.length() > 0.05
	if moving and cam:
		var local := cam.global_transform.basis.inverse() * world_dir.normalized()
		if absf(local.x) > absf(local.z) * 1.2:
			view = "side"
			flip_h = local.x < 0.0
		else:
			view = "front" if local.z > 0.0 else "back"
			flip_h = false
	var anim := "%s_%s" % ["walk" if moving else "idle", view]
	if animation != anim:
		play(anim)
