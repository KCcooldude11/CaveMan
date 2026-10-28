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
var merchant_purse := 0        # gold Zara can still spend on your gear today
var prosperity := 30           # 0-100: more heroes, better trade
var safety := 50               # 0-100: caravans, raids, shortages
var projects: Dictionary = {}  # project id -> { gold: paid, materials: {m: given}, done: bool }
var caravans: Array = []       # [{ amount, return_day }]
var flags: Dictionary = {}     # temporary village states: festival_day, vein_until, vault_until, ...
var gathers_total := 0
var trade_today := 0           # gold heroes spent in the village tonight


func _ready() -> void:
	reset()


func reset() -> void:
	events = []
	commissions = []
	next_commission_id = 1
	rumor_day = 0
	gathered = {}
	merchant_stock = {}
	merchant_purse = 0
	prosperity = int(DataDB.world["village"]["prosperity"])
	safety = int(DataDB.world["village"]["safety"])
	projects = {}
	for id in DataDB.world["projects"]:
		projects[id] = { "gold": 0, "materials": {}, "done": false }
	caravans = []
	flags = {}
	gathers_total = 0


## Called every morning before adventurers plan their day.
func start_day(day: int) -> void:
	events = events.filter(func(e): return int(e["day"]) >= day)
	var cfg: Dictionary = DataDB.village["forecast"]
	# Rumors firm up as the day approaches - and some turn out wrong.
	for e in events.duplicate():
		if int(e["day"]) <= day + 1 and not e.get("confirmed", false):
			if int(e["day"]) > day and randf() < float(DataDB.world["forecast_rumor_reroll"]):
				var idx := events.find(e)
				var fresh := _make_event(int(e["day"]), DataDB.dungeon(e["dungeon"]))
				fresh["changed"] = true
				events[idx] = fresh
			else:
				e["confirmed"] = true
	for d in range(day, day + int(cfg["rumor_days_ahead"]) + 1):
		if events_on(d).is_empty():
			_generate_events(d)
	for e in events:
		if int(e["day"]) <= day + 1:
			e["confirmed"] = true
	_update_commissions(day)
	merchant_stock = {}
	merchant_purse = 0
	if merchant_here(day):
		_stock_merchant()
		merchant_purse = int(DataDB.world["market"]["merchant_purse"]) * (3 if project_done("market") else 2) / 2


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
	var extra := 1 if project_done("watchtower") else 0
	return extra + (int(cfg["rumor_days_ahead"]) if rumor_day == GameState.day else int(cfg["days_ahead"]))


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
	var enemy: String = Dungeons.get_state(d["id"])["controller"]
	var extra := {}
	if kind == "invasion":
		var others: Array = DataDB.enemies.keys().filter(func(e): return e != Dungeons.get_state(d["id"])["controller"])
		enemy = others.pick_random()
	elif kind == "vein":
		var mat: String = cfg["vein_materials"].pick_random()
		extra[mat] = [1, 3]
	var text: String = k["text"].format({
		"enemy": DataDB.enemies[enemy]["name"], "dungeon": d["name"],
		"extra": DataDB.format_loot(extra)})
	var mod := ""
	for m in DataDB.world["modifiers"]:
		if randf() < float(DataDB.world["modifiers"][m]["chance"]) * 0.6:
			mod = m
			break
	return {
		"day": day, "dungeon": d["id"], "kind": kind, "enemy": enemy,
		"loot_mult": float(k["loot_mult"]), "extra": extra, "modifier": mod,
		"bounty": randi_range(int(k["bounty"][0]), int(k["bounty"][1])), "text": text,
		"confirmed": false,
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


## What a dungeon looks like on a given day (see Dungeons.conditions).
func conditions(dungeon_id: String, day: int) -> Dictionary:
	return Dungeons.conditions(dungeon_id, day)


# --- Commissions ---------------------------------------------------------------
## A commission: { id, giver, recipe ("" = any), slot, tag, affix ("" / "any" /
## affix id), quality, gold, renown, due, reason, special ("", "envoy",
## "contest", "hero"), hero (id), fail_renown, rival_power }

func _update_commissions(day: int) -> void:
	for c in commissions.duplicate():
		if int(c["due"]) < day:
			commissions.erase(c)
			_commission_failed(c)
	var cfg: Dictionary = DataDB.village["commissions"]
	var ordinary := commissions.filter(func(c): return str(c.get("special", "")) == "").size()
	if ordinary < int(cfg["max_active"]) and (ordinary == 0 or randf() < float(cfg["new_chance"])):
		var c := _make_commission(day)
		if not c.is_empty():
			commissions.append(c)
			EventBus.notify.emit("New commission on the notice board from %s." % c["giver"])


func _commission_failed(c: Dictionary) -> void:
	var pen := int(c.get("fail_renown", 0))
	if pen != 0:
		GameState.add_renown(pen)
	match str(c.get("special", "")):
		"hero":
			var adv := AdventurerManager.get_adv(int(c.get("hero", 0)))
			if not adv.is_empty():
				AdventurerManager.change_loyalty(adv, -12)
				AdventurerManager.remember(adv, "Waited on an order from your forge that never came.")
		"contest":
			Market.rival_rep += 5.0
			Chronicle.add("You never answered %s's challenge. The village took note." % DataDB.world["rival"]["name"], "market")
		"envoy":
			Chronicle.add("You failed the royal envoy. Word travels to the capital.", "village")
	EventBus.notify.emit("%s's commission expired.%s" % [c["giver"], " (%d renown)" % pen if pen != 0 else ""])


func add_commission(c: Dictionary) -> Dictionary:
	var base := { "id": next_commission_id, "recipe": "", "slot": "", "tag": "", "affix": "",
		"quality": 1, "gold": 0, "renown": 0, "due": GameState.day + 3, "reason": "",
		"special": "", "hero": 0, "fail_renown": 0, "rival_power": 0 }
	base.merge(c, true)
	next_commission_id += 1
	commissions.append(base)
	return base


func _make_commission(day: int) -> Dictionary:
	var cfg: Dictionary = DataDB.village["commissions"]
	var options: Array = DataDB.recipes.keys().filter(func(id):
		return GameState.is_recipe_unlocked(id) and GameState.station_level(DataDB.recipes[id]["station"]) > 0)
	if options.is_empty():
		return {}
	# Half the time, ask for something that counters an upcoming threat.
	var reason := ""
	var threat_tag := ""
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
			threat_tag = weak.filter(func(t): return t != "fireward").pick_random() if weak.size() > 0 else ""
			reason = "for the fight against the %s" % DataDB.enemies[ev["enemy"]]["name"]
	var recipe: String = options.pick_random()
	var quality := 1 if randf() < 0.6 else 2
	var value := int(DataDB.recipes[recipe]["value"]) * float(DataDB.QUALITIES[quality]["mult"])
	var c := {
		"giver": cfg["givers"].pick_random(), "recipe": recipe, "quality": quality,
		"gold": int(value * float(cfg["gold_mult"])),
		"renown": randi_range(int(cfg["renown"][0]), int(cfg["renown"][1])),
		"due": day + randi_range(int(cfg["due_days"][0]), int(cfg["due_days"][1])),
		"reason": reason,
	}
	var roll := randf()
	if roll < 0.25 and threat_tag != "":
		# "Anything with silver in it" - let the player choose how.
		c["recipe"] = ""
		c["slot"] = DataDB.recipes[recipe]["slot"]
		c["tag"] = threat_tag
		c["gold"] = int(c["gold"] * 1.1)
	elif roll < 0.45:
		# Something personal and unusual: a specific infused item.
		var known: Array = GameState.discovered_affixes.filter(func(a): return DataDB.affixes[a].has("infusion") and not DataDB.affixes[a].get("always_legendary", false))
		var aff: String = known.pick_random() if not known.is_empty() else "any"
		c["affix"] = aff
		c["gold"] = int(c["gold"] * 1.8)
		c["renown"] = int(c["renown"]) + 1
		c["due"] = int(c["due"]) + 1
	return add_commission(c)


func commission_text(c: Dictionary) -> String:
	var q: Dictionary = DataDB.QUALITIES[int(c["quality"])]
	var what := ""
	if str(c.get("recipe", "")) != "":
		what = DataDB.recipes[c["recipe"]]["name"]
	else:
		what = "%s%s" % ["%s " % c["tag"] if str(c.get("tag", "")) != "" else "", c.get("slot", "item") if str(c.get("slot", "")) != "" else "item"]
	var aff := ""
	match str(c.get("affix", "")):
		"": aff = ""
		"any": aff = "infused "
		_: aff = "%s " % DataDB.affixes[c["affix"]]["name"]
	return "a [color=#%s]%s[/color]-or-better %s%s" % [q["color"].to_html(false), q["name"], aff, what]


## Items on your shelf that satisfy a commission.
func matching_items(c: Dictionary) -> Array:
	return GameState.items.filter(func(it): return item_matches(c, it))


func item_matches(c: Dictionary, it: Dictionary) -> bool:
	if int(it["quality"]) < int(c["quality"]):
		return false
	if str(c.get("recipe", "")) != "" and it["recipe"] != c["recipe"]:
		return false
	if str(c.get("slot", "")) != "" and GameState.item_slot(it) != c["slot"]:
		return false
	if str(c.get("tag", "")) != "" and not c["tag"] in GameState.item_tags(it):
		return false
	var aff := str(c.get("affix", ""))
	var affixes: Array = it.get("affixes", [])
	if aff == "any":
		return affixes.any(func(a): return DataDB.affixes[a].has("infusion"))
	if aff != "" and not aff in affixes:
		return false
	return true


func fulfil(c: Dictionary, item: Dictionary) -> bool:
	if not c in commissions or not item_matches(c, item) or GameState.find_item(int(item["uid"])).is_empty():
		return false
	commissions.erase(c)
	match str(c.get("special", "")):
		"contest":
			var mine := GameState.item_power(item)
			GameState.remove_item(int(item["uid"]))
			var hc: Dictionary = DataDB.happenings["rival_challenge"]
			if mine >= int(c["rival_power"]):
				GameState.add_renown(int(hc["win_renown"]))
				GameState.add_gold(int(c["gold"]))
				Market.rival_rep *= 0.6
				Market.contest_wins += 1
				EventBus.celebrate.emit("You won the contest!", "%s (power %d) beat %s's entry (power %d)" % [GameState.item_name(item), mine, DataDB.world["rival"]["name"], int(c["rival_power"])])
				Chronicle.add("You beat %s in a crafting contest with your %s." % [DataDB.world["rival"]["name"], GameState.item_name(item)], "milestone")
			else:
				GameState.add_renown(int(hc["lose_renown"]))
				Market.rival_rep += 5.0
				EventBus.notify.emit("%s's entry (power %d) beat yours (power %d)." % [DataDB.world["rival"]["name"], int(c["rival_power"]), mine])
				Chronicle.add("%s beat you in a crafting contest." % DataDB.world["rival"]["name"], "market")
			return true
		"hero":
			var adv := AdventurerManager.get_adv(int(c.get("hero", 0)))
			if adv.is_empty() or not adv["alive"]:
				commissions.append(c)
				return false
			AdventurerManager.sell_item(adv, item, 0)
			AdventurerManager.change_loyalty(adv, 15)
			AdventurerManager.remember(adv, "Received the %s I ordered from your forge." % GameState.item_name(item))
			GameState.add_gold(int(c["gold"]))
			GameState.add_renown(int(c["renown"]))
			EventBus.notify.emit("Delivered to %s! +%dg, +%d renown." % [adv["name"], int(c["gold"]), int(c["renown"])])
			return true
	GameState.remove_item(int(item["uid"]))
	GameState.add_gold(int(c["gold"]))
	GameState.add_renown(int(c["renown"]))
	if str(c.get("special", "")) == "envoy":
		EventBus.celebrate.emit("The Crown is pleased!", "Your %s leaves for the capital" % GameState.item_name(item))
		Chronicle.add("You forged %s for the royal envoy." % GameState.item_name(item), "milestone")
		change_prosperity(5)
	EventBus.notify.emit("Commission complete! +%dg, +%d renown." % [int(c["gold"]), int(c["renown"])])
	return true


# --- Merchant, tavern, gathering ------------------------------------------------

func merchant_every() -> int:
	return 2 if project_done("market") else int(DataDB.village["merchant"]["every_days"])


func merchant_here(day: int) -> bool:
	return day % merchant_every() == 0


func next_merchant_day(day: int) -> int:
	var every := merchant_every()
	return day + (every - day % every) % every


func _stock_merchant() -> void:
	var cfg: Dictionary = DataDB.village["merchant"]
	var rare: Array = DataDB.materials.keys().filter(func(m): return not DataDB.materials[m]["buyable"])
	rare.shuffle()
	for i in randi_range(int(cfg["stock_kinds"][0]), int(cfg["stock_kinds"][1])):
		if i < rare.size():
			merchant_stock[rare[i]] = randi_range(int(cfg["stock_count"][0]), int(cfg["stock_count"][1]))


func merchant_price(material: String) -> int:
	return int(ceil(Market.price(material) * float(DataDB.village["merchant"]["price_mult"])))


func merchant_buy(material: String) -> bool:
	if int(merchant_stock.get(material, 0)) <= 0 or not GameState.spend_gold(merchant_price(material)):
		return false
	merchant_stock[material] = int(merchant_stock[material]) - 1
	GameState.add_material(material, 1)
	merchant_purse += merchant_price(material) / 2  # she has more coin to buy your gear
	return true


## Zara pays well, but buyers saturate and her purse is limited per visit.
func merchant_offer(item: Dictionary) -> int:
	var v := GameState.item_value(item) * float(DataDB.village["merchant"]["buy_rate"]) * Market.saturation_mult(item["recipe"])
	return clampi(int(v), 1, maxi(1, merchant_purse))


func merchant_sell(item: Dictionary) -> bool:
	var offer := merchant_offer(item)
	if not merchant_here(GameState.day) or offer > merchant_purse or GameState.find_item(int(item["uid"])).is_empty():
		return false
	merchant_purse -= offer
	GameState.add_gold(offer)
	GameState.remove_item(int(item["uid"]))
	Market.on_item_dumped(item)
	return true


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
	gathers_total += 1
	for m in g["yield"]:
		var n := randi_range(int(g["yield"][m][0]), int(g["yield"][m][1]))
		if spot == "mine" and project_done("deepmine"):
			n += 1
		GameState.add_material(m, n)
		got.append("%dx %s" % [n, DataDB.material_name(m)])
	var bonus: Dictionary = g["bonus"].duplicate()
	if spot == "mine" and project_done("deepmine"):
		bonus["silver_ingot"] = 0.25
		bonus["mithril_ore"] = 0.1
	if spot == "mine" and int(flags.get("vein_until", 0)) >= GameState.day:
		bonus["mithril_ore"] = 1.0
	for m in bonus:
		if randf() < float(bonus[m]):
			GameState.add_material(m, 1)
			got.append("1x %s (lucky!)" % DataDB.material_name(m))
	TimeManager.advance(int(g["minutes"]))
	return ", ".join(got)


# --- Prosperity, projects, investments -------------------------------------------

## Hero spending in the village nudges prosperity up a little.
func add_trade(gold: int) -> void:
	trade_today += gold


func change_prosperity(amount: int) -> void:
	prosperity = clampi(prosperity + amount, 0, 100)


func change_safety(amount: int) -> void:
	safety = clampi(safety + amount, 0, 100)


func project_done(id: String) -> bool:
	return projects.has(id) and projects[id]["done"]


func project_available(id: String) -> bool:
	return not project_done(id) and prosperity >= int(DataDB.world["projects"][id]["prosperity"])


## What's still missing for a project: { gold: n, materials: {m: n} }.
func project_remaining(id: String) -> Dictionary:
	var p: Dictionary = DataDB.world["projects"][id]
	var st: Dictionary = projects[id]
	var mats := {}
	for m in p["materials"]:
		var left := int(p["materials"][m]) - int(st["materials"].get(m, 0))
		if left > 0:
			mats[m] = left
	return { "gold": maxi(0, int(p["gold"]) - int(st["gold"])), "materials": mats }


## Contribute whatever you can toward a project. Completes it when funded.
func contribute(id: String) -> String:
	if not project_available(id):
		return ""
	var rem := project_remaining(id)
	var st: Dictionary = projects[id]
	var gave: PackedStringArray = []
	var g := mini(GameState.gold, int(rem["gold"]))
	if g > 0 and GameState.spend_gold(g):
		st["gold"] = int(st["gold"]) + g
		gave.append("%dg" % g)
	for m in rem["materials"]:
		var n := mini(GameState.material_count(m), int(rem["materials"][m]))
		if n > 0:
			GameState.consume_materials({ m: n })
			st["materials"][m] = int(st["materials"].get(m, 0)) + n
			gave.append("%dx %s" % [n, DataDB.material_name(m)])
	rem = project_remaining(id)
	if int(rem["gold"]) == 0 and rem["materials"].is_empty():
		_complete_project(id)
	return ", ".join(gave)


func _complete_project(id: String) -> void:
	projects[id]["done"] = true
	var name: String = DataDB.world["projects"][id]["name"]
	change_prosperity(5)
	match id:
		"watchtower": change_safety(25)
		"market": change_prosperity(10)
	GameState.add_renown(3)
	EventBus.notify.emit("The %s is restored!" % name)
	EventBus.projects_changed.emit()
	Chronicle.add("The %s was restored, thanks to your work." % name, "village")


## Risky investment: send gold with a trade caravan, get back 0x-2.4x.
func invest_caravan(amount: int) -> bool:
	var c: Dictionary = DataDB.world["caravan"]
	if amount < int(c["min"]) or amount > int(c["max"]) or not caravans.is_empty() or not GameState.spend_gold(amount):
		return false
	caravans.append({ "amount": amount, "return_day": GameState.day + int(c["nights"]) })
	return true


func _resolve_caravans(day: int) -> Array:
	var lines: Array = []
	var c: Dictionary = DataDB.world["caravan"]
	for cv in caravans.duplicate():
		if int(cv["return_day"]) > day + 1:
			continue
		caravans.erase(cv)
		var lo := float(c["base_return"][0]) + safety * float(c["safety_weight"])
		var hi := float(c["base_return"][1]) + safety * float(c["safety_weight"])
		var roll := randf_range(lo, hi) if randf() > 0.15 * (1.0 - safety / 100.0) else 0.0
		var back := int(int(cv["amount"]) * roll)
		GameState.add_gold(back)
		if back == 0:
			lines.append("[color=#e06c6c]Bandits took your caravan. Your %dg is gone.[/color]" % int(cv["amount"]))
			Chronicle.add("Bandits robbed the caravan you invested in.", "market")
		else:
			lines.append("[color=#ffd27a]Your caravan returned: %dg invested, %dg back.[/color]" % [int(cv["amount"]), back])
			if back >= int(cv["amount"]) * 2:
				Chronicle.add("Your caravan came home laden with riches (%dg)." % back, "market")
	return lines


## Village-wide changes each night. Returns report lines.
func night_update(day: int) -> Array:
	var lines := _resolve_caravans(day)
	# Prosperity drifts toward what the village can sustain.
	var target := 25 + Dungeons.bosses_slain * 5 + projects.values().filter(func(p): return p["done"]).size() * 6
	target += mini(15, trade_today / 200)
	trade_today = 0
	if prosperity < target:
		change_prosperity(1)
	elif prosperity > target + 20:
		change_prosperity(-1)
	var high_threat := DataDB.dungeons.filter(func(d): return Dungeons.threat(d["id"]) >= 70).size()
	change_safety(-high_threat + (1 if high_threat == 0 else 0))
	return lines


func is_festival(day: int) -> bool:
	return int(flags.get("festival_day", 0)) == day


# --- Save / load -------------------------------------------------------------

func to_dict() -> Dictionary:
	return { "events": events, "commissions": commissions, "next_commission_id": next_commission_id,
		"rumor_day": rumor_day, "gathered": gathered, "prosperity": prosperity, "safety": safety,
		"projects": projects, "caravans": caravans, "flags": flags, "gathers_total": gathers_total,
		"merchant_stock": merchant_stock, "merchant_purse": merchant_purse }


func from_dict(d: Dictionary) -> void:
	reset()
	events = d.get("events", [])
	commissions = d.get("commissions", [])
	next_commission_id = int(d.get("next_commission_id", 1))
	rumor_day = int(d.get("rumor_day", 0))
	gathered = d.get("gathered", {})
	prosperity = int(d.get("prosperity", prosperity))
	safety = int(d.get("safety", safety))
	for id in d.get("projects", {}):
		if projects.has(id):
			projects[id].merge(d["projects"][id], true)
	caravans = d.get("caravans", [])
	flags = d.get("flags", {})
	gathers_total = int(d.get("gathers_total", 0))
	merchant_stock = d.get("merchant_stock", {})
	merchant_purse = int(d.get("merchant_purse", 0))
