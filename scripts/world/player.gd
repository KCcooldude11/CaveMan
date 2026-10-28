extends CharacterBody3D
## Third-person controller for the smith, drawn as a 2D pixel sprite.
## WASD moves relative to the camera, the mouse orbits the camera, the wheel
## zooms, E / left click interacts with whatever is right in front of you.
##
## The camera floats at a fixed downward angle with a narrow FOV, which gives
## the "diorama" look of HD-2D games like EthrA and Octopath Traveler.

const WALK_SPEED := 3.5
const SPRINT_SPEED := 5.5
const JUMP_VELOCITY := 4.2
const MOUSE_SENS := 0.004
const CAM_PITCH_DEG := -35.0
const CAM_FOV := 38.0
const ZOOM_MIN := 5.0
const ZOOM_MAX := 16.0
const REACH := 1.1          # how far in front of you interaction checks
const REACH_RADIUS := 0.9

var camera: Camera3D
var cam_yaw: Node3D          # rotates around Y, follows the player
var cam_pitch: Node3D
var sprite: PixelCharacter
var input_enabled := true
var facing := Vector3(0, 0, 1)
var zoom := 9.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _probe := SphereShape3D.new()


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.6
	cs.shape = shape
	cs.position.y = 0.8
	add_child(cs)

	sprite = PixelCharacter.new()
	add_child(sprite)
	sprite.setup("smith")

	# Camera rig lives in world space (top_level) so it doesn't spin with us.
	cam_yaw = Node3D.new()
	cam_yaw.top_level = true
	add_child(cam_yaw)
	cam_pitch = Node3D.new()
	cam_pitch.rotation_degrees.x = CAM_PITCH_DEG
	cam_yaw.add_child(cam_pitch)
	camera = Camera3D.new()
	camera.fov = CAM_FOV
	camera.position.z = zoom
	cam_pitch.add_child(camera)
	_probe.radius = REACH_RADIUS

	EventBus.menu_opened.connect(func(): set_input_enabled(false))
	EventBus.menu_closed.connect(func(): set_input_enabled(true))
	set_input_enabled(true)


func set_input_enabled(on: bool) -> void:
	input_enabled = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


## Point the camera at a yaw (radians). 0 = looking north (-Z).
func set_camera_yaw(yaw: float) -> void:
	cam_yaw.rotation.y = yaw


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw.rotate_y(-event.relative.x * MOUSE_SENS)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom = clampf(zoom + (-0.8 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), ZOOM_MIN, ZOOM_MAX)
	elif event.is_action_pressed("interact"):
		var target := get_target()
		if target:
			target.interact(self)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The interactable closest to the spot just in front of the smith.
func get_target() -> Node:
	if not is_inside_tree():
		return null
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _probe
	q.collision_mask = 2
	var probe_pos := global_position + facing * REACH + Vector3(0, 0.8, 0)
	q.transform = Transform3D(Basis(), probe_pos)
	var best: Node = null
	var best_d := INF
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 16):
		var c: Object = hit["collider"]
		if c != null and c.has_method("interact"):
			var d := (c as Node3D).global_position.distance_to(probe_pos)
			if d < best_d:
				best_d = d
				best = c
	return best


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	var dir := Vector3.ZERO
	if input_enabled:
		var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		dir = (cam_yaw.global_transform.basis * Vector3(v.x, 0, v.y))
		dir.y = 0
		dir = dir.normalized()
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
	if dir != Vector3.ZERO:
		facing = dir
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()
	sprite.face(dir)
	sprite.speed_scale = 1.5 if speed == SPRINT_SPEED and dir != Vector3.ZERO else 1.0


func _process(delta: float) -> void:
	# Smoothly follow, aiming at chest height.
	var target := global_position + Vector3(0, 1.0, 0)
	cam_yaw.global_position = cam_yaw.global_position.lerp(target, clampf(delta * 10.0, 0.0, 1.0))
	camera.position.z = lerpf(camera.position.z, zoom, clampf(delta * 8.0, 0.0, 1.0))
	_update_cutaways()


## Hide walls that stand between the camera and the player, and the roof
## while the player is indoors - so the camera can always see you.
func _update_cutaways() -> void:
	var cam_pos := camera.global_position
	var me := global_position + Vector3(0, 1.0, 0)
	for wall in get_tree().get_nodes_in_group("cutaway"):
		var box: AABB = wall.get_meta("aabb")
		var blocking := box.intersects_segment(cam_pos, me) != null
		# Indoors: also hide every wall on the camera's side (dollhouse view).
		if not blocking and wall.get_meta("indoors").has_point(me):
			var to_cam := cam_pos - box.get_center()
			blocking = wall.get_meta("outward").dot(Vector3(to_cam.x, 0, to_cam.z).normalized()) > 0.2
		wall.get_meta("mesh").visible = not blocking
	for roof in get_tree().get_nodes_in_group("roof"):
		var area: AABB = roof.get_meta("indoors")
		roof.visible = not area.has_point(global_position + Vector3(0, 0.5, 0))


## Jump the camera straight to the player (after spawning / teleporting).
func snap_camera() -> void:
	cam_yaw.global_position = global_position + Vector3(0, 1.0, 0)
