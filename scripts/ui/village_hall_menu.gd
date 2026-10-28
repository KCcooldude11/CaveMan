extends BaseMenu
## The Village Hall: prosperity, safety, restoration projects and caravan
## investments. Restored buildings appear in the world and change the rules.

var _invest: SpinBox


func _init() -> void:
	super("Village Hall - Mayor Brindle")


func build() -> void:
	add_rich("[font_size=20]Prosperity [color=#ffd27a]%d[/color]/100   Safety [color=#9fd8ff]%d[/color]/100   Your gold %dg[/font_size]" % [Village.prosperity, Village.safety, GameState.gold])
	add_label("Prosperity grows with slain bosses and restored buildings and brings more heroes. Safety protects caravans and walls; high dungeon threat erodes it.", 14, Color("b8b0a0"))
	add_heading("Restoration projects")
	for id in DataDB.world["projects"]:
		var p: Dictionary = DataDB.world["projects"][id]
		if Village.project_done(id):
			add_rich("[color=#8fd18f][b]%s[/b] - restored.[/color] [color=#b8b0a0]%s[/color]" % [p["name"], p["desc"]])
			continue
		var rem := Village.project_remaining(id)
		var need: PackedStringArray = []
		if int(rem["gold"]) > 0:
			need.append("%dg" % int(rem["gold"]))
		for m in rem["materials"]:
			need.append("%d %s (have %d)" % [int(rem["materials"][m]), DataDB.material_name(m), GameState.material_count(m)])
		var avail := Village.project_available(id)
		var text := "[b]%s[/b]  [color=#b8b0a0]%s[/color]\n    Still needed: %s%s" % [p["name"], p["desc"], ", ".join(need),
			"" if avail else "   [color=#e06c6c](needs prosperity %d)[/color]" % int(p["prosperity"])]
		add_row(text, [button("Contribute", _contribute.bind(id), not avail)])

	add_heading("Trade caravan")
	var c: Dictionary = DataDB.world["caravan"]
	if not Village.caravans.is_empty():
		add_rich("Your caravan is on the road. It returns on Day %d." % int(Village.caravans[0]["return_day"]))
	else:
		add_label("Invest %d-%dg in a caravan to the cities. In %d days it comes back with anywhere from nothing to more than double. Better odds when the village is safe." % [int(c["min"]), int(c["max"]), int(c["nights"])], 15)
		var row := HBoxContainer.new()
		_invest = SpinBox.new()
		_invest.min_value = int(c["min"])
		_invest.max_value = int(c["max"])
		_invest.step = 10
		_invest.value = int(c["min"])
		row.add_child(_invest)
		row.add_child(button("Invest", _do_invest))
		content.add_child(row)


func _contribute(id: String) -> void:
	var gave := Village.contribute(id)
	if gave != "":
		EventBus.notify.emit("You contributed %s to the %s." % [gave, DataDB.world["projects"][id]["name"]])
	refresh()


func _do_invest() -> void:
	if Village.invest_caravan(int(_invest.value)):
		EventBus.notify.emit("The caravan sets off with %dg of your money." % int(_invest.value))
	refresh()
