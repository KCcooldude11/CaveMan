extends Node
## Everything about *you*, the craftsman: money, renown, stock, upgrades,
## crafting mastery, discoveries and the legendary items you've forged.
## Also owns saving/loading (every other system saves through here).

const SAVE_PATH := "user://savegame.json"
const START_GOLD := 150
## Crafts needed for mastery levels 1..4 in a weapon family.
const MASTERY_STEPS := [3, 8, 15, 25]
const MASTERY_FAMILIES := {
	"blades": "Blades", "crushers": "Axes & Maces", "ranged": "Bows & Staves",
	"armor": "Armor", "jewelry": "Jewelry",
}
const LEGEND_PREFIX := ["Grave", "Dawn", "Storm", "Ember", "Night", "Wolf", "Star", "Oath", "Ash", "Frost", "Thorn", "Sorrow"]
const LEGEND_SUFFIX := {
	"weapon": ["cleaver", "fang", "song", "bane", "brand", "breaker", "whisper", "call", "reaver", "edge"],
	"armor": ["mantle", "aegis", "shroud", "ward", "hide", "bulwark"],
	"trinket": ["eye", "heart", "charm", "sigil", "tear", "star"],
}

var gold: int = START_GOLD
var renown: int = 0
var day: int = 1
var materials: Dictionary = {}   # material id -> count
var items: Array = []            # crafted items on your shelf (see create_item)
var upgrades: Dictionary = {}    # upgrade id -> level
var last_recipe: String = ""
var next_uid: int = 1
var stats: Dictionary = {}
var first_clears: Array = []     # dungeon ids first cleared by someone in your gear
var mastery: Dictionary = {}     # family -> crafts made
var known_blueprints: Array = [] # blueprint recipe ids you've learned
var discovered_affixes: Array = [] # affix ids whose effect you've seen
var legends: Dictionary = {}     # legend id (string) -> legend record
var next_legend: int = 1


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
	stats = { "crafted": 0, "sold": 0, "earned": 0, "masterworks": 0, "legends": 0 }
	first_clears = []
	mastery = {}
	known_blueprints = []
	discovered_affixes = []
	legends = {}
	next_legend = 1


# --- Gold & renown -----------------------------------------------------------

func add_gold(amount: int) -> void:
	gold += amount
	if amount > 0:
		stats["earned"] += amount
	EventBus.gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if amount < 0 or amount > gold:
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
		Chronicle.add("Your name spreads: you are now known as a %s." % new_tier["name"], "milestone")


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


## Supplier price right now (market supply/demand, minus your contacts).
func material_price(id: String) -> int:
	var discount := 0.1 * upgrade_level("contacts")
	return maxi(1, int(round(Market.price(id) * (1.0 - discount))))


## Buy from the supplier one unit at a time (each purchase nudges the price
## up). Returns how many were bought.
func buy_material(id: String, count: int) -> int:
	if not DataDB.materials[id]["buyable"]:
		return 0
	var bought := 0
	for i in count:
		if not spend_gold(material_price(id)):
			break
		add_material(id, 1)
		Market.on_bought(id, 1)
		bought += 1
	return bought


## What the raw materials of a recipe cost at the supplier right now.
func recipe_cost(recipe_id: String) -> int:
	var total := 0
	var r: Dictionary = DataDB.recipes[recipe_id]
	for m in r["inputs"]:
		total += int(round(Market.price(m))) * int(r["inputs"][m])
	return total


# --- Items -----------------------------------------------------------------
## Items are plain dictionaries so they save to JSON trivially:
## { uid, recipe, quality, affixes: [ids], bonus: int, legend: id or "" }

func create_item(recipe_id: String, quality: int, affixes: Array = [], bonus := 0) -> Dictionary:
	var item := { "uid": next_uid, "recipe": recipe_id, "quality": quality,
		"affixes": affixes.duplicate(), "bonus": bonus, "legend": "" }
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


func find_item(uid: int) -> Dictionary:
	for it in items:
		if int(it["uid"]) == uid:
			return it
	return {}


func item_name(item: Dictionary) -> String:
	if str(item.get("legend", "")) != "" and legends.has(item["legend"]):
		return legends[item["legend"]]["name"]
	var q: Dictionary = DataDB.QUALITIES[int(item["quality"])]
	var parts: PackedStringArray = [q["name"]]
	for a in item.get("affixes", []):
		parts.append(DataDB.affixes[a]["name"])
	parts.append(DataDB.recipes[item["recipe"]]["name"])
	return " ".join(parts)


## Full description used under a legend's name, e.g. "Masterwork Flaming War Axe".
func item_base_name(item: Dictionary) -> String:
	var copy := item.duplicate()
	copy["legend"] = ""
	return item_name(copy)


func item_tags(item: Dictionary) -> Array:
	var tags: Array = DataDB.recipes[item["recipe"]]["tags"].duplicate()
	for a in item.get("affixes", []):
		for t in DataDB.affixes[a].get("add_tags", []):
			if not t in tags:
				tags.append(t)
	return tags


func item_power(item: Dictionary) -> int:
	var r: Dictionary = DataDB.recipes[item["recipe"]]
	var p := float(r["power"]) * float(DataDB.QUALITIES[int(item["quality"])]["mult"])
	for a in item.get("affixes", []):
		p *= float(DataDB.affixes[a].get("power_mult", 1.0))
	return int(round(p)) + int(item.get("bonus", 0))


## The "fair" price an average adventurer would pay.
func item_value(item: Dictionary) -> int:
	var r: Dictionary = DataDB.recipes[item["recipe"]]
	var v := float(r["value"]) * float(DataDB.QUALITIES[int(item["quality"])]["mult"])
	for a in item.get("affixes", []):
		v *= float(DataDB.affixes[a].get("value_mult", 1.0))
	if str(item.get("legend", "")) != "":
		v *= 1.5
	return int(round(v))


func item_slot(item: Dictionary) -> String:
	return DataDB.recipes[item["recipe"]]["slot"]


## Snapshot an item into the form adventurers carry as gear.
func item_to_gear(item: Dictionary) -> Dictionary:
	return {
		"name": item_name(item), "slot": item_slot(item), "recipe": item["recipe"],
		"power": item_power(item), "tags": item_tags(item), "player_made": true,
		"affixes": item.get("affixes", []).duplicate(), "legend": str(item.get("legend", "")),
	}


## Combined effect of affixes on a gear/item: mode "mult" multiplies, "add"
## sums, "any" returns true if any affix has the flag.
static func affix_effect(affix_ids: Array, key: String, mode := "mult") -> Variant:
	if mode == "any":
		for a in affix_ids:
			if DataDB.affixes[a].get(key, false):
				return true
		return false
	var v := 1.0 if mode == "mult" else 0.0
	for a in affix_ids:
		if DataDB.affixes[a].has(key):
			v = v * float(DataDB.affixes[a][key]) if mode == "mult" else v + float(DataDB.affixes[a][key])
	return v


## The affix (if any) a rare material grants when infused.
static func affix_for_infusion(material: String) -> String:
	for a in DataDB.affixes:
		var inf = DataDB.affixes[a].get("infusion", "")
		if (inf is String and inf == material) or (inf is Array and material in inf):
			return a
	return ""


static func infusion_materials() -> Array:
	var out: Array = []
	for a in DataDB.affixes:
		var inf = DataDB.affixes[a].get("infusion", "")
		if inf is String and inf != "":
			out.append(inf)
		elif inf is Array:
			out.append_array(inf)
	return out


# --- Crafting, mastery & discoveries --------------------------------------------

static func mastery_family(recipe_id: String) -> String:
	var r: Dictionary = DataDB.recipes[recipe_id]
	if r["slot"] == "armor":
		return "armor"
	if r["slot"] == "trinket":
		return "jewelry"
	var tags: Array = r["tags"]
	if "blunt" in tags or "axe" in tags:
		return "crushers"
	if "bow" in tags or "staff" in tags:
		return "ranged"
	return "blades"


func mastery_level(family: String) -> int:
	var n := int(mastery.get(family, 0))
	var lvl := 0
	for step in MASTERY_STEPS:
		if n >= step:
			lvl += 1
	return lvl


## Step 1 of crafting: pay the materials (plus one infusion material).
func begin_craft(recipe_id: String, infusion := "") -> bool:
	var inputs: Dictionary = DataDB.recipes[recipe_id]["inputs"].duplicate()
	if infusion != "":
		if affix_for_infusion(infusion) == "":
			return false
		inputs[infusion] = int(inputs.get(infusion, 0)) + 1
	if not is_recipe_unlocked(recipe_id):
		return false
	return consume_materials(inputs)


## Step 2: the minigame decided the quality; make the item. Handles mastery,
## surprise discoveries and legends. Returns { item, notes: [strings] }.
func finish_craft(recipe_id: String, quality: int, infusion := "") -> Dictionary:
	var notes: Array = []
	var affixes: Array = []
	if infusion != "":
		var a := affix_for_infusion(infusion)
		affixes.append(a)
		if not a in discovered_affixes:
			discovered_affixes.append(a)
			notes.append("Discovery! %s: %s" % [DataDB.affixes[a]["name"], DataDB.affixes[a]["desc"]])
			Chronicle.add("You discovered how to forge %s gear by infusing %s." % [DataDB.affixes[a]["name"], DataDB.material_name(infusion)], "discovery")
	var family := mastery_family(recipe_id)
	var lvl := mastery_level(family)
	# Excellent work sometimes produces something unexpected.
	if quality >= 2:
		var chance := (0.06 if quality == 2 else 0.14) + 0.03 * lvl
		if randf() < chance:
			var d := "keen" if randf() < 0.7 else "cursed"
			if not d in affixes:
				affixes.append(d)
				notes.append("The %s came out %s! %s" % [DataDB.recipes[recipe_id]["name"], DataDB.affixes[d]["name"], DataDB.affixes[d]["desc"]])
				if not d in discovered_affixes:
					discovered_affixes.append(d)
	var bonus := 1 if lvl >= 3 else 0
	var item := create_item(recipe_id, quality, affixes, bonus)
	mastery[family] = int(mastery.get(family, 0)) + 1
	if mastery_level(family) > lvl:
		notes.append("Mastery up: %s level %d (wider sweet spots, more discoveries%s)." % [
			MASTERY_FAMILIES[family], mastery_level(family), ", +1 power" if mastery_level(family) >= 3 else ""])
		Chronicle.add("You reached %s mastery level %d." % [MASTERY_FAMILIES[family], mastery_level(family)], "milestone")
	var legendary := affix_effect(affixes, "always_legendary", "any") as bool
	# Legends need intent: a Masterwork deliberately infused with a rare
	# material - and a little luck - or a slain boss's trophy.
	if not legendary and quality == 3 and infusion != "":
		legendary = randf() < 0.12
	if legendary:
		_make_legend(item)
		notes.append("LEGENDARY! You forged %s, a %s. Its story begins today." % [item_name(item), item_base_name(item)])
	return { "item": item, "notes": notes }


## Convenience: begin + finish in one call (apprentice, tests).
func craft(recipe_id: String, quality: int, infusion := "") -> Dictionary:
	if not begin_craft(recipe_id, infusion):
		return {}
	return finish_craft(recipe_id, quality, infusion)


func _make_legend(item: Dictionary) -> void:
	var slot := item_slot(item)
	var used: Array = legends.values().map(func(l): return l["name"])
	var legend_name := ""
	for attempt in 20:
		legend_name = (LEGEND_PREFIX.pick_random() + LEGEND_SUFFIX[slot].pick_random()).capitalize()
		if not legend_name in used:
			break
	var id := "L%d" % next_legend
	next_legend += 1
	legends[id] = {
		"id": id, "name": legend_name, "recipe": item["recipe"], "base": item_base_name(item),
		"forged_day": day, "status": "shelf", "holder": 0, "holder_name": "", "kills": 0,
		"location": "", "history": ["Forged on Day %d." % day],
		"item": { "recipe": item["recipe"], "quality": item["quality"], "affixes": item["affixes"].duplicate(),
			"bonus": item.get("bonus", 0) },
	}
	item["legend"] = id
	stats["legends"] += 1
	Chronicle.add("You forged the legendary %s (%s)." % [legend_name, item_base_name(item)], "legend")


## A lost legend comes home: it goes back on your shelf.
func restore_legend(id: String) -> Dictionary:
	if not legends.has(id):
		return {}
	var base: Dictionary = legends[id]["item"]
	var item := { "uid": next_uid, "recipe": base["recipe"], "quality": int(base["quality"]),
		"affixes": base["affixes"].duplicate(), "bonus": int(base.get("bonus", 0)), "legend": id }
	next_uid += 1
	items.append(item)
	legends[id]["status"] = "shelf"
	legends[id]["holder"] = 0
	legends[id]["holder_name"] = ""
	legends[id]["location"] = ""
	EventBus.inventory_changed.emit()
	return item


func legend_event(id: String, text: String) -> void:
	if legends.has(id):
		legends[id]["history"].append("Day %d: %s" % [day, text])


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
	var r: Dictionary = DataDB.recipes[recipe_id]
	if r.get("blueprint", false) and not recipe_id in known_blueprints:
		return false
	return renown >= int(r["renown"])


func learn_blueprint(recipe_id: String, source: String) -> bool:
	if recipe_id in known_blueprints or not DataDB.recipes.has(recipe_id):
		return false
	known_blueprints.append(recipe_id)
	EventBus.notify.emit("New blueprint: %s!" % DataDB.recipes[recipe_id]["name"])
	Chronicle.add("You learned to make the %s (%s)." % [DataDB.recipes[recipe_id]["name"], source], "discovery")
	return true


## Nightly apprentice work. Returns a description or "".
func run_apprentice() -> String:
	var lvl := upgrade_level("apprentice")
	if lvl <= 0 or last_recipe == "":
		return ""
	var made := 0
	var recipe := last_recipe
	for i in lvl:
		if not craft(recipe, 1).is_empty():
			made += 1
	if made == 0:
		return "Your apprentice had no materials to make a %s." % DataDB.recipes[recipe]["name"]
	return "Your apprentice crafted %d %s overnight." % [made, DataDB.recipes[recipe]["name"]]


# --- Save / load -------------------------------------------------------------

## Every system that saves: name -> autoload. Each has to_dict()/from_dict().
func _systems() -> Dictionary:
	return { "adventurers": AdventurerManager, "village": Village, "dungeons": Dungeons,
		"market": Market, "chronicle": Chronicle, "happenings": Happenings }


func to_dict() -> Dictionary:
	var d := {
		"gold": gold, "renown": renown, "day": day, "materials": materials,
		"items": items, "upgrades": upgrades, "last_recipe": last_recipe,
		"next_uid": next_uid, "stats": stats, "first_clears": first_clears,
		"mastery": mastery, "known_blueprints": known_blueprints,
		"discovered_affixes": discovered_affixes, "legends": legends, "next_legend": next_legend,
	}
	var sys := _systems()
	for k in sys:
		d[k] = sys[k].to_dict()
	return d


func from_dict(raw: Dictionary) -> void:
	var d: Dictionary = jsonfix(raw)
	reset()
	gold = int(d.get("gold", START_GOLD))
	renown = int(d.get("renown", 0))
	day = int(d.get("day", 1))
	materials = d.get("materials", {})
	items = []
	for it in d.get("items", []):
		var item: Dictionary = { "affixes": [], "bonus": 0, "legend": "" }
		item.merge(it, true)
		items.append(item)
	for id in d.get("upgrades", {}):
		upgrades[id] = int(d["upgrades"][id])
	last_recipe = d.get("last_recipe", "")
	next_uid = int(d.get("next_uid", 1))
	stats.merge(d.get("stats", {}), true)
	first_clears = d.get("first_clears", [])
	mastery = d.get("mastery", {})
	known_blueprints = d.get("known_blueprints", [])
	discovered_affixes = d.get("discovered_affixes", [])
	legends = d.get("legends", {})
	next_legend = int(d.get("next_legend", 1))
	var sys := _systems()
	for k in sys:
		sys[k].from_dict(d.get(k, {}))
	EventBus.gold_changed.emit(gold)
	EventBus.renown_changed.emit(renown)
	EventBus.materials_changed.emit()
	EventBus.inventory_changed.emit()
	EventBus.upgrades_changed.emit()


## Resets every system for a brand-new game.
func new_game() -> void:
	reset()
	for s in _systems().values():
		s.reset()


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


## JSON turns every number into a float. Turn whole-number floats back into
## ints (recursively) so saved data behaves exactly like fresh data.
static func jsonfix(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if v == floor(v) and absf(v) < 1e12 else v
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[k] = jsonfix(v[k])
			return out
		TYPE_ARRAY:
			return v.map(func(x): return jsonfix(x))
	return v


## Back-compat helper used by older code paths.
static func _int_values(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = int(d[k])
	return out
