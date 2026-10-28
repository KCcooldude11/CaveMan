class_name Visuals
## Placeholder art + the hook for real 3D models.
##
## HOW TO SWAP IN REAL MODELS: drop a file named "<key>.glb" into
## res://assets/models/ (e.g. "forge.glb", "adventurer_warrior.glb").
## Anything built through Visuals.model() will automatically use it instead
## of the grey-box placeholder. No code changes needed.

const MODEL_DIR := "res://assets/models/"
const TEXTURE_DIR := "res://assets/textures/"
## World textures are 32px tiles covering 2m, i.e. 16 pixels per meter, the
## same density as the character sprites. Matching texel density is what
## makes 2D sprites and 3D geometry look like one pixel-art world.
const TILE_METERS := 2.0

static var _tex_cache := {}


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


## Pixel-art textured material, mapped in world space so every surface gets
## the same pixel size no matter how big the box is. `tint` multiplies it.
static func tex_mat(tex_name: String, tint := Color.WHITE) -> StandardMaterial3D:
	var key := "%s/%s" % [tex_name, tint.to_html()]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEXTURE_DIR + tex_name + ".png")
	m.albedo_color = tint
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / TILE_METERS
	m.roughness = 0.95
	_tex_cache[key] = m
	return m


## `look` is either a Color (flat) or a texture name like "wood_floor".
static func box(size: Vector3, look: Variant, pos := Vector3.ZERO, emission := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = tex_mat(look) if look is String else mat(look, emission)
	mi.position = pos
	return mi


## A flat pixel-art prop (tree, bush...) that turns to face the camera.
static func billboard(sprite_name: String, pos: Vector3) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = load("res://assets/sprites/%s.png" % sprite_name)
	s.pixel_size = 1.0 / 16.0
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = true
	s.double_sided = true
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	s.position = pos + Vector3(0, s.texture.get_height() * s.pixel_size / 2.0, 0)
	return s


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
	l.pixel_size = 0.0028
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return l


## A name tag / speech bubble: same size on screen at any zoom, drawn on top.
static func tag(text: String, pos: Vector3, size := 26, color := Color.WHITE) -> Label3D:
	var l := label(text, pos, size, color)
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	return l


## A solid wall/floor block with collision on the "world" layer.
static func solid(size: Vector3, look: Variant, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.add_child(box(size, look))
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	return body
