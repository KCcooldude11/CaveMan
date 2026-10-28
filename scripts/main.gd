extends Node3D
## Entry point. Builds the (grey-box) village and shop in code, spawns the
## player and UI, and runs the day -> night -> day loop.
##
## Layout (top view, +Z is "south" towards the village):
##
##     [Forge]     [Workbench]     [Jeweler]        <- back wall (z = -5)
##  [Supply]                         [Ledger]
##     [Bed]                       [Upgrades]
##            [====== Counter ======]
##                 (customer line)
##   ------------------  door  ------------------   <- front wall (z = 5)
##                       path to village / dungeon gate

const Shop := preload("res://scripts/world/shop.gd")
const Player := preload("res://scripts/world/player.gd")
const UIRoot := preload("res://scripts/ui/ui_root.gd")
const PixelFilter := preload("res://scripts/world/pixel_filter.gd")

## Points of interest around the village.
const TAVERN_POS := Vector3(-16, 0, 24)
const BOARD_POS := Vector3(-6, 0, 19.8)
const MERCHANT_POS := Vector3(10, 0, 21)
const MINE_POS := Vector3(-24, 0, -12)
const GROVE_POS := Vector3(20, 0, -8)
## Areas kept free of random trees: [center, half-size] in x/z.
const CLEAR_ZONES := [
	[Vector2(0, 0), Vector2(8, 8)],          # shop
	[Vector2(0, 16), Vector2(32, 2.5)],      # east-west road
	[Vector2(0, 11), Vector2(2.5, 6)],       # path to the shop door
	[Vector2(-16, 23), Vector2(6, 5)],       # tavern
	[Vector2(-4, 21), Vector2(9, 5)],        # village square + notice board
	[Vector2(10, 21.5), Vector2(3.5, 3)],    # merchant
	[Vector2(-24, -12), Vector2(5, 5)],      # mine
	[Vector2(20, -8), Vector2(6, 6)],        # grove
	[Vector2(28, 16), Vector2(3, 5)],        # dungeon gate
]

const SHOP_W := 12.0
const SHOP_D := 10.0
const WALL_H := 3.4

var player: CharacterBody3D
var shop: Node3D
var ui: CanvasLayer
var sun: DirectionalLight3D
var env: Environment


func _ready() -> void:
	_setup_input()
	ui = UIRoot.new()
	add_child(ui)
	_build_environment()
	_build_village()
	_build_shop()

	player = Player.new()
	add_child(player)
	player.global_position = Vector3(0, 0.1, 0.8)
	player.facing = Vector3(0, 0, 1)  # toward the counter / door
	player.snap_camera()
	add_child(PixelFilter.new())

	ui.player = player
	EventBus.sleep_requested.connect(_on_sleep)
	EventBus.time_changed.connect(_update_sun)

	if GameState.load_game():
		EventBus.notify.emit("Welcome back! Day %d." % GameState.day)
	else:
		EventBus.notify.emit("Welcome to your new shop! Craft gear, sell it to adventurers.")
	_begin_day()


func _begin_day() -> void:
	Village.start_day(GameState.day)
	AdventurerManager.plan_day()
	TimeManager.start_day()


func _on_sleep() -> void:
	if ui.summary_open():
		return
	TimeManager.running = false
	shop.clear_all()
	var night := AdventurerManager.run_night()
	GameState.add_renown(int(night["renown"]))
	var lines: Array = night["lines"]
	var apprentice := GameState.run_apprentice()
	if apprentice != "":
		lines.push_front("[color=#9fd8ff]%s[/color]" % apprentice)
	var finished_day := GameState.day
	GameState.day += 1
	GameState.save_game()
	ui.show_summary(finished_day, lines, int(night["renown"]), func(): _begin_day())


func _update_sun(minutes: int) -> void:
	# Sun sweeps across the sky; sky darkens at dusk.
	var t := clampf((minutes - 6 * 60) / (14.0 * 60.0), 0.0, 1.0)  # 0 at 6:00, 1 at 20:00
	sun.rotation_degrees = Vector3(-10 - 160 * t, 30, 0)
	var day_amount := clampf(sin(t * PI) * 1.4, 0.0, 1.0)
	if minutes > 20 * 60:
		day_amount = 0.0
	sun.light_energy = lerpf(0.05, 1.2, day_amount)
	env.ambient_light_energy = lerpf(0.15, 0.6, day_amount)
	env.background_energy_multiplier = lerpf(0.1, 1.0, day_amount)


# --- Input -----------------------------------------------------------------

func _setup_input() -> void:
	# Defined in code so the project file stays readable. Rebind here.
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT], "jump": [KEY_SPACE], "interact": [KEY_E],
		"strike": [KEY_SPACE, KEY_E], "pause": [KEY_ESCAPE], "ledger": [KEY_TAB],
		"pixel_filter": [KEY_F2],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("interact", click)
	var click2 := click.duplicate()
	InputMap.action_add_event("strike", click2)


# --- World building ----------------------------------------------------------

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("4a7fc1")
	sky_mat.sky_horizon_color = Color("c9d8e8")
	sky_mat.ground_horizon_color = Color("8a9a7a")
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_bloom = 0.15
	we.environment = env
	# A soft background blur sells the "tiny diorama" HD-2D look.
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 22.0
	attrs.dof_blur_far_transition = 12.0
	attrs.dof_blur_amount = 0.08
	we.camera_attributes = attrs
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)


func _build_village() -> void:
	add_child(Visuals.solid(Vector3(120, 1, 120), "grass", Vector3(0, -0.5, 0)))
	# Dirt road: shop door -> village (west) and -> dungeon gate (east).
	add_child(Visuals.box(Vector3(3, 0.02, 12), "dirt", Vector3(0, 0.01, 11)))
	add_child(Visuals.box(Vector3(60, 0.02, 3), "dirt", Vector3(0, 0.01, 16)))

	var houses := [Vector3(-22, 0, 8), Vector3(-4, 0, 36), Vector3(16, 0, 30), Vector3(-28, 0, 27), Vector3(24, 0, 26)]
	for h in houses:
		add_child(Visuals.model("house", _house_placeholder(h)))
	_build_points_of_interest()

	# 2D pixel-art foliage scattered around (billboard sprites), kept out of
	# the shop, the road and the points of interest.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 60:
		var p := Vector3(rng.randf_range(-45, 45), 0, rng.randf_range(-40, 45))
		if _is_clear(p, 3.0):
			add_child(Visuals.billboard("tree", p))
	for i in 40:
		var p := Vector3(rng.randf_range(-32, 32), 0, rng.randf_range(-15, 35))
		if _is_clear(p, 1.2):
			add_child(Visuals.billboard("bush", p))
	# A few trees around the woodcutter's grove.
	for off in [Vector3(-3, 0, -3), Vector3(3, 0, -4), Vector3(4, 0, 2), Vector3(-4, 0, 3), Vector3(0, 0, -5)]:
		add_child(Visuals.billboard("tree", GROVE_POS + off))

	# The dungeon gate where adventurers head off to.
	var gate := Node3D.new()
	gate.position = Vector3(28, 0, 16)
	gate.add_child(Visuals.box(Vector3(1.2, 5, 1.2), "stone", Vector3(0, 2.5, -2.5)))
	gate.add_child(Visuals.box(Vector3(1.2, 5, 1.2), "stone", Vector3(0, 2.5, 2.5)))
	gate.add_child(Visuals.box(Vector3(1.4, 1.2, 6.2), "stone", Vector3(0, 5.4, 0)))
	gate.add_child(Visuals.box(Vector3(0.3, 4.4, 3.8), Color("120d0a"), Vector3(0.4, 2.2, 0)))
	gate.add_child(Visuals.label("DUNGEON GATE", Vector3(-0.8, 6.6, 0), 96, Color("ff9a6a")))
	add_child(Visuals.model("dungeon_gate", gate))


func _is_clear(p: Vector3, margin: float) -> bool:
	for z in CLEAR_ZONES:
		var c: Vector2 = z[0]
		var half: Vector2 = z[1]
		if absf(p.x - c.x) < half.x + margin and absf(p.z - c.y) < half.y + margin:
			return false
	for h in [Vector3(-22, 0, 8), Vector3(-4, 0, 36), Vector3(16, 0, 30), Vector3(-28, 0, 27), Vector3(24, 0, 26)]:
		if p.distance_to(h) < 4.0 + margin:
			return false
	return true


func _build_points_of_interest() -> void:
	# Tavern: a long building with a barkeep and benches out front.
	var tavern := Node3D.new()
	tavern.position = TAVERN_POS
	tavern.add_child(Visuals.solid(Vector3(9, 3.4, 5), "plaster", Vector3(0, 1.7, 0)))
	tavern.add_child(Visuals.box(Vector3(9.1, 0.6, 5.1), "dark_wood", Vector3(0, 0.3, 0)))
	var roof := Visuals.box(Vector3(4.2, 4.2, 9.6), "roof", Vector3(0, 3.6, 0))
	roof.rotation_degrees = Vector3(0, 90, 45)
	roof.scale = Vector3(1.0, 0.55, 1.0)
	tavern.add_child(roof)
	tavern.add_child(Visuals.box(Vector3(1.4, 2.2, 0.1), "dark_wood", Vector3(0, 1.1, 2.52)))  # door
	var tsign := Visuals.label(DataDB.village["tavern"]["name"].to_upper(), Vector3(0, 3.0, 2.7), 80, Color("ffd27a"))
	tsign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	tavern.add_child(tsign)
	for x in [-3.0, 3.0]:
		tavern.add_child(Visuals.box(Vector3(1.6, 0.8, 0.8), "dark_wood", Vector3(x, 0.4, 4.0)))   # table
		tavern.add_child(Visuals.box(Vector3(1.6, 0.4, 0.3), "dark_wood", Vector3(x, 0.2, 3.3)))   # bench
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.6, 3.2)
	lamp.light_color = Color("ffc070")
	lamp.light_energy = 1.4
	lamp.omni_range = 6.0
	tavern.add_child(lamp)
	add_child(tavern)
	_place(Stations.villager(ui, "barkeep", "tavern", "Talk to the barkeep (tavern)", "Barkeep Moll"), TAVERN_POS + Vector3(1.2, 0, 3.3), 0)

	# Notice board in the village square, watched by the town guard.
	var board := Node3D.new()
	board.add_child(Visuals.box(Vector3(0.15, 2.0, 0.15), "dark_wood", Vector3(-1.0, 1.0, 0)))
	board.add_child(Visuals.box(Vector3(0.15, 2.0, 0.15), "dark_wood", Vector3(1.0, 1.0, 0)))
	board.add_child(Visuals.box(Vector3(2.3, 1.2, 0.1), "wood_floor", Vector3(0, 1.4, 0)))
	board.add_child(Visuals.box(Vector3(2.5, 0.12, 0.3), "dark_wood", Vector3(0, 2.05, 0)))
	for i in 5:  # pinned notices
		board.add_child(Visuals.box(Vector3(0.3, 0.38, 0.02), Color("efe8d8"), Vector3(-0.8 + i * 0.4, 1.4 + (0.15 if i % 2 else -0.1), 0.07)))
	board.add_child(Visuals.label("NOTICE BOARD", Vector3(0, 2.7, 0), 40))
	var nb := Stations.MenuObject.new()
	nb.menu = "notice_board"
	nb.ui = ui
	nb.prompt_text = "Read the notice board (forecast & commissions)"
	nb.setup_body("notice_board", Vector3(2.4, 2.2, 0.4), board)
	_place(nb, BOARD_POS, 0)
	var guard := PixelCharacter.new()
	guard.setup("guard")
	add_child(guard)
	guard.global_position = BOARD_POS + Vector3(1.9, guard.position.y, 0.6)

	_place(Stations.merchant_stop(ui), MERCHANT_POS, 0)

	# Old mine: a rocky mound with a timber-framed entrance.
	var mine := Node3D.new()
	mine.add_child(Visuals.box(Vector3(7, 3.5, 5), "stone", Vector3(0, 1.75, -1.5)))
	mine.add_child(Visuals.box(Vector3(5, 1.5, 4), "stone", Vector3(0, 4.0, -2.0)))
	mine.add_child(Visuals.box(Vector3(1.8, 2.2, 0.2), Color("0e0b09"), Vector3(0, 1.1, 1.02)))
	mine.add_child(Visuals.box(Vector3(0.25, 2.5, 0.25), "dark_wood", Vector3(-1.0, 1.25, 1.1)))
	mine.add_child(Visuals.box(Vector3(0.25, 2.5, 0.25), "dark_wood", Vector3(1.0, 1.25, 1.1)))
	mine.add_child(Visuals.box(Vector3(2.4, 0.3, 0.3), "dark_wood", Vector3(0, 2.5, 1.1)))
	mine.add_child(Visuals.box(Vector3(1.0, 0.6, 0.7), "iron", Vector3(1.8, 0.3, 2.0)))  # ore cart
	_place(Stations.gatherable("mine", "Scavenge ore", mine, Vector3(7, 3.5, 5)), MINE_POS, 0)

	# Woodcutter's grove: a log pile and a chopping stump.
	var grove := Node3D.new()
	for i in 3:
		var wood_log := Visuals.cylinder(0.25, 2.2, Color("6b4a2b"), Vector3(0, 0.25 + i * 0.4, -0.5 + i * 0.15))
		wood_log.rotation_degrees.z = 90
		grove.add_child(wood_log)
	grove.add_child(Visuals.cylinder(0.4, 0.6, Color("7a5231"), Vector3(1.8, 0.3, 0.6)))
	grove.add_child(Visuals.box(Vector3(0.08, 0.7, 0.08), "dark_wood", Vector3(1.8, 0.85, 0.6)))
	grove.add_child(Visuals.box(Vector3(0.3, 0.2, 0.06), "iron", Vector3(1.85, 1.15, 0.6)))
	_place(Stations.gatherable("grove", "Chop wood", grove, Vector3(3.0, 1.2, 1.6)), GROVE_POS, 0)


func _house_placeholder(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = randf() * TAU
	n.add_child(Visuals.solid(Vector3(5, 3, 4), "plaster", Vector3(0, 1.5, 0)))
	n.add_child(Visuals.box(Vector3(5.1, 0.6, 4.1), "dark_wood", Vector3(0, 0.3, 0)))
	var roof := Visuals.box(Vector3(3.6, 3.6, 4.4), "roof", Vector3(0, 3.0, 0))
	roof.rotation_degrees.z = 45
	roof.scale = Vector3(1.0, 0.55, 1.0)
	n.add_child(roof)
	return n


## A wall that disappears while it blocks the camera's view of the player.
## `outward` points out of the building; indoors, walls facing the camera hide.
func _cutaway_wall(parent: Node, size: Vector3, look: Variant, pos: Vector3, outward: Vector3) -> void:
	var w := Visuals.solid(size, look, pos)
	parent.add_child(w)
	w.add_to_group("cutaway")
	w.set_meta("mesh", w.get_child(0))
	w.set_meta("aabb", AABB(pos - size / 2.0, size).grow(0.05))
	w.set_meta("outward", outward)
	w.set_meta("indoors", AABB(Vector3(-SHOP_W / 2.0, 0, -SHOP_D / 2.0), Vector3(SHOP_W, WALL_H, SHOP_D)))


func _build_shop() -> void:
	var hw := SHOP_W / 2.0
	var hd := SHOP_D / 2.0
	var root := Node3D.new()
	root.name = "ShopBuilding"
	add_child(root)

	root.add_child(Visuals.solid(Vector3(SHOP_W, 0.1, SHOP_D), "wood_floor", Vector3(0, 0.05, 0)))
	_cutaway_wall(root, Vector3(SHOP_W, WALL_H, 0.2), "plaster", Vector3(0, WALL_H / 2, -hd), Vector3.FORWARD)
	_cutaway_wall(root, Vector3(0.2, WALL_H, SHOP_D), "plaster", Vector3(-hw, WALL_H / 2, 0), Vector3.LEFT)
	_cutaway_wall(root, Vector3(0.2, WALL_H, SHOP_D), "plaster", Vector3(hw, WALL_H / 2, 0), Vector3.RIGHT)
	# Front wall with a 2m door gap in the middle.
	var seg := (SHOP_W - 2.0) / 2.0
	_cutaway_wall(root, Vector3(seg, WALL_H, 0.2), "plaster", Vector3(-1.0 - seg / 2, WALL_H / 2, hd), Vector3.BACK)
	_cutaway_wall(root, Vector3(seg, WALL_H, 0.2), "plaster", Vector3(1.0 + seg / 2, WALL_H / 2, hd), Vector3.BACK)
	_cutaway_wall(root, Vector3(2.0, 0.9, 0.2), "plaster", Vector3(0, WALL_H - 0.45, hd), Vector3.BACK)
	# Timber frame along the base of the walls.
	for z in [-hd, hd]:
		root.add_child(Visuals.box(Vector3(SHOP_W + 0.1, 0.4, 0.25), "dark_wood", Vector3(0, 0.2, z)))
	for x in [-hw, hw]:
		root.add_child(Visuals.box(Vector3(0.25, 0.4, SHOP_D + 0.1), "dark_wood", Vector3(x, 0.2, 0)))

	# Roof: visible from outside, hidden while you're indoors.
	var roof := Node3D.new()
	var slab := Visuals.box(Vector3(SHOP_W + 1.0, 0.3, SHOP_D + 1.0), "roof", Vector3(0, WALL_H + 0.15, 0))
	roof.add_child(slab)
	var ridge := Visuals.box(Vector3(SHOP_W + 1.0, 1.4, SHOP_D * 0.55), "roof", Vector3(0, WALL_H + 0.9, 0))
	roof.add_child(ridge)
	roof.add_to_group("roof")
	roof.set_meta("indoors", AABB(Vector3(-hw, 0, -hd), Vector3(SHOP_W, WALL_H, SHOP_D)))
	root.add_child(roof)
	var shop_sign := Visuals.label("FORGE & FORTUNE", Vector3(0, WALL_H + 0.6, hd + 0.6), 120, Color("ffd27a"))
	shop_sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	roof.add_child(shop_sign)

	for p in [Vector3(-3, 3.0, -2), Vector3(3, 3.0, -2), Vector3(0, 3.0, 2.5)]:
		var lamp := OmniLight3D.new()
		lamp.position = p
		lamp.light_color = Color("ffd9a0")
		lamp.light_energy = 1.0
		lamp.omni_range = 7.0
		root.add_child(lamp)

	# Furniture & stations.
	_place(Stations.forge(ui), Vector3(-4.0, 0.1, -4.0), 0)
	_place(Stations.workbench(ui), Vector3(0, 0.1, -4.3), 0)
	_place(Stations.jeweler(ui), Vector3(4.0, 0.1, -4.2), 0)
	_place(Stations.menu_object(ui, "supply", "Supply Order Board", "supply_board", "dark_wood", Vector3(0.3, 1.8, 1.6)), Vector3(-5.7, 0.1, -1.0), 0)
	_place(Stations.menu_object(ui, "ledger", "Adventurer Ledger", "ledger_board", Color("3e5a7a"), Vector3(0.3, 1.8, 1.6)), Vector3(5.7, 0.1, -1.0), 0)
	_place(Stations.menu_object(ui, "upgrades", "Upgrade Lectern", "lectern", Color("7a3e5a"), Vector3(0.7, 1.1, 0.7)), Vector3(4.5, 0.1, 1.8), 0)
	_place(Stations.bed(), Vector3(-4.6, 0.1, 2.6), 0)

	shop = Shop.new()
	shop.name = "ShopFloor"
	shop.ui = ui
	add_child(shop)
	var counter := Stations.counter(shop)
	_place(counter, Vector3(0, 0.1, 2.2), 0)
	shop.counter_front = Vector3(0, 0.1, 3.2)
	shop.queue_dir = Vector3(0, 0, 1)
	shop.spawn_point = Vector3(-30, 0.1, 16)
	shop.arrive_path = [Vector3(0, 0.1, 16), Vector3(0, 0.1, 7.5)]
	shop.exit_path = [Vector3(0, 0.1, 7.5), Vector3(0, 0.1, 16), Vector3(27, 0.1, 16)]


func _place(node: Node3D, pos: Vector3, rot_y: float) -> void:
	add_child(node)
	node.position = pos
	node.rotation.y = rot_y
