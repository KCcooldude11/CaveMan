extends Node
## Headless logic tests. Run from the project folder with:
##   godot --headless res://tests/test_runner.tscn
## Exits with code 0 when everything passes.

var _failures := 0
var _checks := 0


func _ready() -> void:
	seed(12345)
	GameState.reset()
	AdventurerManager.reset()
	test_data_loaded()
	test_crafting()
	test_minigame_scoring()
	test_selling()
	test_upgrades()
	test_long_simulation()
	test_save_roundtrip()
	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", what)


func test_data_loaded() -> void:
	check(DataDB.recipes.size() > 10, "recipes loaded")
	check(DataDB.dungeons.size() == 5, "dungeons loaded")
	for id in DataDB.recipes:
		var r: Dictionary = DataDB.recipes[id]
		check(DataDB.STATION_NAMES.has(r["station"]), "%s has a valid station" % id)
		check(r["slot"] in DataDB.SLOTS, "%s has a valid slot" % id)
		for m in r["inputs"]:
			check(DataDB.materials.has(m), "%s input %s exists" % [id, m])
	for d in DataDB.dungeons:
		for m in d["loot"]:
			check(DataDB.materials.has(m), "dungeon loot %s exists" % m)


func test_crafting() -> void:
	GameState.reset()
	var inputs: Dictionary = DataDB.recipes["iron_sword"]["inputs"]
	check(GameState.has_materials(inputs), "starting mats cover an iron sword")
	check(GameState.consume_materials(inputs), "consume works")
	check(GameState.material_count("iron_ingot") == 2, "iron consumed")
	var item := GameState.create_item("iron_sword", 2)
	check(GameState.items.size() == 1, "item on shelf")
	check(GameState.item_name(item) == "Fine Iron Sword", "item naming")
	check(GameState.item_power(item) > 8, "fine quality boosts power")


func test_minigame_scoring() -> void:
	var MG := preload("res://scripts/ui/forge_minigame.gd")
	check(MG.score_to_quality(0) == 0, "all misses -> crude")
	check(MG.score_to_quality(3) == 1, "mixed -> common")
	check(MG.score_to_quality(6) == 3, "all perfect -> masterwork")


func test_selling() -> void:
	GameState.reset()
	AdventurerManager.reset()
	var adv := AdventurerManager.recruit(1)
	adv["cls"] = "warrior"
	adv["gold"] = 200
	var item := GameState.create_item("iron_sword", 1)
	var p0 := AdventurerManager.power(adv)
	check(not AdventurerManager.evaluate_offer(adv, item, 9999)["accepted"], "absurd price refused")
	var fair := GameState.item_value(item)
	check(AdventurerManager.evaluate_offer(adv, item, fair)["accepted"], "fair price accepted by a warrior")
	var gold_before := GameState.gold
	AdventurerManager.sell_item(adv, item, fair)
	check(GameState.gold == gold_before + fair, "gold received")
	check(GameState.items.is_empty(), "item left the shelf")
	check(adv["gear"]["weapon"]["player_made"], "adventurer wears our sword")
	check(AdventurerManager.power(adv) > p0, "adventurer got stronger")
	var item2 := GameState.create_item("iron_dagger", 0)
	check(not AdventurerManager.evaluate_offer(adv, item2, 1)["accepted"], "won't buy a worse weapon")


func test_upgrades() -> void:
	GameState.reset()
	check(GameState.station_level("jeweler") == 0, "jeweler starts locked")
	GameState.gold = 1000
	check(not GameState.buy_upgrade("jeweler"), "jeweler needs renown")
	GameState.renown = 10
	check(GameState.buy_upgrade("jeweler"), "jeweler bought")
	check(GameState.station_level("jeweler") == 1, "jeweler unlocked")
	check(GameState.gold == 800, "upgrade cost charged")
	GameState.upgrades["forge"] = GameState.upgrade_max("forge")
	check(GameState.upgrade_next("forge").is_empty(), "max level has no next")


## Plays 30 days with a simple bot: buy mats, craft, sell to everyone who
## visits, sleep. Makes sure the economy actually progresses.
func test_long_simulation() -> void:
	GameState.reset()
	AdventurerManager.reset()
	for day in 30:
		AdventurerManager.plan_day()
		# Bot crafts the best affordable unlocked recipe a few times.
		for i in 4:
			var best := ""
			for id in DataDB.recipes:
				var r: Dictionary = DataDB.recipes[id]
				if not GameState.is_recipe_unlocked(id) or GameState.station_level(r["station"]) <= 0:
					continue
				var cost := 0
				var ok := true
				for m in r["inputs"]:
					if not DataDB.materials[m]["buyable"] and GameState.material_count(m) < int(r["inputs"][m]):
						ok = false
					elif DataDB.materials[m]["buyable"]:
						cost += GameState.material_price(m) * int(r["inputs"][m])
				if ok and cost <= GameState.gold and (best == "" or int(r["value"]) > int(DataDB.recipes[best]["value"])):
					best = id
			if best == "":
				break
			for m in DataDB.recipes[best]["inputs"]:
				var need := int(DataDB.recipes[best]["inputs"][m]) - GameState.material_count(m)
				if need > 0 and DataDB.materials[m]["buyable"]:
					GameState.spend_gold(GameState.material_price(m) * need)
					GameState.add_material(m, need)
			if GameState.consume_materials(DataDB.recipes[best]["inputs"]):
				GameState.create_item(best, randi_range(1, 2))
		for visit in AdventurerManager.schedule:
			var adv := AdventurerManager.get_adv(int(visit["id"]))
			if not adv["loot"].is_empty() and AdventurerManager.loot_price(adv) < GameState.gold / 3:
				AdventurerManager.buy_loot(adv)
			for item in GameState.items.duplicate():
				var price := GameState.item_value(item)
				if AdventurerManager.evaluate_offer(adv, item, price)["accepted"]:
					AdventurerManager.sell_item(adv, item, price)
					break
		AdventurerManager.schedule = []
		var night := AdventurerManager.run_night()
		GameState.add_renown(int(night["renown"]))
		GameState.run_apprentice()
		GameState.day += 1
		if day % 5 == 4:
			print("  day %d: gold=%d renown=%d" % [day + 1, GameState.gold, GameState.renown])
		for id in ["signboard", "jeweler", "forge", "workbench"]:
			if GameState.gold > 400:
				GameState.buy_upgrade(id)
	print("Sim after 30 days: gold=%d renown=%d tier=%s sold=%d roster=%d alive=%d" % [
		GameState.gold, GameState.renown, DataDB.tier_for_renown(GameState.renown)["name"],
		int(GameState.stats["sold"]), AdventurerManager.roster.size(), AdventurerManager.alive().size()])
	check(GameState.stats["sold"] > 20, "bot sold a reasonable amount")
	check(GameState.renown >= 10, "bot earned renown")
	check(AdventurerManager.alive().size() > 0, "someone is still alive")


func test_save_roundtrip() -> void:
	var before := JSON.stringify(GameState.to_dict())
	GameState.from_dict(JSON.parse_string(before))
	var after := JSON.stringify(GameState.to_dict())
	check(before == after, "save -> load -> save is stable")
