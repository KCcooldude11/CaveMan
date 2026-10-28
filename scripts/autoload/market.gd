extends Node
## The village economy:
##  - material prices float with supply & demand (your purchases push prices
##    up, heroes selling dungeon loot pushes them down, everything drifts back)
##  - selling the same thing again and again saturates buyers (no infinite
##    craft-and-dump loops: the wholesaler never pays more than the materials)
##  - hero demand for kinds of gear follows the forecast (skeletons coming?
##    blunt weapons are hot) and cools when you flood the market
##  - Brannoc, the rival smith, sells to heroes you don't serve

var price_mult: Dictionary = {}    # material -> multiplier (1.0 = normal)
var saturation: Dictionary = {}    # recipe -> recent sales count (decays)
var recent_tags: Dictionary = {}   # tag -> recent sales to heroes (decays)
var temp_shocks: Array = []        # [{ material, mult, until_day }]
var rival_rep: float = 20.0
var rival_active := true
var contest_wins := 0              # contests you've won against Brannoc
var _rival_delta := 0.0            # tonight's swing from his customers


func reset() -> void:
	price_mult = {}
	saturation = {}
	recent_tags = {}
	temp_shocks = []
	rival_rep = float(_cfg_rival()["start_rep"])
	rival_active = true
	contest_wins = 0
	_rival_delta = 0.0


func _ready() -> void:
	reset()


static func _cfg() -> Dictionary:
	return DataDB.world["market"]


static func _cfg_rival() -> Dictionary:
	return DataDB.world["rival"]


# --- Materials ---------------------------------------------------------------

func mult(material: String) -> float:
	var m := float(price_mult.get(material, 1.0))
	for s in temp_shocks:
		if s["material"] == material and int(s["until_day"]) >= GameState.day:
			m *= float(s["mult"])
	return clampf(m, float(_cfg()["min_mult"]), float(_cfg()["max_mult"]))


func price(material: String) -> float:
	return float(DataDB.materials[material]["price"]) * mult(material)


func on_bought(material: String, count: int) -> void:
	_nudge(material, float(_cfg()["buy_impact"]) * count)


## Heroes brought this much of a material back to town.
func on_loot_arrived(material: String, count: int) -> void:
	_nudge(material, -float(_cfg()["loot_impact"]) * count)


func _nudge(material: String, amount: float) -> void:
	var m := float(price_mult.get(material, 1.0)) + amount
	price_mult[material] = clampf(m, float(_cfg()["min_mult"]), float(_cfg()["max_mult"]))


func add_shock(material: String, m: float, days: int) -> void:
	temp_shocks.append({ "material": material, "mult": m, "until_day": GameState.day + days })


## "Iron is cheap / expensive" hints for the UI.
func trend(material: String) -> String:
	var m := mult(material)
	if m >= 1.35:
		return "[color=#e06c6c]scarce[/color]"
	if m >= 1.1:
		return "[color=#e0b06c]pricey[/color]"
	if m <= 0.8:
		return "[color=#8fd18f]glut[/color]"
	return ""


# --- Selling gear back -------------------------------------------------------

func saturation_mult(recipe: String) -> float:
	return pow(1.0 - float(_cfg()["sale_saturation"]), float(saturation.get(recipe, 0.0)))


## What the wholesaler pays: a fraction of value, worn down by saturation,
## and never more than the raw materials cost (so dumping is never profit).
func wholesale_offer(item: Dictionary) -> int:
	var by_value := GameState.item_value(item) * 0.4 * saturation_mult(item["recipe"])
	var cap := GameState.recipe_cost(item["recipe"]) * float(_cfg()["wholesale_cost_cap"])
	return maxi(1, int(minf(by_value, cap)))


func on_item_dumped(item: Dictionary) -> void:
	saturation[item["recipe"]] = float(saturation.get(item["recipe"], 0.0)) + 1.0


# --- Hero demand ---------------------------------------------------------------

## Extra willingness to pay for gear with these tags (+/- fraction).
func demand(tags: Array) -> float:
	var d := 0.0
	var cfg := _cfg()
	# Upcoming threats (next 2 days) make their counters hot.
	var hot := {}
	for day in range(GameState.day, GameState.day + 2):
		for e in Village.events_on(day):
			for t in DataDB.enemies[e["enemy"]]["weak"]:
				hot[t] = true
	for t in tags:
		if hot.has(t):
			d += float(cfg["demand_threat_bonus"])
			break
	var flood := 0.0
	for t in tags:
		flood = maxf(flood, float(recent_tags.get(t, 0.0)))
	d -= flood * float(cfg["demand_per_recent_sale"])
	return maxf(d, float(cfg["demand_floor"]))


func demand_label(tags: Array) -> String:
	var d := demand(tags)
	if d >= 0.15:
		return "[color=#8fd18f]in demand[/color]"
	if d <= -0.15:
		return "[color=#e0b06c]market flooded[/color]"
	return ""


func on_sold_to_hero(tags: Array) -> void:
	for t in tags:
		recent_tags[t] = float(recent_tags.get(t, 0.0)) + 1.0


# --- Rival smith ---------------------------------------------------------------

## Overnight, Brannoc sells to heroes who still lack gear. Returns report lines.
func rival_night(unserved: Array) -> Array:
	var lines: Array = []
	if not rival_active:
		return lines
	var cfg := _cfg_rival()
	for adv in unserved:
		if randf() > float(cfg["steal_chance"]) * clampf(rival_rep / maxf(10.0, GameState.renown + 10.0), 0.3, 1.5):
			continue
		var slot: String = AdventurerManager.wants(adv)["slot"]
		var power := int(round(4 + rival_rep * float(cfg["power_per_rep"]) + int(adv["level"])))
		var cur = adv["gear"][slot]
		if cur != null and int(cur["power"]) >= power:
			continue
		var cost := power * 6
		if int(adv["gold"]) < cost:
			continue
		adv["gold"] = int(adv["gold"]) - cost
		adv["gear"][slot] = { "name": "Brannoc's %s" % slot.capitalize(), "slot": slot, "recipe": "",
			"power": power, "tags": [], "player_made": false, "rival_made": true, "affixes": [], "legend": "" }
		lines.append("%s bought %s gear from %s." % [adv["name"], slot, cfg["shop"]])
	return lines


func rival_gear_won() -> void:
	_rival_delta += 0.4


func rival_gear_failed() -> void:
	_rival_delta -= 0.4


## Daily drift: your fame slowly squeezes Brannoc out, and he can leave town.
func night_update() -> Array:
	var lines: Array = []
	var cfg := _cfg()
	var recover := float(cfg["recover"]) * (1.5 if Village.project_done("market") else 1.0)
	for m in price_mult.keys():
		price_mult[m] = lerpf(float(price_mult[m]), 1.0, recover)
	for r in saturation.keys():
		saturation[r] = float(saturation[r]) * (1.0 - float(cfg["saturation_recover"]))
	for t in recent_tags.keys():
		recent_tags[t] = float(recent_tags[t]) * 0.7
	temp_shocks = temp_shocks.filter(func(s): return int(s["until_day"]) > GameState.day)
	if rival_active:
		# Brannoc improves as the village grows, trailing your fame; his
		# customers' fortunes swing it a little each night.
		var target := 10.0 + 0.7 * GameState.renown
		rival_rep += (target - rival_rep) * 0.06 + clampf(_rival_delta, -1.5, 1.5)
		rival_rep = maxf(0.0, rival_rep)
		_rival_delta = 0.0
		# Beat him twice in open contest while out-shining him and he leaves.
		if contest_wins >= 2 and GameState.renown >= rival_rep * 1.2:
			rival_active = false
			lines.append("[color=#ffc94a]%s has closed his smithy and left town. The heroes are yours.[/color]" % _cfg_rival()["name"])
			Chronicle.add("%s closed his smithy and left town, outshone by your work." % _cfg_rival()["name"], "milestone")
	return lines


func to_dict() -> Dictionary:
	return { "price_mult": price_mult, "saturation": saturation, "recent_tags": recent_tags,
		"temp_shocks": temp_shocks, "rival_rep": rival_rep, "rival_active": rival_active,
		"contest_wins": contest_wins }


func from_dict(d: Dictionary) -> void:
	reset()
	price_mult = d.get("price_mult", {})
	saturation = d.get("saturation", {})
	recent_tags = d.get("recent_tags", {})
	temp_shocks = d.get("temp_shocks", [])
	rival_rep = float(d.get("rival_rep", rival_rep))
	rival_active = bool(d.get("rival_active", true))
	contest_wins = int(d.get("contest_wins", 0))
