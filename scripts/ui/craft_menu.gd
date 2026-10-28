extends BaseMenu
## Recipe list for one crafting station, an optional rare-material infusion,
## then the station's minigame. The forge hands off to the first-person
## anvil (see world/forge_session.gd); other stations play inside the menu.

const ForgeMinigame := preload("res://scripts/ui/forge_minigame.gd")
const DialMinigame := preload("res://scripts/ui/dial_minigame.gd")
## Which minigame each station uses ("anvil" = first-person forging).
const STATION_MINIGAMES := {
	"forge": "anvil",
	"workbench": ForgeMinigame,
	"jeweler": DialMinigame,
}

var station: String
var _game: Node = null
var _recipe: String = ""
var _infusion: String = ""


func _init(station_id: String) -> void:
	station = station_id
	super(DataDB.STATION_NAMES[station_id])


func build() -> void:
	_game = null
	title_label.text = "%s  (Lv %d)" % [DataDB.STATION_NAMES[station], GameState.station_level(station)]
	_build_infusion_picker()
	var fams := {}
	for id in DataDB.recipes_for_station(station):
		fams[GameState.mastery_family(id)] = true
	var mparts: PackedStringArray = []
	for f in fams:
		mparts.append("%s Lv %d (%d crafted)" % [GameState.MASTERY_FAMILIES[f], GameState.mastery_level(f), int(GameState.mastery.get(f, 0))])
	add_rich("[color=#b8b0a0]Mastery: %s[/color]" % "   ".join(mparts))
	var hidden := 0
	for id in DataDB.recipes_for_station(station):
		var r: Dictionary = DataDB.recipes[id]
		if r.get("blueprint", false) and not id in GameState.known_blueprints:
			hidden += 1
			continue
		_recipe_row(id)
	if hidden > 0:
		add_label("%d secret blueprint(s) for this station are out there: slay bosses, trade with strangers, raid vaults." % hidden, 14, Color("c77dff"))


func _build_infusion_picker() -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Infuse with: "
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.focus_mode = Control.FOCUS_NONE
	opt.add_item("Nothing")
	opt.set_item_metadata(0, "")
	var selected := 0
	for m in GameState.infusion_materials():
		if GameState.material_count(m) <= 0:
			continue
		var a := GameState.affix_for_infusion(m)
		var known := a in GameState.discovered_affixes
		opt.add_item("%s (%d) -> %s" % [DataDB.material_name(m), GameState.material_count(m), DataDB.affixes[a]["name"] if known else "??? experiment!"])
		opt.set_item_metadata(opt.item_count - 1, m)
		if m == _infusion:
			selected = opt.item_count - 1
	if selected == 0:
		_infusion = ""
	opt.select(selected)
	opt.item_selected.connect(func(i):
		_infusion = opt.get_item_metadata(i)
		refresh())
	row.add_child(opt)
	content.add_child(row)
	if _infusion != "":
		var a := GameState.affix_for_infusion(_infusion)
		if a in GameState.discovered_affixes:
			add_rich("[color=#c77dff]%s:[/color] %s  [color=#b8b0a0](uses 1 %s per craft)[/color]" % [DataDB.affixes[a]["name"], DataDB.affixes[a]["desc"], DataDB.material_name(_infusion)])
		else:
			add_rich("[color=#c77dff]Unknown effect.[/color] Forge something with it to discover what %s does." % DataDB.material_name(_infusion))
	elif GameState.infusion_materials().any(func(m): return GameState.material_count(m) > 0):
		add_label("Tip: infuse a rare material to give the item a special property.", 14, Color("b8b0a0"))


func _inputs(id: String) -> Dictionary:
	var inputs: Dictionary = DataDB.recipes[id]["inputs"].duplicate()
	if _infusion != "":
		inputs[_infusion] = int(inputs.get(_infusion, 0)) + 1
	return inputs


func _recipe_row(id: String) -> void:
	var r: Dictionary = DataDB.recipes[id]
	var unlocked := GameState.is_recipe_unlocked(id)
	var inputs := _inputs(id)
	var parts: PackedStringArray = []
	for m in inputs:
		var need := int(inputs[m])
		var have := GameState.material_count(m)
		var col := "8fd18f" if have >= need else "e06c6c"
		parts.append("[color=#%s]%d/%d %s[/color]" % [col, have, need, DataDB.material_name(m)])
	var strong := DataDB.strong_against(r["tags"])
	var vs := "  [color=#e06c6c]strong vs %s[/color]" % ", ".join(strong) if not strong.is_empty() else ""
	var dl := Market.demand_label(r["tags"])
	var bp := " [color=#c77dff](blueprint)[/color]" if r.get("blueprint", false) else ""
	var text := "[b]%s[/b]%s  [color=#b8b0a0]%s, power %d, ~%dg, materials ~%dg  [%s][/color]%s %s\n%s" % [
		r["name"], bp, r["slot"], int(r["power"]), int(r["value"]), GameState.recipe_cost(id), ", ".join(r["tags"]), vs, dl, "  ".join(parts)]
	var btn: Button
	if not unlocked:
		text = "[color=#777]%s[/color]" % text
		btn = button("Renown %d" % int(r["renown"]), func(): pass, true)
	else:
		btn = button("Craft", _start_craft.bind(id), not GameState.has_materials(inputs))
	add_row(text, [btn])


func _minigame_level() -> int:
	# Station upgrades and mastery both widen the sweet spots.
	return GameState.station_level(station) + GameState.mastery_level(GameState.mastery_family(_recipe)) / 2


func _start_craft(id: String) -> void:
	if not GameState.begin_craft(id, _infusion):
		return
	_recipe = id
	var r: Dictionary = DataDB.recipes[id]
	var mg = STATION_MINIGAMES[station]
	if mg is String and mg == "anvil":
		ui.begin_anvil(self, _minigame_level(), int(r["power"]))
		return
	for c in content.get_children():
		c.queue_free()
	add_heading("%s: %s" % ["Setting" if mg == DialMinigame else "Crafting", r["name"]])
	_game = mg.new()
	if _game is DialMinigame:
		_game.configure(_minigame_level(), int(r["power"]), r.get("dial", ""))
	else:
		_game.configure(_minigame_level(), int(r["power"]))
	_game.finished.connect(on_minigame_finished)
	content.add_child(_game)


## Called by the in-menu minigames and by the first-person anvil.
func on_minigame_finished(quality: int) -> void:
	var res := GameState.finish_craft(_recipe, quality, _infusion)
	var item: Dictionary = res["item"]
	var q: Dictionary = DataDB.QUALITIES[quality]
	_game = null
	for c in content.get_children():
		c.queue_free()
	add_rich("\n[font_size=22]You made %s[color=#%s]%s[/color]![/font_size]\nPower %d, fair value %dg. %s" % [
		"" if item.get("legend", "") != "" else "a ", hex(q["color"]), GameState.item_name(item), GameState.item_power(item), GameState.item_value(item),
		"Strong vs %s." % ", ".join(DataDB.strong_against(GameState.item_tags(item))) if not DataDB.strong_against(GameState.item_tags(item)).is_empty() else ""])
	for n in res["notes"]:
		add_rich("[color=#c77dff]%s[/color]" % n)
	var row := HBoxContainer.new()
	row.add_child(button("Make another", _start_craft.bind(_recipe), not GameState.has_materials(_inputs(_recipe))))
	row.add_child(button("Back to recipes", refresh))
	content.add_child(row)
	EventBus.notify.emit("Crafted %s." % GameState.item_name(item))
	if str(item.get("legend", "")) != "":
		EventBus.celebrate.emit("LEGENDARY: %s" % GameState.item_name(item), GameState.item_base_name(item))
	elif quality == 3:
		EventBus.celebrate.emit("Masterwork!", GameState.item_name(item))


func close() -> void:
	if _game != null:
		_game.force_finish()
	super()
