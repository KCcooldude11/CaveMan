extends Node
## Boots the real game scene headless, fast-forwards a day and pokes every
## menu. Catches runtime errors the logic tests can't.
##   godot --headless res://tests/smoke_test.tscn

func _ready() -> void:
	GameState.delete_save()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = main
	var ui: Node = main.ui
	var shop: Node = main.shop

	for station in ["forge", "workbench"]:
		ui.open_craft(station)
		await get_tree().process_frame
		ui.current._start_craft(DataDB.recipes_for_station(station)[0])
		await get_tree().process_frame
		for i in 3:
			ui.current._game.strike()
		await get_tree().process_frame
		ui.current.close()
		await get_tree().process_frame
	print("items after crafting: ", GameState.items.size())

	for m in ["supply", "upgrades", "ledger"]:
		ui.open_menu_by_name(m)
		await get_tree().process_frame
		ui.current.close()
		await get_tree().process_frame

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
	print("served customers: ", served, "  gold: ", GameState.gold, "  time: ", TimeManager.time_string())

	Engine.time_scale = 1.0
	TimeManager.minutes = 21 * 60
	EventBus.sleep_requested.emit()
	await get_tree().process_frame
	print("summary open: ", ui.summary_open())
	ui.current.close()
	await get_tree().process_frame
	print("day now: ", GameState.day, "  running: ", TimeManager.running, "  paused: ", TimeManager.is_paused())
	GameState.delete_save()
	print("SMOKE OK" if served > 0 and GameState.day == 2 and not TimeManager.is_paused() else "SMOKE FAILED")
	get_tree().quit()
