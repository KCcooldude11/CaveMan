extends Node
## Loads all static game content from res://data/*.json.
## Want a new sword, dungeon or upgrade? Edit the JSON - no code needed.

const QUALITIES := [
	{ "name": "Crude", "mult": 0.75, "color": Color("9a8f86") },
	{ "name": "Common", "mult": 1.0, "color": Color("e8e2d6") },
	{ "name": "Fine", "mult": 1.3, "color": Color("6fc3ff") },
	{ "name": "Masterwork", "mult": 1.7, "color": Color("ffc94a") },
]
const SLOTS := ["weapon", "armor", "trinket"]
const STATION_NAMES := { "forge": "Forge", "workbench": "Workbench", "jeweler": "Jeweler's Bench" }

var materials: Dictionary = {}
var recipes: Dictionary = {}
var classes: Dictionary = {}
var dungeons: Array = []
var upgrades: Dictionary = {}
var renown_tiers: Array = []
var dial: Dictionary = {}


func _ready() -> void:
	materials = _load("res://data/materials.json")
	recipes = _load("res://data/recipes.json")
	classes = _load("res://data/classes.json")
	dungeons = _load("res://data/dungeons.json")
	upgrades = _load("res://data/upgrades.json")
	renown_tiers = _load("res://data/renown_tiers.json")
	dial = _load("res://data/dial_minigame.json")


func _load(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("DataDB: could not parse %s" % path)
	return parsed


func material_name(id: String) -> String:
	return materials.get(id, {}).get("name", id)


func recipes_for_station(station: String) -> Array:
	var out: Array = []
	for id in recipes:
		if recipes[id]["station"] == station:
			out.append(id)
	out.sort_custom(func(a, b): return recipes[a]["renown"] < recipes[b]["renown"])
	return out


func tier_for_renown(renown: int) -> Dictionary:
	var best: Dictionary = renown_tiers[0]
	for t in renown_tiers:
		if renown >= int(t["min"]):
			best = t
	return best


func next_tier(renown: int) -> Variant:
	for t in renown_tiers:
		if int(t["min"]) > renown:
			return t
	return null


func format_inputs(inputs: Dictionary) -> String:
	var parts: PackedStringArray = []
	for m in inputs:
		parts.append("%dx %s" % [int(inputs[m]), material_name(m)])
	return ", ".join(parts)
