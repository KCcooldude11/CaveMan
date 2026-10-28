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
	add_rich("[color=#b8b0a0]Crafted %d  -  Sold %d  -  Earned %dg  -  Masterworks %d[/color]" % [
		int(s["crafted"]), int(s["sold"]), int(s["earned"]), int(s["masterworks"])])

	add_heading("Dungeons")
	for d in DataDB.dungeons:
		var cond := Village.conditions(d["id"], GameState.day)
		add_rich("[b]%s[/b]  difficulty %d   [color=#b8b0a0]tonight: %s, loot: %s[/color]" % [
			d["name"], int(d["difficulty"]), DataDB.enemies[cond["enemy"]]["name"], DataDB.format_loot(cond["loot"])])
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
		add_rich("[color=#%s][b]%s[/b]  Lv %d %s  -  %dg  -  power %d  -  your gear: %d/3\n    [i]%s[/i][/color]" % [
			color, a["name"], int(a["level"]), AdventurerManager.class_name_of(a), int(a["gold"]),
			int(AdventurerManager.power(a)), mine, a["last_result"]])
