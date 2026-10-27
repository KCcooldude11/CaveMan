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
	player.global_position = Vector3(0, 0.1, 0)
	player.rotation.y = PI  # face the counter / door

	ui.player = player
	EventBus.sleep_requested.connect(_on_sleep)
	EventBus.time_changed.connect(_update_sun)

	if GameState.load_game():
		EventBus.notify.emit("Welcome back! Day %d." % GameState.day)
	else:
		EventBus.notify.emit("Welcome to your new shop! Craft gear, sell it to adventurers.")
	_begin_day()


func _begin_day() -> void:
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
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)


func _build_village() -> void:
	add_child(Visuals.solid(Vector3(120, 1, 120), Color("6d8f4e"), Vector3(0, -0.5, 0)))
	# Dirt road: shop door -> village (west) and -> dungeon gate (east).
	add_child(Visuals.box(Vector3(3, 0.02, 12), Color("9a8462"), Vector3(0, 0.01, 11)))
	add_child(Visuals.box(Vector3(60, 0.02, 3), Color("9a8462"), Vector3(0, 0.01, 16)))

	var houses := [Vector3(-14, 0, 24), Vector3(-22, 0, 8), Vector3(-9, 0, 26), Vector3(12, 0, 25), Vector3(-26, 0, 22)]
	for h in houses:
		add_child(Visuals.model("house", _house_placeholder(h)))

	# The dungeon gate where adventurers head off to.
	var gate := Node3D.new()
	gate.position = Vector3(28, 0, 16)
	gate.add_child(Visuals.box(Vector3(1.2, 5, 1.2), Color("55524d"), Vector3(0, 2.5, -2.5)))
	gate.add_child(Visuals.box(Vector3(1.2, 5, 1.2), Color("55524d"), Vector3(0, 2.5, 2.5)))
	gate.add_child(Visuals.box(Vector3(1.4, 1.2, 6.2), Color("4a4743"), Vector3(0, 5.4, 0)))
	gate.add_child(Visuals.box(Vector3(0.3, 4.4, 3.8), Color("120d0a"), Vector3(0.4, 2.2, 0)))
	gate.add_child(Visuals.label("DUNGEON GATE", Vector3(-0.8, 6.6, 0), 96, Color("ff9a6a")))
	add_child(Visuals.model("dungeon_gate", gate))


func _house_placeholder(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = randf() * TAU
	n.add_child(Visuals.solid(Vector3(5, 3, 4), Color("c9b48a"), Vector3(0, 1.5, 0)))
	var roof := Visuals.box(Vector3(3.6, 3.6, 4.4), Color("8a3b2b"), Vector3(0, 3.0, 0))
	roof.rotation_degrees.z = 45
	roof.scale = Vector3(1.0, 0.55, 1.0)
	n.add_child(roof)
	return n


func _build_shop() -> void:
	var hw := SHOP_W / 2.0
	var hd := SHOP_D / 2.0
	var wall := Color("b8a07a")
	var root := Node3D.new()
	root.name = "ShopBuilding"
	add_child(root)

	root.add_child(Visuals.solid(Vector3(SHOP_W, 0.1, SHOP_D), Color("7a6650"), Vector3(0, 0.05, 0)))
	root.add_child(Visuals.solid(Vector3(SHOP_W, 0.2, SHOP_D), Color("5e4a36"), Vector3(0, WALL_H, 0)))
	root.add_child(Visuals.solid(Vector3(SHOP_W, WALL_H, 0.2), wall, Vector3(0, WALL_H / 2, -hd)))
	root.add_child(Visuals.solid(Vector3(0.2, WALL_H, SHOP_D), wall, Vector3(-hw, WALL_H / 2, 0)))
	root.add_child(Visuals.solid(Vector3(0.2, WALL_H, SHOP_D), wall, Vector3(hw, WALL_H / 2, 0)))
	# Front wall with a 2m door gap in the middle.
	var seg := (SHOP_W - 2.0) / 2.0
	root.add_child(Visuals.solid(Vector3(seg, WALL_H, 0.2), wall, Vector3(-1.0 - seg / 2, WALL_H / 2, hd)))
	root.add_child(Visuals.solid(Vector3(seg, WALL_H, 0.2), wall, Vector3(1.0 + seg / 2, WALL_H / 2, hd)))
	root.add_child(Visuals.solid(Vector3(2.0, 0.9, 0.2), wall, Vector3(0, WALL_H - 0.45, hd)))
	var shop_sign := Visuals.label("FORGE & FORTUNE", Vector3(0, WALL_H + 0.6, hd + 0.3), 120, Color("ffd27a"))
	shop_sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	root.add_child(shop_sign)

	for p in [Vector3(-3, 3.0, -2), Vector3(3, 3.0, -2), Vector3(0, 3.0, 2.5)]:
		var lamp := OmniLight3D.new()
		lamp.position = p
		lamp.light_color = Color("ffd9a0")
		lamp.light_energy = 1.2
		lamp.omni_range = 7.0
		root.add_child(lamp)

	# Furniture & stations.
	_place(Stations.forge(ui), Vector3(-4.0, 0.1, -4.0), 0)
	_place(Stations.workbench(ui), Vector3(0, 0.1, -4.3), 0)
	_place(Stations.jeweler(ui), Vector3(4.0, 0.1, -4.2), 0)
	_place(Stations.menu_object(ui, "supply", "Supply Order Board", "supply_board", Color("6b4a2b"), Vector3(0.3, 1.8, 1.6)), Vector3(-5.7, 0.1, -1.0), 0)
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
