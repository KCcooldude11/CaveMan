extends BaseMenu
## The village notice board: dungeon status, the forecast, commissions and
## a bestiary. Rumors further out are marked - they can turn out wrong.


func _init() -> void:
	super("Village Notice Board")


func build() -> void:
	var today := GameState.day
	add_heading("Dungeon status")
	for d in DataDB.dungeons:
		var st := Dungeons.get_state(d["id"])
		var b := Dungeons.boss(d["id"])
		var threat := "%s (%d)" % [Dungeons.threat_label(d["id"]), Dungeons.threat(d["id"])] if Village.project_done("watchtower") else Dungeons.threat_label(d["id"])
		var ctrl := "" if st["controller"] == d["enemy"] else "  [color=#ff9a6a]held by the %s[/color]" % DataDB.enemies[st["controller"]]["name"]
		var boss := "  [color=#ff9a6a][b]BOSS: %s[/b][/color]" % b["name"] if not b.is_empty() else ""
		var lost := "  [color=#ffc94a](a lost legend lies here)[/color]" if not st["lost"].is_empty() else ""
		add_rich("[b]%s[/b]  threat %s%s%s%s" % [d["name"], threat, ctrl, boss, lost])
	add_label("Threat rises when heroes fail or stay away and falls when they win. High threat raises a boss; maximum threat means a raid on the village.", 14, Color("b8b0a0"))

	add_heading("Forecast")
	var days := Village.visible_days()
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
			var rumor := "" if e.get("confirmed", false) else " [color=#9a8f86](rumor)[/color]"
			var changed := " [color=#e0b06c](the rumor was wrong - this is new!)[/color]" if e.get("changed", false) else ""
			var mod: Dictionary = cond["modifier"]
			var mtext := "\n    [color=#c77dff]%s:[/color] %s" % [mod["name"], mod["desc"]] if not mod.is_empty() else ""
			add_rich("[b]%s[/b]  %s%s%s%s\n    [color=#e06c6c]Weak to:[/color] %s   [color=#9a8f86]Resists:[/color] %s\n    [color=#9fd8ff]Loot:[/color] %s%s" % [
				when, e["text"], bounty, rumor, changed, ", ".join(enemy["weak"]), _or_none(enemy["resist"]), DataDB.format_loot(cond["loot"]), mtext])
	if Village.rumor_day != today:
		add_label("Want to see further ahead? Buy a round at the tavern and listen to the rumors.", 14, Color("b8b0a0"))

	add_heading("Commissions")
	if Village.commissions.is_empty():
		add_label("No commissions posted right now. Check back tomorrow.", 15, Color("b8b0a0"))
	for c in Village.commissions:
		var matches := Village.matching_items(c)
		var reason := " %s" % c["reason"] if str(c.get("reason", "")) != "" else ""
		var tag := ""
		match str(c.get("special", "")):
			"envoy": tag = "[color=#ffc94a][ROYAL][/color] "
			"contest": tag = "[color=#e06c6c][CONTEST][/color] "
			"hero": tag = "[color=#8fd18f][PERSONAL][/color] "
		var reward := "the contest" if str(c.get("special", "")) == "contest" else "[color=#ffd27a]%dg[/color] + %d renown" % [int(c["gold"]), int(c["renown"])]
		var fail := "   [color=#e06c6c]fail: %d renown[/color]" % int(c["fail_renown"]) if int(c.get("fail_renown", 0)) != 0 else ""
		var text := "%s[b]%s[/b] wants %s%s.\n    Reward: %s   -   due by Day %d%s" % [
			tag, c["giver"], Village.commission_text(c), reason, reward, int(c["due"]), fail]
		var btn := button("Deliver", _deliver.bind(c, _best(matches)), matches.is_empty())
		add_row(text, [btn])

	add_heading("Bestiary")
	for id in DataDB.enemies:
		var e: Dictionary = DataDB.enemies[id]
		add_rich("[b]%s[/b] - %s\n    [color=#e06c6c]Weak:[/color] %s   [color=#9a8f86]Resists:[/color] %s   [color=#9fd8ff]Drops:[/color] %s" % [
			e["name"], e["desc"], ", ".join(e["weak"]), _or_none(e["resist"]), DataDB.format_loot(e["loot"])])


## For contests deliver your strongest match; otherwise your least valuable.
func _best(matches: Array) -> Dictionary:
	if matches.is_empty():
		return {}
	var sorted := matches.duplicate()
	sorted.sort_custom(func(a, b): return GameState.item_power(a) > GameState.item_power(b))
	return sorted[0]


func _deliver(c: Dictionary, item: Dictionary) -> void:
	if not item.is_empty():
		Village.fulfil(c, item)
	refresh()


static func _or_none(a: Array) -> String:
	return "nothing" if a.is_empty() else ", ".join(a)
