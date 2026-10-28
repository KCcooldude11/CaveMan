extends Node
## Boots the real game scene headless and plays through it: first-person
## forging at the anvil, the workbench minigame, every menu, a fast day of
## customers, several nights (with morning decisions), and save/load.
##   godot --headless res://tests/smoke_test.tscn

var ok := true


func fail(msg: String) -> void:
	ok = false
	printerr("SMOKE FAIL: ", msg)


func _ready() -> void:
	# Watchdog: never hang CI.
	get_tree().create_timer(300.0, true, false, true).timeout.connect(func():
		printerr("SMOKE FAILED (timeout)")
		get_tree().quit(1))
	GameState.delete_save()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = main
	var ui: Node = main.ui
	var shop: Node = main.shop
	if ui.current != null:
		ui.current.close()  # welcome briefing
	await get_tree().process_frame

	# --- First-person anvil at the forge.
	ui.open_craft("forge")
	await get_tree().process_frame
	var items_before := GameState.items.size()
	ui.current._start_craft("iron_dagger")
	await get_tree().process_frame
	var session: Node = main.get_children().filter(func(c): return c.has_method("auto_strike"))[0]
	if get_viewport().get_camera_3d() != session._camera:
		fail("anvil camera not active")
	var done := [false]
	session.finished.connect(func(_q): done[0] = true)
	for i in session.strikes_total:
		session.auto_strike(2)
		await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	while not done[0] and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	await get_tree().process_frame
	if GameState.items.size() != items_before + 1:
		fail("anvil craft did not produce an item")
	elif int(GameState.items[-1]["quality"]) != 3:
		fail("perfect anvil strikes should give Masterwork, got %d" % int(GameState.items[-1]["quality"]))
	if get_viewport().get_camera_3d() != main.player.camera:
		fail("player camera not restored after forging")
	print("anvil: crafted ", GameState.item_name(GameState.items[-1]))
	ui.current.close()
	await get_tree().process_frame

	# --- Workbench (in-menu minigame).
	GameState.add_material("leather", 3)
	ui.open_craft("workbench")
	await get_tree().process_frame
	ui.current._start_craft("leather_vest")
	await get_tree().process_frame
	for i in 3:
		ui.current._game.strike()
	await get_tree().process_frame
	ui.current.close()
	await get_tree().process_frame
	print("items after crafting: ", GameState.items.size())

	for m in ["supply", "upgrades", "ledger", "notice_board", "tavern", "village_hall", "chronicle", "briefing"]:
		ui.open_menu_by_name(m)
		await get_tree().process_frame
		if ui.current == null:
			fail("menu %s did not open" % m)
		else:
			ui.current.close()
		await get_tree().process_frame

	# --- A fast day at the counter.
	Engine.time_scale = 8.0
	TimeManager.minutes_per_second = 10.0
	var served := 0
	var frames := 0
	while TimeManager.minutes < 19 * 60 and frames < 20000:
		frames += 1
		await get_tree().physics_frame
		var front: Node = shop.front_customer()
		if front != null and ui.current == null:
			shop.serve(front)
			await get_tree().process_frame
			var menu: Node = ui.current
			if not GameState.items.is_empty():
				menu._select(GameState.items[0])
				menu._offer()
			if ui.current != null:
				ui.current.close()
			served += 1
	Engine.time_scale = 1.0
	print("served customers: ", served, "  gold: ", GameState.gold)
	if served == 0:
		fail("no customers served")

	# --- Several nights, answering every morning decision.
	for night in 4:
		TimeManager.minutes = 21 * 60
		EventBus.sleep_requested.emit()
		await get_tree().process_frame
		if not ui.summary_open():
			fail("night report did not open")
			break
		ui.current.close()
		await get_tree().process_frame
		while not Happenings.pending.is_empty():
			var d: Dictionary = Happenings.pending[0]
			Happenings.resolve(int(d["id"]), d["options"][0]["key"])
		if ui.current != null:
			ui.current.close()
		await get_tree().process_frame
	print("day now: ", GameState.day, "  chronicle entries: ", Chronicle.entries.size(), "  paused: ", TimeManager.is_paused())
	if GameState.day != 5 or TimeManager.is_paused():
		fail("day did not advance cleanly")

	# --- Save / load.
	GameState.save_game()
	var before := JSON.stringify(GameState.jsonfix(JSON.parse_string(JSON.stringify(GameState.to_dict()))))
	if not GameState.load_game():
		fail("load failed")
	var after := JSON.stringify(GameState.jsonfix(JSON.parse_string(JSON.stringify(GameState.to_dict()))))
	if before != after:
		fail("save/load changed the world")
	GameState.delete_save()
	print("SMOKE OK" if ok else "SMOKE FAILED")
	get_tree().quit(0 if ok else 1)
