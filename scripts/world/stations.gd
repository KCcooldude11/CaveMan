class_name Stations
## Factory for every interactable piece of furniture in the shop.
## Each one just opens a UI menu; the logic lives in the autoloads.


class CraftingStation extends Interactable:
	var station: String
	var ui: Node

	func get_prompt() -> String:
		var n: String = DataDB.STATION_NAMES[station]
		if GameState.station_level(station) <= 0:
			return "%s (locked - buy it at the Upgrade Lectern)" % n
		return "[E] Craft at %s (Lv %d)" % [n, GameState.station_level(station)]

	func interact(_player: Node) -> void:
		if GameState.station_level(station) <= 0:
			EventBus.notify.emit("You need to buy the %s first." % DataDB.STATION_NAMES[station])
			return
		ui.open_craft(station)


class MenuObject extends Interactable:
	var menu: String
	var ui: Node

	func get_prompt() -> String:
		return "[E] " + prompt_text

	func interact(_player: Node) -> void:
		ui.open_menu_by_name(menu)


class Bed extends Interactable:
	func get_prompt() -> String:
		if TimeManager.can_sleep():
			return "[E] Sleep (end day)"
		return "Too early to sleep (after 18:00)"

	func interact(_player: Node) -> void:
		if TimeManager.can_sleep():
			EventBus.sleep_requested.emit()


class Counter extends Interactable:
	var shop: Node

	func get_prompt() -> String:
		var front: Node = shop.front_customer()
		if front == null:
			return "Shop counter - %s" % ("waiting for customers" if TimeManager.is_shop_open() else "shop is closed")
		return "[E] Serve %s" % front.adv["name"]

	func interact(_player: Node) -> void:
		var front: Node = shop.front_customer()
		if front:
			shop.serve(front)


## A villager standing in the world (pixel sprite) who opens a menu.
class Villager extends Interactable:
	var menu: String
	var ui: Node

	func get_prompt() -> String:
		return "[E] " + prompt_text

	func interact(_player: Node) -> void:
		ui.open_menu_by_name(menu)


## The travelling merchant's wagon: only open on merchant days.
class MerchantStop extends Interactable:
	var ui: Node
	var wagon: Node3D

	func _process(_delta: float) -> void:
		wagon.visible = Village.merchant_here(GameState.day)

	func get_prompt() -> String:
		if Village.merchant_here(GameState.day):
			return "[E] Trade with %s" % DataDB.village["merchant"]["name"]
		return "Merchant's spot - %s visits every %d days (next: Day %d)" % [
			DataDB.village["merchant"]["name"], int(DataDB.village["merchant"]["every_days"]),
			Village.next_merchant_day(GameState.day)]

	func interact(_player: Node) -> void:
		if Village.merchant_here(GameState.day):
			ui.open_menu_by_name("merchant")


## A free resource spot (old mine, woodcutter's grove). Once per day, costs time.
class Gatherable extends Interactable:
	var spot: String
	var verb: String

	func get_prompt() -> String:
		var g: Dictionary = DataDB.village["gathering"][spot]
		if not Village.can_gather(spot):
			return "%s - come back tomorrow" % g["name"]
		return "[E] %s at the %s (%d min)" % [verb, g["name"], int(g["minutes"])]

	func interact(_player: Node) -> void:
		var haul := Village.gather(spot)
		if haul != "":
			EventBus.notify.emit("%s: you gathered %s." % [DataDB.village["gathering"][spot]["name"], haul])


## A restoration project in the world: ruins until it's done, then the real
## building. Interacting opens the Village Hall so you can contribute.
class ProjectSite extends Interactable:
	var project: String
	var ui: Node
	var ruined: Node3D
	var restored: Node3D

	func _ready() -> void:
		EventBus.projects_changed.connect(refresh)
		refresh()

	func refresh() -> void:
		var done := Village.project_done(project)
		ruined.visible = not done
		restored.visible = done

	func get_prompt() -> String:
		var n: String = DataDB.world["projects"][project]["name"]
		if Village.project_done(project):
			return n
		return "[E] Ruins of the %s - help restore it (Village Hall)" % n

	func interact(_player: Node) -> void:
		if not Village.project_done(project):
			ui.open_menu_by_name("village_hall")


## Someone you can talk to whose words depend on the state of the world.
class Talker extends Interactable:
	var line_fn: Callable

	func get_prompt() -> String:
		return "[E] " + prompt_text

	func interact(_player: Node) -> void:
		EventBus.notify.emit(line_fn.call())


static func project_site(ui: Node, project: String, ruined: Node3D, restored: Node3D, size: Vector3) -> ProjectSite:
	var p := ProjectSite.new()
	p.project = project
	p.ui = ui
	p.ruined = ruined
	p.restored = restored
	p.add_child(ruined)
	p.add_child(restored)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position.y = size.y / 2.0
	p.add_child(cs)
	return p


static func talker(sheet: String, prompt: String, title: String, line_fn: Callable) -> Talker:
	var t := Talker.new()
	t.prompt_text = prompt
	t.line_fn = line_fn
	var pc := PixelCharacter.new()
	pc.setup(sheet)
	t.setup_body("villager_" + sheet, Vector3(0.8, 1.8, 0.8), pc)
	t.add_child(Visuals.tag(title, Vector3(0, 2.7, 0), 24, Color("ffe9a8")))
	return t


static func villager(ui: Node, sheet: String, menu: String, text: String, title: String) -> Villager:
	var v := Villager.new()
	v.menu = menu
	v.ui = ui
	v.prompt_text = text
	var pc := PixelCharacter.new()
	pc.setup(sheet)
	v.setup_body("villager_" + sheet, Vector3(0.8, 1.8, 0.8), pc)
	v.add_child(Visuals.tag(title, Vector3(0, 2.7, 0), 24, Color("ffe9a8")))
	return v


static func merchant_stop(ui: Node) -> MerchantStop:
	var m := MerchantStop.new()
	m.ui = ui
	var wagon := Node3D.new()
	wagon.add_child(Visuals.box(Vector3(2.6, 0.8, 1.6), "dark_wood", Vector3(0, 0.9, 0)))
	wagon.add_child(Visuals.box(Vector3(2.8, 0.08, 1.8), Color("7a3e8a"), Vector3(0, 2.4, 0)))  # canopy
	for x in [-1.3, 1.3]:
		wagon.add_child(Visuals.box(Vector3(0.1, 1.2, 0.1), "dark_wood", Vector3(x, 1.8, 0.8)))
		wagon.add_child(Visuals.box(Vector3(0.1, 1.2, 0.1), "dark_wood", Vector3(x, 1.8, -0.8)))
		wagon.add_child(Visuals.cylinder(0.45, 0.12, Color("4a3020"), Vector3(x * 0.7, 0.45, 0.85)))
	for i in 3:
		wagon.add_child(Visuals.box(Vector3(0.4, 0.4, 0.4), ["iron", "dark_wood", "stone"][i], Vector3(-0.8 + i * 0.8, 1.5, 0.2)))
	var zara := PixelCharacter.new()
	zara.setup("merchant")
	zara.position.z = 1.4
	zara.position.y += 0.0
	wagon.add_child(zara)
	wagon.add_child(Visuals.tag(DataDB.village["merchant"]["name"], Vector3(0, 3.0, 1.4), 24, Color("ffe9a8")))
	m.wagon = wagon
	m.add_child(wagon)
	# A signpost that is always there.
	m.add_child(Visuals.box(Vector3(0.12, 1.4, 0.12), "dark_wood", Vector3(2.0, 0.7, 1.6)))
	m.add_child(Visuals.box(Vector3(0.8, 0.4, 0.06), "wood_floor", Vector3(2.0, 1.3, 1.65)))
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 2.0, 3.2)
	cs.shape = shape
	cs.position = Vector3(0, 1.0, 0.6)
	m.add_child(cs)
	return m


static func gatherable(spot: String, verb: String, visual: Node3D, size: Vector3) -> Gatherable:
	var g := Gatherable.new()
	g.spot = spot
	g.verb = verb
	g.setup_body(spot, size, visual)
	g.add_child(Visuals.label(DataDB.village["gathering"][spot]["name"].to_upper(), Vector3(0, size.y + 0.8, 0), 40))
	return g


static func forge(ui: Node) -> CraftingStation:
	var s := CraftingStation.new()
	s.station = "forge"
	s.ui = ui
	var ph := Node3D.new()
	ph.add_child(Visuals.box(Vector3(1.6, 1.0, 1.2), "stone", Vector3(0, 0.5, 0)))
	ph.add_child(Visuals.box(Vector3(1.0, 0.25, 0.7), Color("ff7a2a"), Vector3(0, 1.05, 0), 3.0))
	ph.add_child(Visuals.box(Vector3(0.6, 1.6, 0.6), "stone", Vector3(0, 1.8, -0.3)))
	# The anvil (first-person forging happens on its face).
	ph.add_child(Visuals.box(Vector3(0.5, 0.12, 0.36), "iron", Vector3(1.6, 0.06, 0.35)))
	ph.add_child(Visuals.box(Vector3(0.26, 0.42, 0.22), "iron", Vector3(1.6, 0.33, 0.35)))
	ph.add_child(Visuals.box(Vector3(0.62, 0.14, 0.3), "iron", Vector3(1.6, 0.6, 0.35)))
	var horn := Visuals.box(Vector3(0.22, 0.08, 0.12), "iron", Vector3(1.99, 0.62, 0.35))
	ph.add_child(horn)
	ph.add_child(Visuals.box(Vector3(0.12, 0.6, 0.12), "dark_wood", Vector3(1.15, 0.3, 0.6)))  # quench bucket post
	s.set_meta("anvil_top", Vector3(1.6, 0.67, 0.35))
	var light := OmniLight3D.new()
	light.light_color = Color("ff8a3a")
	light.light_energy = 2.0
	light.omni_range = 5.0
	light.position = Vector3(0, 1.6, 0.6)
	ph.add_child(light)
	ph.add_child(Visuals.label("FORGE", Vector3(0, 2.9, 0)))
	s.setup_body("forge", Vector3(2.4, 1.2, 1.2), ph)
	return s


static func workbench(ui: Node) -> CraftingStation:
	var s := CraftingStation.new()
	s.station = "workbench"
	s.ui = ui
	var ph := Node3D.new()
	ph.add_child(Visuals.box(Vector3(2.2, 0.12, 1.0), "wood_floor", Vector3(0, 0.9, 0)))
	for x in [-1.0, 1.0]:
		for z in [-0.4, 0.4]:
			ph.add_child(Visuals.box(Vector3(0.1, 0.85, 0.1), "dark_wood", Vector3(x, 0.42, z)))
	ph.add_child(Visuals.box(Vector3(0.5, 0.08, 0.3), Color("c9b48a"), Vector3(-0.4, 1.0, 0)))
	ph.add_child(Visuals.label("WORKBENCH", Vector3(0, 2.0, 0)))
	s.setup_body("workbench", Vector3(2.2, 1.0, 1.0), ph)
	return s


static func jeweler(ui: Node) -> CraftingStation:
	var s := CraftingStation.new()
	s.station = "jeweler"
	s.ui = ui
	var ph := Node3D.new()
	ph.add_child(Visuals.box(Vector3(1.4, 0.9, 0.8), "dark_wood", Vector3(0, 0.45, 0)))
	ph.add_child(Visuals.box(Vector3(0.2, 0.2, 0.2), Color("4fb0c6"), Vector3(0.3, 1.0, 0), 1.5))
	ph.add_child(Visuals.box(Vector3(0.15, 0.15, 0.15), Color("d9dde3"), Vector3(-0.3, 0.98, 0.1), 0.5))
	ph.add_child(Visuals.label("JEWELER", Vector3(0, 2.0, 0)))
	s.setup_body("jeweler", Vector3(1.4, 1.0, 0.8), ph)
	return s


static func menu_object(ui: Node, menu: String, text: String, key: String, look: Variant, size: Vector3) -> MenuObject:
	var s := MenuObject.new()
	s.menu = menu
	s.ui = ui
	s.prompt_text = text
	var ph := Node3D.new()
	ph.add_child(Visuals.box(size, look, Vector3(0, size.y / 2.0, 0)))
	ph.add_child(Visuals.label(text.to_upper(), Vector3(0, size.y + 0.4, 0), 36))
	s.setup_body(key, size, ph)
	return s


static func bed() -> Bed:
	var s := Bed.new()
	var ph := Node3D.new()
	ph.add_child(Visuals.box(Vector3(1.2, 0.4, 2.2), "dark_wood", Vector3(0, 0.2, 0)))
	ph.add_child(Visuals.box(Vector3(1.1, 0.15, 2.0), Color("c9c2b0"), Vector3(0, 0.47, 0)))
	ph.add_child(Visuals.box(Vector3(0.9, 0.15, 0.4), Color("ffffff"), Vector3(0, 0.6, -0.75)))
	s.setup_body("bed", Vector3(1.2, 0.6, 2.2), ph)
	return s


static func counter(shop: Node) -> Counter:
	var s := Counter.new()
	s.shop = shop
	var ph := Node3D.new()
	ph.add_child(Visuals.box(Vector3(4.0, 1.0, 0.8), "dark_wood", Vector3(0, 0.5, 0)))
	ph.add_child(Visuals.box(Vector3(4.2, 0.08, 1.0), "wood_floor", Vector3(0, 1.04, 0)))
	s.setup_body("counter", Vector3(4.0, 1.1, 0.8), ph)
	return s
