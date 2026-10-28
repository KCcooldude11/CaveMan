extends BaseMenu
## The Rusty Tankard: hear rumors (extends the forecast) and see where the
## adventurers are heading tonight.


func _init() -> void:
	super(DataDB.village["tavern"]["name"])


func build() -> void:
	add_label("Gold: %dg" % GameState.gold, 18, Color("ffd27a"))
	var cost := int(DataDB.village["tavern"]["round_cost"])
	if Village.rumor_day == GameState.day:
		add_label("You bought a round today. The rumors are on the notice board: you can see %d days ahead." % Village.visible_days(), 15, Color("8fd18f"))
	else:
		add_row("Buy a round for the house ([color=#ffd27a]%dg[/color]). Loose tongues reveal what's stirring in the dungeons further ahead, and the heroes may toast your name." % cost,
			[button("Buy round", _buy_round, GameState.gold < cost)])

	add_heading("Where the heroes are heading tonight")
	var plans := {}
	for a in AdventurerManager.alive():
		var p: String = a.get("plan", "")
		if p != "":
			plans[p] = plans.get(p, []) + [a]
	if plans.is_empty():
		add_label("The tavern is quiet.", 15, Color("b8b0a0"))
	for d in DataDB.dungeons:
		if not plans.has(d["id"]):
			continue
		var cond := Village.conditions(d["id"], GameState.day)
		var names: PackedStringArray = []
		for a in plans[d["id"]]:
			names.append("%s (Lv %d)" % [a["name"], int(a["level"])])
		add_rich("[b]%s[/b] vs %s - %d heading out\n    [color=#b8b0a0]%s[/color]" % [
			d["name"], DataDB.enemies[cond["enemy"]]["name"], plans[d["id"]].size(), ", ".join(names)])


func _buy_round() -> void:
	if Village.buy_round():
		EventBus.notify.emit("You buy a round. The rumors flow...")
	refresh()
