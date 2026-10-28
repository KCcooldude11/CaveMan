extends Node
## Life in the village beyond your shop:
##  - the dungeon FORECAST: upcoming swarms, invasions and rich veins, so you
##    can craft the right counters and know which loot will be for sale
##  - COMMISSIONS posted on the notice board
##  - the travelling MERCHANT who visits every few days
##  - the TAVERN (rumors reveal the forecast further ahead)
##  - free GATHERING spots (old mine, woodcutter's grove), once per day
##
## Forecast events are plain dictionaries:
##   { day, dungeon, kind, enemy, loot_mult, extra: {material: [min,max]}, bounty, text }

var events: Array = []
var commissions: Array = []
var next_commission_id := 1
var rumor_day := 0             # day on which you last bought a round
var gathered: Dictionary = {}  # spot id -> day last gathered
var merchant_stock: Dictionary = {}  # material -> count (on merchant days)


func reset() -> void:
	events = []
	commissions = []
	next_commission_id = 1
	rumor_day = 0
	gathered = {}
	merchant_stock = {}


## Called every morning before adventurers plan their day.
func start_day(day: int) -> void:
	events = events.filter(func(e): return int(e["day"]) >= day)
	var cfg: Dictionary = DataDB.village["forecast"]
	for d in range(day, day + int(cfg["rumor_days_ahead"])):
		if events_on(d).is_empty():
			_generate_events(d)
	_update_commissions(day)
	merchant_stock = {}
	if merchant_here(day):
		_stock_merchant()


# --- Forecast ----------------------------------------------------------------

func events_on(day: int) -> Array:
	return events.filter(func(e): return int(e["day"]) == day)


func event_for(dungeon_id: String, day: int) -> Dictionary:
	for e in events:
		if int(e["day"]) == day and e["dungeon"] == dungeon_id:
			return e
	return {}


## How many days ahead you can see (rumors from the tavern extend it).
func visible_days() -> int:
	var cfg: Dictionary = DataDB.village["forecast"]
	return int(cfg["rumor_days_ahead"]) if rumor_day == GameState.day else int(cfg["days_ahead"])


## Dungeons a hero at your current fame tier might actually visit.
func reachable_dungeons() -> Array:
	var tier_index := 0
	for i in DataDB.renown_tiers.size():
		if GameState.renown >= int(DataDB.renown_tiers[i]["min"]):
			tier_index = i
	return DataDB.dungeons.slice(0, mini(DataDB.dungeons.size(), tier_index + 2))


func _generate_events(day: int) -> void:
	var cfg: Dictionary = DataDB.village["forecast"]
	var count := randi_range(int(cfg["events_per_day"][0]), int(cfg["events_per_day"][1]))
	var pool := reachable_dungeons()
	pool.shuffle()
	for i in mini(count, pool.size()):
		events.append(_make_event(day, pool[i]))


func _make_event(day: int, d: Dictionary) -> Dictionary:
	var cfg: Dictionary = DataDB.village["forecast"]
	var kinds: Dictionary = cfg["kinds"]
	var kind := _weighted_pick(kinds)
	var k: Dictionary = kinds[kind]
	var enemy: String = d["enemy"]
	var extra := {}
	if kind == "invasion":
		var others: Array = DataDB.enemies.keys().filter(func(e): return e != d["enemy"])
		enemy = others.pick_random()
	elif kind == "vein":
		var mat: String = cfg["vein_materials"].pick_random()
		extra[mat] = [1, 3]
	var text: String = k["text"].format({
		"enemy": DataDB.enemies[enemy]["name"], "dungeon": d["name"],
		"extra": DataDB.format_loot(extra)})
	return {
		"day": day, "dungeon": d["id"], "kind": kind, "enemy": enemy,
		"loot_mult": float(k["loot_mult"]), "extra": extra,
		"bounty": randi_range(int(k["bounty"][0]), int(k["bounty"][1])), "text": text,
	}


static func _weighted_pick(options: Dictionary) -> String:
	var total := 0.0
	for k in options:
		total += float(options[k]["weight"])
	var roll := randf() * total
	for k in options:
		roll -= float(options[k]["weight"])
		if roll <= 0.0:
			return k
	return options.keys()[0]


## What a dungeon looks like on a given day: enemy, loot table, bounty.
func conditions(dungeon_id: String, day: int) -> Dictionary:
	var d := DataDB.dungeon(dungeon_id)
	var e := event_for(dungeon_id, day)
	var enemy: String = e.get("enemy", d["enemy"])
	var mult: float = e.get("loot_mult", 1.0)
	var loot := {}
	for m in DataDB.enemies[enemy]["loot"]:
		var r: Array = DataDB.enemies[enemy]["loot"][m]
		loot[m] = [int(round(int(r[0]) * mult)), int(round(int(r[1]) * mult))]
	for m in e.get("extra", {}):
		loot[m] = e["extra"][m]
	return { "dungeon": d, "enemy": enemy, "loot": loot, "bounty": int(e.get("bounty", 0)), "event": e }


# --- Commissions ---------------------------------------------------------------

func _update_commissions(day: int) -> void:
	for c in commissions.duplicate():
		if int(c["due"]) < day:
			commissions.erase(c)
			EventBus.notify.emit("%s's commission expired." % c["giver"])
	var cfg: Dictionary = DataDB.village["commissions"]
	if commissions.size() < int(cfg["max_active"]) and (commissions.is_empty() or randf() < float(cfg["new_chance"])):
		var c := _make_commission(day)
		if not c.is_empty():
			commissions.append(c)
			EventBus.notify.emit("New commission on the notice board from %s." % c["giver"])


func _make_commission(day: int) -> Dictionary:
	var cfg: Dictionary = DataDB.village["commissions"]
	var options: Array = DataDB.recipes.keys().filter(func(id):
		return GameState.is_recipe_unlocked(id) and GameState.station_level(DataDB.recipes[id]["station"]) > 0)
	if options.is_empty():
		return {}
	# Half the time, ask for something that counters an upcoming threat.
	var reason := ""
	var upcoming := events.filter(func(e): return int(e["day"]) >= day and int(e["day"]) <= day + 3)
	if not upcoming.is_empty() and randf() < 0.5:
		var ev: Dictionary = upcoming.pick_random()
		var weak: Array = DataDB.enemies[ev["enemy"]]["weak"]
		var counters := options.filter(func(id):
			for t in DataDB.recipes[id]["tags"]:
				if t in weak:
					return true
			return false)
		if not counters.is_empty():
			options = counters
			reason = "for the fight against the %s" % DataDB.enemies[ev["enemy"]]["name"]
	var recipe: String = options.pick_random()
	var quality := 1 if randf() < 0.6 else 2
	var value := int(DataDB.recipes[recipe]["value"]) * float(DataDB.QUALITIES[quality]["mult"])
	var c := {
		"id": next_commission_id, "giver": cfg["givers"].pick_random(), "recipe": recipe,
		"quality": quality, "gold": int(value * float(cfg["gold_mult"])),
		"renown": randi_range(int(cfg["renown"][0]), int(cfg["renown"][1])),
		"due": day + randi_range(int(cfg["due_days"][0]), int(cfg["due_days"][1])),
		"reason": reason,
	}
	next_commission_id += 1
	return c


## Items on your shelf that satisfy a commission.
func matching_items(c: Dictionary) -> Array:
	return GameState.items.filter(func(it):
		return it["recipe"] == c["recipe"] and int(it["quality"]) >= int(c["quality"]))


func fulfil(c: Dictionary, item: Dictionary) -> bool:
	if not c in commissions or not item in matching_items(c):
		return false
	GameState.remove_item(int(item["uid"]))
	GameState.add_gold(int(c["gold"]))
	GameState.add_renown(int(c["renown"]))
	commissions.erase(c)
	EventBus.notify.emit("Commission complete! +%dg, +%d renown." % [int(c["gold"]), int(c["renown"])])
	return true


# --- Merchant, tavern, gathering ------------------------------------------------

func merchant_here(day: int) -> bool:
	return day % int(DataDB.village["merchant"]["every_days"]) == 0


func next_merchant_day(day: int) -> int:
	var every := int(DataDB.village["merchant"]["every_days"])
	return day + (every - day % every) % every


func _stock_merchant() -> void:
	var cfg: Dictionary = DataDB.village["merchant"]
	var rare: Array = DataDB.materials.keys().filter(func(m): return not DataDB.materials[m]["buyable"])
	rare.shuffle()
	for i in randi_range(int(cfg["stock_kinds"][0]), int(cfg["stock_kinds"][1])):
		if i < rare.size():
			merchant_stock[rare[i]] = randi_range(int(cfg["stock_count"][0]), int(cfg["stock_count"][1]))


func merchant_price(material: String) -> int:
	return int(ceil(int(DataDB.materials[material]["price"]) * float(DataDB.village["merchant"]["price_mult"])))


func merchant_buy(material: String) -> bool:
	if int(merchant_stock.get(material, 0)) <= 0 or not GameState.spend_gold(merchant_price(material)):
		return false
	merchant_stock[material] = int(merchant_stock[material]) - 1
	GameState.add_material(material, 1)
	return true


func merchant_offer(item: Dictionary) -> int:
	return maxi(1, int(GameState.item_value(item) * float(DataDB.village["merchant"]["buy_rate"])))


## Buy a round at the tavern: rumors extend the forecast today, and the
## adventurers might toast your name. Returns false if already done today.
func buy_round() -> bool:
	if rumor_day == GameState.day or not GameState.spend_gold(int(DataDB.village["tavern"]["round_cost"])):
		return false
	rumor_day = GameState.day
	if randf() < float(DataDB.village["tavern"]["renown_chance"]):
		GameState.add_renown(1)
		EventBus.notify.emit("The adventurers raise their mugs to you! +1 renown")
	return true


func can_gather(spot: String) -> bool:
	return int(gathered.get(spot, 0)) != GameState.day


## Gather at a spot. Costs game time. Returns a description of the haul.
func gather(spot: String) -> String:
	if not can_gather(spot):
		return ""
	var g: Dictionary = DataDB.village["gathering"][spot]
	gathered[spot] = GameState.day
	var got: PackedStringArray = []
	for m in g["yield"]:
		var n := randi_range(int(g["yield"][m][0]), int(g["yield"][m][1]))
		GameState.add_material(m, n)
		got.append("%dx %s" % [n, DataDB.material_name(m)])
	for m in g["bonus"]:
		if randf() < float(g["bonus"][m]):
			GameState.add_material(m, 1)
			got.append("1x %s (lucky!)" % DataDB.material_name(m))
	TimeManager.advance(int(g["minutes"]))
	return ", ".join(got)


# --- Save / load -------------------------------------------------------------

func to_dict() -> Dictionary:
	return { "events": events, "commissions": commissions, "next_commission_id": next_commission_id,
		"rumor_day": rumor_day, "gathered": gathered }


func from_dict(d: Dictionary) -> void:
	reset()
	for e in d.get("events", []):
		var ev: Dictionary = e.duplicate(true)
		ev["day"] = int(ev["day"])
		ev["bounty"] = int(ev["bounty"])
		events.append(ev)
	for c in d.get("commissions", []):
		var cc: Dictionary = c.duplicate(true)
		for k in ["id", "quality", "gold", "renown", "due"]:
			cc[k] = int(cc[k])
		commissions.append(cc)
	next_commission_id = int(d.get("next_commission_id", 1))
	rumor_day = int(d.get("rumor_day", 0))
	for k in d.get("gathered", {}):
		gathered[k] = int(d["gathered"][k])
