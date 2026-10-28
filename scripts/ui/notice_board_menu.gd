extends BaseMenu
## The village notice board: what's stirring in the dungeons over the next
## few days, commissions from villagers, and a bestiary of known enemies.


func _init() -> void:
	super("Village Notice Board")


func build() -> void:
	var today := GameState.day
	var days := Village.visible_days()
	add_heading("Dungeon forecast")
	add_label("Plan ahead: craft gear that exploits these weaknesses, and expect this loot to be for sale when the heroes return.", 15, Color("b8b0a0"))
	for d in range(today, today + days):
		var when := "Tonight" if d == today else ("Tomorrow" if d == today + 1 else "Day %d" % d)
		var evs := Village.events_on(d)
		if evs.is_empty():
			add_rich("[b]%s[/b]  [color=#777]All quiet.[/color]" % when)
			continue
		for e in evs:
			var cond := Village.conditions(e["dungeon"], d)
			var enemy: Dictionary = DataDB.enemies[cond["enemy"]]
			var bounty := "   [color=#ffd27a]Bounty %dg[/color]" % int(cond["bounty"]) if int(cond["bounty"]) > 0 else ""
			add_rich("[b]%s[/b]  %s%s\n    [color=#e06c6c]Weak to:[/color] %s   [color=#9a8f86]Resists:[/color] %s\n    [color=#9fd8ff]Loot:[/color] %s" % [
				when, e["text"], bounty, ", ".join(enemy["weak"]), _or_none(enemy["resist"]), DataDB.format_loot(cond["loot"])])
	if days < int(DataDB.village["forecast"]["rumor_days_ahead"]):
		add_label("Want to see further ahead? Buy a round at the tavern and listen to the rumors.", 14, Color("b8b0a0"))

	add_heading("Commissions")
	if Village.commissions.is_empty():
		add_label("No commissions posted right now. Check back tomorrow.", 15, Color("b8b0a0"))
	for c in Village.commissions:
		var r: Dictionary = DataDB.recipes[c["recipe"]]
		var q: Dictionary = DataDB.QUALITIES[int(c["quality"])]
		var matches := Village.matching_items(c)
		var reason := " %s" % c["reason"] if c["reason"] != "" else ""
		var text := "[b]%s[/b] wants a [color=#%s]%s[/color]-or-better %s%s.\n    Reward: [color=#ffd27a]%dg[/color] + %d renown   -   due by Day %d" % [
			c["giver"], hex(q["color"]), q["name"], r["name"], reason, int(c["gold"]), int(c["renown"]), int(c["due"])]
		var btn := button("Deliver", _deliver.bind(c, matches[0] if not matches.is_empty() else {}), matches.is_empty())
		add_row(text, [btn])

	add_heading("Bestiary")
	for id in DataDB.enemies:
		var e: Dictionary = DataDB.enemies[id]
		add_rich("[b]%s[/b] - %s\n    [color=#e06c6c]Weak:[/color] %s   [color=#9a8f86]Resists:[/color] %s   [color=#9fd8ff]Drops:[/color] %s" % [
			e["name"], e["desc"], ", ".join(e["weak"]), _or_none(e["resist"]), DataDB.format_loot(e["loot"])])


func _deliver(c: Dictionary, item: Dictionary) -> void:
	if not item.is_empty():
		Village.fulfil(c, item)
	refresh()


static func _or_none(a: Array) -> String:
	return "nothing" if a.is_empty() else ", ".join(a)
