class_name Visuals
## Placeholder art + the hook for real 3D models.
##
## HOW TO SWAP IN REAL MODELS: drop a file named "<key>.glb" into
## res://assets/models/ (e.g. "forge.glb", "adventurer_warrior.glb").
## Anything built through Visuals.model() will automatically use it instead
## of the grey-box placeholder. No code changes needed.

const MODEL_DIR := "res://assets/models/"


static func model(key: String, fallback: Node3D) -> Node3D:
	for ext in ["glb", "gltf", "tscn"]:
		var path := "%s%s.%s" % [MODEL_DIR, key, ext]
		if ResourceLoader.exists(path):
			var scene := load(path) as PackedScene
			if scene:
				var inst := scene.instantiate() as Node3D
				inst.transform = fallback.transform
				fallback.free()
				return inst
	return fallback


static func mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


static func box(size: Vector3, color: Color, pos := Vector3.ZERO, emission := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat(color, emission)
	mi.position = pos
	return mi


static func cylinder(radius: float, height: float, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = pos
	return mi


static func sphere(radius: float, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = pos
	return mi


static func label(text: String, pos: Vector3, size := 48, color := Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = size
	l.modulate = color
	l.outline_size = 10
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.004
	return l


## A solid wall/floor block with collision on the "world" layer.
static func solid(size: Vector3, color: Color, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.add_child(box(size, color))
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	return body
