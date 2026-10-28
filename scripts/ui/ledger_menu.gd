extends BaseMenu
## Your notes on every adventurer in town plus the known dungeons.


func _init() -> void:
	super("Adventurer Ledger")


func build() -> void:
	var tier := DataDB.tier_for_renown(GameState.renown)
	var nxt = DataDB.next_tier(GameState.renown)
	var t := "Renown %d - [b]%s[/b]" % [GameState.renown, tier["name"]]
	if nxt != null:
		t += "   (next: %s at %d)" % [nxt["name"], int(nxt["min"])]
	add_rich(t)
	var s: Dictionary = GameState.stats
	add_rich("[color=#b8b0a0]Crafted %d  -  Sold %d  -  Earned %dg  -  Masterworks %d  -  Legends %d[/color]" % [
		int(s["crafted"]), int(s["sold"]), int(s["earned"]), int(s["masterworks"]), int(s.get("legends", 0))])
	if Market.rival_active:
		add_rich("[color=#9a8f86]Rival: %s (reputation %d vs your %d)[/color]" % [DataDB.world["rival"]["name"], int(Market.rival_rep), GameState.renown])

	add_heading("Dungeons")
	for d in DataDB.dungeons:
		var cond := Village.conditions(d["id"], GameState.day)
		add_rich("[b]%s[/b]  difficulty %d, threat %s   [color=#b8b0a0]tonight: %s, loot: %s[/color]" % [
			d["name"], int(cond["difficulty"]), Dungeons.threat_label(d["id"]), DataDB.enemies[cond["enemy"]]["name"], DataDB.format_loot(cond["loot"])])
	add_label("See the notice board in the village square for the full forecast.", 14, Color("b8b0a0"))

	add_heading("Adventurers")
	var list: Array = AdventurerManager.roster.duplicate()
	list.sort_custom(func(a, b):
		if a["alive"] != b["alive"]:
			return a["alive"]
		return int(a["level"]) > int(b["level"]))
	if list.is_empty():
		add_label("No adventurers known yet.")
	for a in list:
		var mine := 0
		for slot in DataDB.SLOTS:
			if a["gear"][slot] != null and a["gear"][slot]["player_made"]:
				mine += 1
		var color := "e8e2d6" if a["alive"] else "777777"
		var status := ""
		if not a["alive"]:
			status = "fallen"
		elif not a.get("expedition", {}).is_empty():
			status = "[color=#ff9a6a]on a boss hunt[/color]"
		elif int(a.get("injured_until", 0)) >= GameState.day:
			status = "[color=#e0b06c]injured[/color]"
		var rival := AdventurerManager.get_adv(int(a.get("rival", 0)))
		var memory: String = a["memories"][-1] if not a["memories"].is_empty() else a["last_result"]
		add_rich("[color=#%s][b]%s[/b]  Lv %d %s %s - %s - %dg - power %d - your gear %d/3 %s%s\n    [i]%s[/i][/color]" % [
			color, AdventurerManager.full_name(a), int(a["level"]), AdventurerManager.personality_of(a)["name"], AdventurerManager.class_name_of(a),
			AdventurerManager.loyalty_label(a), int(a["gold"]), int(AdventurerManager.power(a)), mine, status,
			"  rival: %s" % rival["name"] if not rival.is_empty() else "", memory])
