extends BaseMenu
## The morning briefing: decisions that need you, news, deadlines and the
## threats that matter today. Opens automatically when something happened;
## reopen it any time with B.


func _init() -> void:
	super("Morning of Day %d" % GameState.day)


func build() -> void:
	title_label.text = "Morning of Day %d" % GameState.day
	for n in Happenings.news:
		add_rich(n)
	if not Happenings.pending.is_empty():
		add_heading("Decisions")
		for d in Happenings.pending:
			add_rich("[b][color=#ffd27a]%s[/color][/b]\n%s" % [d["title"], d["text"]])
			for o in d["options"]:
				add_row("    [color=#b8b0a0]%s[/color]" % o.get("hint", ""), [_choice_button(int(d["id"]), o)])
	var due := Village.commissions.filter(func(c): return int(c["due"]) <= GameState.day + 1)
	if not due.is_empty():
		add_heading("Deadlines")
		for c in due:
			add_rich("[color=#e0b06c]%s[/color] wants %s - due %s." % [c["giver"], Village.commission_text(c), "TODAY" if int(c["due"]) == GameState.day else "tomorrow"])
	add_heading("Tonight in the dungeons")
	var any := false
	for d in DataDB.dungeons:
		var b := Dungeons.boss(d["id"])
		if not b.is_empty():
			any = true
			add_rich("[color=#ff9a6a][b]%s[/b] lurks in the %s.[/color]%s" % [b["name"], d["name"],
				" A party is hunting it." if not b.get("party", []).is_empty() else " Heroes will form a party once enough are free."])
	for e in Village.events_on(GameState.day):
		any = true
		add_rich("%s [color=#e06c6c](weak to %s)[/color]" % [e["text"], ", ".join(DataDB.enemies[e["enemy"]]["weak"])])
	if not any:
		add_label("All quiet.", 15, Color("b8b0a0"))
	content.add_child(button("Begin the day", close))


func _choice_button(id: int, o: Dictionary) -> Button:
	var b := button(o["label"], func():
		Happenings.resolve(id, o["key"])
		refresh())
	b.custom_minimum_size.x = 300
	return b
