extends Node
## Everything about *you*, the craftsman: money, renown, stock and upgrades.
## Also owns saving/loading (adventurer roster is saved via AdventurerManager).

const SAVE_PATH := "user://savegame.json"
const START_GOLD := 150

var gold: int = START_GOLD
var renown: int = 0
var day: int = 1
var materials: Dictionary = {}   # material id -> count
var items: Array = []            # crafted items waiting to be sold (see create_item)
var upgrades: Dictionary = {}    # upgrade id -> level
var last_recipe: String = ""
var next_uid: int = 1
var stats: Dictionary = {}
var first_clears: Array = []     # dungeon ids first cleared by someone in your gear


func _ready() -> void:
	reset()


func reset() -> void:
	gold = START_GOLD
	renown = 0
	day = 1
	materials = { "iron_ingot": 4, "wood": 4, "leather": 3 }
	items = []
	upgrades = {}
	for id in DataDB.upgrades:
		upgrades[id] = int(DataDB.upgrades[id]["start"])
	last_recipe = ""
	next_uid = 1
	stats = { "crafted": 0, "sold": 0, "earned": 0, "masterworks": 0 }
	first_clears = []


# --- Gold & renown -----------------------------------------------------------

func add_gold(amount: int) -> void:
	gold += amount
	if amount > 0:
		stats["earned"] += amount
	EventBus.gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if amount > gold:
		return false
	gold -= amount
	EventBus.gold_changed.emit(gold)
	return true


func add_renown(amount: int) -> void:
	if amount == 0:
		return
	var old_tier: Dictionary = DataDB.tier_for_renown(renown)
	renown = max(0, renown + amount)
	EventBus.renown_changed.emit(renown)
	var new_tier: Dictionary = DataDB.tier_for_renown(renown)
	if new_tier["name"] != old_tier["name"] and amount > 0:
		EventBus.notify.emit("Your reputation grows! You are now a %s." % new_tier["name"])


# --- Materials -------------------------------------------------------------

func material_count(id: String) -> int:
	return int(materials.get(id, 0))


func add_material(id: String, count: int) -> void:
	materials[id] = material_count(id) + count
	EventBus.materials_changed.emit()


func has_materials(inputs: Dictionary) -> bool:
	for m in inputs:
		if material_count(m) < int(inputs[m]):
			return false
	return true


func consume_materials(inputs: Dictionary) -> bool:
	if not has_materials(inputs):
		return false
	for m in inputs:
		materials[m] = material_count(m) - int(inputs[m])
	EventBus.materials_changed.emit()
	return true


func material_price(id: String) -> int:
	var base: int = int(DataDB.materials[id]["price"])
	var discount := 0.1 * upgrade_level("contacts")
	return max(1, int(round(base * (1.0 - discount))))


# --- Items -----------------------------------------------------------------

## Items are plain dictionaries so they save to JSON trivially.
func create_item(recipe_id: String, quality: int) -> Dictionary:
	var item := { "uid": next_uid, "recipe": recipe_id, "quality": quality }
	next_uid += 1
	items.append(item)
	stats["crafted"] += 1
	if quality == DataDB.QUALITIES.size() - 1:
		stats["masterworks"] += 1
	last_recipe = recipe_id
	EventBus.inventory_changed.emit()
	return item


func remove_item(uid: int) -> void:
	for i in items.size():
		if int(items[i]["uid"]) == uid:
			items.remove_at(i)
			EventBus.inventory_changed.emit()
			return


func item_name(item: Dictionary) -> String:
	var q: Dictionary = DataDB.QUALITIES[int(item["quality"])]
	return "%s %s" % [q["name"], DataDB.recipes[item["recipe"]]["name"]]


func item_power(item: Dictionary) -> int:
	var r: Dictionary = DataDB.recipes[item["recipe"]]
	return int(round(float(r["power"]) * DataDB.QUALITIES[int(item["quality"])]["mult"]))


## The "fair" price an average adventurer would pay.
func item_value(item: Dictionary) -> int:
	var r: Dictionary = DataDB.recipes[item["recipe"]]
	return int(round(float(r["value"]) * DataDB.QUALITIES[int(item["quality"])]["mult"]))


func item_slot(item: Dictionary) -> String:
	return DataDB.recipes[item["recipe"]]["slot"]


# --- Upgrades & unlocks ------------------------------------------------------

func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))


func upgrade_max(id: String) -> int:
	var u: Dictionary = DataDB.upgrades[id]
	return int(u["start"]) + u["costs"].size()


## Returns {cost, renown} for the next level, or {} if maxed.
func upgrade_next(id: String) -> Dictionary:
	var u: Dictionary = DataDB.upgrades[id]
	var idx := upgrade_level(id) - int(u["start"])
	if idx >= u["costs"].size():
		return {}
	return { "cost": int(u["costs"][idx]), "renown": int(u["renown"][idx]) }


func buy_upgrade(id: String) -> bool:
	var nxt := upgrade_next(id)
	if nxt.is_empty() or renown < nxt["renown"] or not spend_gold(nxt["cost"]):
		return false
	upgrades[id] = upgrade_level(id) + 1
	EventBus.upgrades_changed.emit()
	return true


func station_level(station: String) -> int:
	return upgrade_level(station)


func is_recipe_unlocked(recipe_id: String) -> bool:
	return renown >= int(DataDB.recipes[recipe_id]["renown"])


## Nightly apprentice work. Returns a description or "".
func run_apprentice() -> String:
	var lvl := upgrade_level("apprentice")
	if lvl <= 0 or last_recipe == "":
		return ""
	var made := 0
	var inputs: Dictionary = DataDB.recipes[last_recipe]["inputs"]
	for i in lvl:
		if consume_materials(inputs):
			create_item(last_recipe, 1)
			made += 1
	if made == 0:
		return "Your apprentice had no materials to make a %s." % DataDB.recipes[last_recipe]["name"]
	return "Your apprentice crafted %d %s overnight." % [made, DataDB.recipes[last_recipe]["name"]]


# --- Save / load -------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"gold": gold, "renown": renown, "day": day, "materials": materials,
		"items": items, "upgrades": upgrades, "last_recipe": last_recipe,
		"next_uid": next_uid, "stats": stats, "first_clears": first_clears,
		"adventurers": AdventurerManager.to_dict(),
		"village": Village.to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	reset()
	gold = int(d.get("gold", START_GOLD))
	renown = int(d.get("renown", 0))
	day = int(d.get("day", 1))
	materials = _int_values(d.get("materials", {}))
	items = []
	for it in d.get("items", []):
		items.append({ "uid": int(it["uid"]), "recipe": it["recipe"], "quality": int(it["quality"]) })
	for id in d.get("upgrades", {}):
		upgrades[id] = int(d["upgrades"][id])
	last_recipe = d.get("last_recipe", "")
	next_uid = int(d.get("next_uid", 1))
	stats.merge(_int_values(d.get("stats", {})), true)
	first_clears = d.get("first_clears", []).duplicate()
	AdventurerManager.from_dict(d.get("adventurers", {}))
	Village.from_dict(d.get("village", {}))
	EventBus.gold_changed.emit(gold)
	EventBus.renown_changed.emit(renown)
	EventBus.materials_changed.emit()
	EventBus.inventory_changed.emit()
	EventBus.upgrades_changed.emit()


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict(), "\t"))


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_game() -> bool:
	if not has_save():
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	from_dict(parsed)
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## JSON turns every number into a float; convert back to ints.
static func _int_values(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = int(d[k])
	return out
