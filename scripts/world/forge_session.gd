extends Node3D
## First-person forging at the anvil.
##
## The camera drops to a close view over the anvil with a glowing bar of hot
## metal on it. A pixel-art hand holding a hammer follows the mouse. For each
## strike a target appears on the metal with a ring closing in on it:
## move the hammer over the target and CLICK as the ring meets it.
##   WHERE you hit (hammer over the spot) and WHEN you hit (ring on the spot)
##   both count. Perfect strikes ring out and throw sparks.
## Station upgrades and mastery make the targets bigger; harder recipes close
## the rings faster and need more strikes.

signal finished(quality: int)

const HAND_TEX := preload("res://assets/sprites/hammer_hand.png")
const SFX := {
	"perfect": preload("res://assets/sounds/anvil_perfect.wav"),
	"good": preload("res://assets/sounds/anvil_good.wav"),
	"miss": preload("res://assets/sounds/anvil_miss.wav"),
	"whoosh": preload("res://assets/sounds/whoosh.wav"),
}
const HAND_SCALE := 5.0
const HEAD := Vector2(15.5, 17.5)   # hammer head centre in the sprite (pixels)
const FIST := Vector2(41, 43)       # swing pivot in the sprite (pixels)

var anvil_top := Vector3.ZERO       # world position of the anvil's face
var level := 1
var power := 8
var strikes_total := 5
var strikes_done := 0
var score := 0
var ring_time := 1.3
var target_radius := 30.0

var _camera: Camera3D
var _prev_camera: Camera3D
var _bar: MeshInstance3D
var _bar_mat: StandardMaterial3D
var _sparks: CPUParticles3D
var _light: OmniLight3D
var _overlay: CanvasLayer
var _draw: Control
var _hand: TextureRect
var _info: Label
var _sfx: AudioStreamPlayer
var _target3d := Vector3.ZERO
var _t := 0.0
var _gap := 0.6                     # pause before the next target appears
var _swing := 0.0                   # >0 while the hammer is coming down
var _feedback := ""
var _feedback_t := 0.0
var _feedback_pos := Vector2.ZERO
var _shake := 0.0
var _done := false
var _heat := 1.0


func setup(top: Vector3, station_level: int, recipe_power: int) -> void:
	anvil_top = top
	level = station_level
	power = recipe_power
	strikes_total = 5 + (1 if recipe_power >= 15 else 0) + (1 if recipe_power >= 25 else 0)
	ring_time = clampf(1.5 - recipe_power * 0.02, 0.8, 1.5)
	target_radius = 28.0 + 6.0 * (station_level - 1)


func _ready() -> void:
	_prev_camera = get_viewport().get_camera_3d()
	_camera = Camera3D.new()
	_camera.fov = 48
	add_child(_camera)
	_camera.global_position = anvil_top + Vector3(0, 0.78, 0.62)
	_camera.look_at(anvil_top + Vector3(0, 0, -0.03), Vector3.UP)
	_camera.current = true

	_bar = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.42, 0.045, 0.1)
	_bar.mesh = mesh
	_bar_mat = StandardMaterial3D.new()
	_bar_mat.emission_enabled = true
	_bar.material_override = _bar_mat
	add_child(_bar)
	_bar.global_position = anvil_top + Vector3(0, 0.024, 0)
	_set_heat(1.0)

	_light = OmniLight3D.new()
	_light.light_color = Color("ff9a4a")
	_light.omni_range = 1.6
	_light.light_energy = 2.0
	add_child(_light)
	_light.global_position = anvil_top + Vector3(0, 0.25, 0.1)

	_sparks = CPUParticles3D.new()
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.amount = 28
	_sparks.lifetime = 0.55
	_sparks.explosiveness = 1.0
	_sparks.direction = Vector3.UP
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 1.2
	_sparks.initial_velocity_max = 2.8
	_sparks.gravity = Vector3(0, -6, 0)
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.012, 0.012, 0.012)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color("ffd27a")
	spark_mat.emission_enabled = true
	spark_mat.emission = Color("ffb04a")
	spark_mat.emission_energy_multiplier = 4.0
	spark_mesh.material = spark_mat
	_sparks.mesh = spark_mesh
	add_child(_sparks)

	_overlay = CanvasLayer.new()
	_overlay.layer = 3
	add_child(_overlay)
	_draw = Control.new()
	_draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_draw_overlay)
	_overlay.add_child(_draw)
	_info = Label.new()
	_info.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_info.offset_top = 24
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_theme_font_size_override("font_size", 22)
	_info.add_theme_constant_override("outline_size", 8)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_overlay.add_child(_info)
	_hand = TextureRect.new()
	_hand.texture = HAND_TEX
	_hand.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hand.size = Vector2(64, 64) * HAND_SCALE
	_hand.pivot_offset = FIST * HAND_SCALE
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_hand)
	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)

	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_hand_to(get_viewport().get_mouse_position())
	_update_info()


func _exit_tree() -> void:
	if _prev_camera and is_instance_valid(_prev_camera):
		_prev_camera.current = true


# --- Rules ---------------------------------------------------------------------

func _new_target() -> void:
	_target3d = anvil_top + Vector3(randf_range(-0.16, 0.16), 0.05, randf_range(-0.03, 0.03))
	_t = 0.0


func has_target() -> bool:
	return _gap <= 0.0 and not _done


## Screen position of the current target.
func target_screen() -> Vector2:
	return _camera.unproject_position(_target3d)


## Current radius of the closing ring (pixels).
func ring_radius() -> float:
	return target_radius * (1.0 + 3.0 * (1.0 - _t / ring_time))


## Where the hammer head is on screen.
func hammer_head() -> Vector2:
	return _hand.position + HEAD * HAND_SCALE


## Score a strike from how far off the hammer was (0 = dead centre, 1 = edge)
## and how early/late (0 = ring exactly on the target).
static func strike_score(pos_err: float, time_err: float) -> int:
	if pos_err <= 0.55 and time_err <= 0.18:
		return 2
	if pos_err <= 1.0 and time_err <= 0.45:
		return 1
	return 0


static func quality_for(total: int, strikes: int) -> int:
	var frac := float(total) / float(2 * strikes)
	if frac >= 0.9:
		return 3
	if frac >= 0.6:
		return 2
	if frac >= 0.3:
		return 1
	return 0


func strike() -> void:
	if not has_target():
		return
	_swing = 0.14
	var pos_err := hammer_head().distance_to(target_screen()) / target_radius
	var time_err := absf(ring_radius() - target_radius) / target_radius
	_resolve(strike_score(pos_err, time_err))


func _resolve(points: int) -> void:
	score += points
	strikes_done += 1
	_feedback_pos = target_screen()
	_feedback_t = 0.8
	match points:
		2:
			_feedback = "PERFECT!"
			_play("perfect")
			_shake = 10.0
			_burst(true)
		1:
			_feedback = "Good"
			_play("good")
			_shake = 4.0
			_burst(false)
		_:
			_feedback = "Miss"
			_play("miss")
	_set_heat(_heat - 0.12)
	if points > 0:
		_bar.scale.x += 0.03 * points
		_bar.scale.y = maxf(0.6, _bar.scale.y - 0.05 * points)
	_gap = 0.45
	_update_info()
	if strikes_done >= strikes_total:
		_done = true
		var q := quality_for(score, strikes_total)
		_info.text = "%s!  (%d / %d)" % [DataDB.QUALITIES[q]["name"], score, strikes_total * 2]
		await get_tree().create_timer(1.1).timeout
		_finish(q)


func _finish(q: int) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	finished.emit(q)
	queue_free()


## Walking away mid-forge: the remaining strikes count as misses.
func force_finish() -> void:
	if _done:
		return
	_done = true
	_finish(quality_for(score, strikes_total))


## For tests and demos: land a strike with the given quality on the current target.
func auto_strike(points: int) -> void:
	if not has_target():
		_gap = 0.0
		_new_target()
	_hand_to(target_screen())
	_t = ring_time
	if points == 1:
		_t = ring_time * 0.75
	elif points == 0:
		_t = 0.0
	strike()


# --- Frame loop -----------------------------------------------------------------

func _process(delta: float) -> void:
	if _gap > 0.0 and not _done:
		_gap -= delta
		if _gap <= 0.0:
			_new_target()
	elif not _done:
		_t += delta
		if _t > ring_time * 1.25:  # too late: the metal cools under the ring
			_resolve(0)
	_swing = maxf(0.0, _swing - delta)
	_feedback_t -= delta
	_shake = maxf(0.0, _shake - 50.0 * delta)
	_hand.rotation = -0.15 if _swing > 0.0 else -0.75
	_camera.h_offset = randf_range(-1, 1) * _shake * 0.0006
	_camera.v_offset = randf_range(-1, 1) * _shake * 0.0006
	_light.light_energy = 1.0 + 2.0 * _heat
	_draw.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hand_to(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if has_target():
			strike()
		else:
			_swing = 0.14
			_play("whoosh")
	elif event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		force_finish()


func _hand_to(screen: Vector2) -> void:
	_hand.position = screen - HEAD * HAND_SCALE


func _set_heat(h: float) -> void:
	_heat = clampf(h, 0.15, 1.0)
	var c := Color("5a1e10").lerp(Color("ffcf6a"), _heat)
	_bar_mat.albedo_color = c
	_bar_mat.emission = c
	_bar_mat.emission_energy_multiplier = 0.5 + 2.5 * _heat


func _burst(big: bool) -> void:
	_sparks.global_position = _target3d
	_sparks.amount = 40 if big else 16
	_sparks.restart()
	_sparks.emitting = true


func _play(key: String) -> void:
	_sfx.stream = SFX[key]
	_sfx.pitch_scale = randf_range(0.94, 1.06)
	_sfx.play()


func _update_info() -> void:
	_info.text = "Strike %d / %d  -  move the hammer onto the glowing spot and CLICK as the ring closes" % [mini(strikes_done + 1, strikes_total), strikes_total]


func _draw_overlay() -> void:
	if has_target():
		var c := target_screen()
		var r := ring_radius()
		_draw.draw_circle(c, target_radius, Color(1.0, 0.75, 0.3, 0.22))
		_draw.draw_arc(c, target_radius, 0, TAU, 48, Color("ffd27a"), 3.0)
		_draw.draw_arc(c, target_radius * 0.55, 0, TAU, 32, Color(1, 0.95, 0.7, 0.8), 2.0)
		var closeness := clampf(1.0 - absf(r - target_radius) / (target_radius * 3.0), 0.0, 1.0)
		_draw.draw_arc(c, r, 0, TAU, 64, Color(1, 1, 1, 0.35 + 0.65 * closeness), 3.0 + 3.0 * closeness)
	if _feedback_t > 0.0:
		var col := Color("ffd27a") if _feedback == "PERFECT!" else (Color("8fd18f") if _feedback == "Good" else Color("e06c6c"))
		col.a = clampf(_feedback_t * 1.5, 0.0, 1.0)
		var font := ThemeDB.fallback_font
		_draw.draw_string_outline(font, _feedback_pos + Vector2(-80, -target_radius - 24 - (0.8 - _feedback_t) * 40), _feedback, HORIZONTAL_ALIGNMENT_CENTER, 160, 30, 8, Color(0, 0, 0, col.a))
		_draw.draw_string(font, _feedback_pos + Vector2(-80, -target_radius - 24 - (0.8 - _feedback_t) * 40), _feedback, HORIZONTAL_ALIGNMENT_CENTER, 160, 30, col)
	# Quality meter at the bottom.
	var w := 360.0
	var x := (_draw.size.x - w) / 2.0
	var y := _draw.size.y - 70.0
	_draw.draw_rect(Rect2(x, y, w, 14), Color(0, 0, 0, 0.6))
	var frac := float(score) / float(2 * strikes_total)
	_draw.draw_rect(Rect2(x, y, w * frac, 14), Color("ffc94a"))
	var marks := { 0.3: "Common", 0.6: "Fine", 0.9: "Masterwork" }
	for f in marks:
		_draw.draw_line(Vector2(x + w * f, y - 3), Vector2(x + w * f, y + 17), Color.WHITE, 2.0)
		_draw.draw_string(ThemeDB.fallback_font, Vector2(x + w * f - 50, y - 8), marks[f], HORIZONTAL_ALIGNMENT_CENTER, 100, 14, Color(1, 1, 1, 0.85))
