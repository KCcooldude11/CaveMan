extends BaseMenu
## Recipe list for one crafting station, then the forging minigame.

const Minigame := preload("res://scripts/ui/forge_minigame.gd")

var station: String
var _game: Node = null
var _recipe: String = ""


func _init(station_id: String) -> void:
	station = station_id
	super(DataDB.STATION_NAMES[station_id])


func build() -> void:
	_game = null
	title_label.text = "%s  (Lv %d)" % [DataDB.STATION_NAMES[station], GameState.station_level(station)]
	add_label("Choose something to make. Better strikes in the minigame = better quality = higher prices and stronger adventurers.", 15, Color("b8b0a0"))
	for id in DataDB.recipes_for_station(station):
		var r: Dictionary = DataDB.recipes[id]
		var unlocked := GameState.is_recipe_unlocked(id)
		var parts: PackedStringArray = []
		for m in r["inputs"]:
			var need := int(r["inputs"][m])
			var have := GameState.material_count(m)
			var col := "8fd18f" if have >= need else "e06c6c"
			parts.append("[color=#%s]%d/%d %s[/color]" % [col, have, need, DataDB.material_name(m)])
		var text := "[b]%s[/b]  [color=#b8b0a0]%s, power %d, ~%dg[/color]\n%s" % [
			r["name"], r["slot"], int(r["power"]), int(r["value"]), "  ".join(parts)]
		var btn: Button
		if not unlocked:
			text = "[color=#777]%s[/color]" % text
			btn = button("Renown %d" % int(r["renown"]), func(): pass, true)
		else:
			btn = button("Craft", _start_craft.bind(id), not GameState.has_materials(r["inputs"]))
		add_row(text, [btn])


func _start_craft(id: String) -> void:
	var r: Dictionary = DataDB.recipes[id]
	if not GameState.consume_materials(r["inputs"]):
		return
	_recipe = id
	for c in content.get_children():
		c.queue_free()
	add_heading("Forging: %s" % r["name"])
	_game = Minigame.new()
	_game.configure(GameState.station_level(station), int(r["power"]))
	_game.finished.connect(_on_finished)
	content.add_child(_game)


func _on_finished(quality: int) -> void:
	var item := GameState.create_item(_recipe, quality)
	var q: Dictionary = DataDB.QUALITIES[quality]
	_game = null
	add_rich("\n[font_size=22]You made a [color=#%s]%s[/color]![/font_size]\nPower %d, fair value %dg. It's waiting on your shelf for a buyer." % [
		hex(q["color"]), GameState.item_name(item), GameState.item_power(item), GameState.item_value(item)])
	var row := HBoxContainer.new()
	var again := button("Make another", _start_craft.bind(_recipe), not GameState.has_materials(DataDB.recipes[_recipe]["inputs"]))
	row.add_child(again)
	row.add_child(button("Back to recipes", refresh))
	content.add_child(row)
	EventBus.notify.emit("Crafted %s." % GameState.item_name(item))


func close() -> void:
	if _game != null:
		_game.force_finish()
	super()
