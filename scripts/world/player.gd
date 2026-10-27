extends CharacterBody3D
## First-person controller: WASD to move, mouse to look, Shift to sprint,
## E (or left click) to interact with whatever you're looking at.

const WALK_SPEED := 4.0
const SPRINT_SPEED := 6.5
const JUMP_VELOCITY := 4.2
const MOUSE_SENS := 0.0025
const REACH := 3.5

var camera: Camera3D
var ray: RayCast3D
var input_enabled := true
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	collision_layer = 0          # nothing collides *into* the player
	collision_mask = 1           # player bumps into world geometry
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	cs.shape = shape
	cs.position.y = 0.9
	add_child(cs)

	camera = Camera3D.new()
	camera.position.y = 1.65
	camera.fov = 75
	add_child(camera)

	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -REACH)
	ray.collision_mask = 1 | 2
	camera.add_child(ray)

	EventBus.menu_opened.connect(func(): set_input_enabled(false))
	EventBus.menu_closed.connect(func(): set_input_enabled(true))
	set_input_enabled(true)


func set_input_enabled(on: bool) -> void:
	input_enabled = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		camera.rotate_x(-event.relative.y * MOUSE_SENS)
		camera.rotation.x = clampf(camera.rotation.x, -1.4, 1.4)
	elif event.is_action_pressed("interact"):
		var target := get_target()
		if target:
			target.interact(self)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func get_target() -> Node:
	if not ray.is_colliding():
		return null
	var c := ray.get_collider()
	return c if c != null and c.has_method("interact") else null


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	var dir := Vector3.ZERO
	if input_enabled:
		var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		dir = (transform.basis * Vector3(v.x, 0, v.y)).normalized()
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()
