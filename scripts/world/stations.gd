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


static func forge(ui: Node) -> CraftingStation:
	var s := CraftingStation.new()
	s.station = "forge"
	s.ui = ui
	var ph := Node3D.new()
	ph.add_child(Visuals.box(Vector3(1.6, 1.0, 1.2), "stone", Vector3(0, 0.5, 0)))
	ph.add_child(Visuals.box(Vector3(1.0, 0.25, 0.7), Color("ff7a2a"), Vector3(0, 1.05, 0), 3.0))
	ph.add_child(Visuals.box(Vector3(0.6, 1.6, 0.6), "stone", Vector3(0, 1.8, -0.3)))
	ph.add_child(Visuals.box(Vector3(0.7, 0.3, 0.35), "iron", Vector3(1.3, 0.75, 0.2)))  # anvil
	var light := OmniLight3D.new()
	light.light_color = Color("ff8a3a")
	light.light_energy = 2.0
	light.omni_range = 5.0
	light.position = Vector3(0, 1.6, 0.6)
	ph.add_child(light)
	ph.add_child(Visuals.label("FORGE", Vector3(0, 2.9, 0)))
	s.setup_body("forge", Vector3(2.0, 1.2, 1.2), ph)
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
