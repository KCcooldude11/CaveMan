extends Node
## The adventurers of the village: who they are, what gear they carry, who
## visits your shop today, and what happens to them in the dungeons overnight.
##
## Adventurers are plain dictionaries:
## { id, name, cls, level, xp, gold, haggle, alive, gear: {slot: gear|null},
##   loot: {material: count}, runs, last_result }
## A gear entry is a snapshot: { name, slot, power, tags, player_made }

const FIRST_NAMES := ["Bram", "Elsa", "Torvin", "Mira", "Kael", "Sorrel", "Dunstan", "Ysolde",
	"Garrick", "Lysa", "Fenn", "Odessa", "Rurik", "Tamsin", "Corwin", "Nell", "Haldor", "Isra",
	"Wren", "Brigid", "Osric", "Talia", "Edric", "Maeve"]
const EPITHETS := ["the Bold", "the Quick", "Ironjaw", "the Lucky", "Ashborn", "the Quiet",
	"Stormeye", "the Green", "Half-Elf", "Oakheart", "the Wanderer", "Two-Coins"]
const STARTER_GEAR := {
	"weapon": { "name": "Rusty Blade", "slot": "weapon", "power": 2, "tags": [], "player_made": false },
	"armor": null,
	"trinket": null,
}
const MAX_ALIVE := 24

var roster: Array = []
var next_id: int = 1
## Today's visits: [{ "time": minutes, "id": adventurer id }], sorted by time.
var schedule: Array = []


func _ready() -> void:
	EventBus.time_changed.connect(_on_time_changed)


func reset() -> void:
	roster = []
	next_id = 1
	schedule = []


# --- Roster ------------------------------------------------------------------

func get_adv(id: int) -> Dictionary:
	for a in roster:
		if int(a["id"]) == id:
			return a
	return {}


func alive() -> Array:
	return roster.filter(func(a): return a["alive"])


func recruit(level: int = 1) -> Dictionary:
	var cls: String = DataDB.classes.keys().pick_random()
	var adv := {
		"id": next_id,
		"name": "%s %s" % [FIRST_NAMES.pick_random(), EPITHETS.pick_random()],
		"cls": cls,
		"level": level,
		"xp": 0,
		"gold": 40 + level * 30 + randi_range(0, 30),
		"haggle": randf_range(0.9, 1.25),  # how generous they are with coin
		"alive": true,
		"gear": STARTER_GEAR.duplicate(true),
		"loot": {},
		"runs": 0,
		"last_result": "Fresh in town.",
	}
	next_id += 1
	roster.append(adv)
	return adv


func class_name_of(adv: Dictionary) -> String:
	return DataDB.classes[adv["cls"]]["name"]


func title(adv: Dictionary) -> String:
	return "%s (Lv %d %s)" % [adv["name"], int(adv["level"]), class_name_of(adv)]


# --- Power & preferences ----------------------------------------------------

func likes(adv: Dictionary, tags: Array) -> bool:
	for t in tags:
		if t in DataDB.classes[adv["cls"]]["likes"]:
			return true
	return false


## How well gear with these tags does against an enemy type:
## 1.3 if it exploits a weakness, 0.7 for a weapon the enemy resists.
static func counter_mult(tags: Array, slot: String, enemy: String) -> float:
	if enemy == "":
		return 1.0
	var e: Dictionary = DataDB.enemies[enemy]
	for t in tags:
		if t in e["weak"]:
			return 1.3
	if slot == "weapon":
		for t in tags:
			if t in e["resist"]:
				return 0.7
	return 1.0


## Effective power of a gear piece for this adventurer (class affinity bonus,
## plus counters if you pass the enemy they'll be fighting).
func gear_power_for(adv: Dictionary, power: int, tags: Array, slot := "", enemy := "") -> float:
	return power * (1.25 if likes(adv, tags) else 1.0) * counter_mult(tags, slot, enemy)


func power(adv: Dictionary, enemy := "") -> float:
	var p := 2.0 + int(adv["level"]) * 2.5
	for slot in DataDB.SLOTS:
		var g = adv["gear"][slot]
		if g != null:
			p += gear_power_for(adv, int(g["power"]), g["tags"], slot, enemy)
	return p


## The enemy this adventurer plans to fight tonight ("" if no plan yet).
func planned_enemy(adv: Dictionary) -> String:
	if adv.get("plan", "") == "":
		return ""
	return Village.conditions(adv["plan"], GameState.day)["enemy"]


## Which slot this adventurer most wants to upgrade and roughly what they'll spend.
func wants(adv: Dictionary) -> Dictionary:
	var best_slot := "weapon"
	var lowest := INF
	for slot in DataDB.SLOTS:
		var g = adv["gear"][slot]
		var p: float = 0.0 if g == null else float(g["power"])
		if p < lowest:
			lowest = p
			best_slot = slot
	return { "slot": best_slot, "budget": int(int(adv["gold"]) * 0.8), "enemy": planned_enemy(adv) }


## Would they buy `item` at `price`? Returns { accepted: bool, reason: String }.
func evaluate_offer(adv: Dictionary, item: Dictionary, price: int) -> Dictionary:
	var slot := GameState.item_slot(item)
	var r: Dictionary = DataDB.recipes[item["recipe"]]
	var enemy := planned_enemy(adv)
	var new_p := gear_power_for(adv, GameState.item_power(item), r["tags"], slot, enemy)
	var cur = adv["gear"][slot]
	var cur_p := 0.0 if cur == null else gear_power_for(adv, int(cur["power"]), cur["tags"], slot, enemy)
	if new_p <= cur_p:
		return { "accepted": false, "reason": "That's no better than what I've got.", "patience": 0 }
	if price > int(adv["gold"]):
		return { "accepted": false, "reason": "I only have %dg..." % int(adv["gold"]), "patience": 1 }
	var willing := max_price(adv, item)
	if price <= willing:
		return { "accepted": true, "reason": "A fine deal!", "patience": 0 }
	if price <= willing * 1.2:
		return { "accepted": false, "reason": "Hmm, a bit pricey for me.", "patience": 1 }
	return { "accepted": false, "reason": "Outrageous! Do I look like a noble?", "patience": 2 }


## The most this adventurer is willing to pay (hidden from the player; the UI
## only shows the item's "fair value").
func max_price(adv: Dictionary, item: Dictionary) -> int:
	var r: Dictionary = DataDB.recipes[item["recipe"]]
	var m: float = adv["haggle"]
	if likes(adv, r["tags"]):
		m += 0.25
	if wants(adv)["slot"] == r["slot"]:
		m += 0.1
	if counter_mult(r["tags"], r["slot"], planned_enemy(adv)) > 1.0:
		m += 0.2  # exactly what they need for tonight
	return min(int(adv["gold"]), int(GameState.item_value(item) * m))


func sell_item(adv: Dictionary, item: Dictionary, price: int) -> void:
	var r: Dictionary = DataDB.recipes[item["recipe"]]
	adv["gear"][r["slot"]] = {
		"name": GameState.item_name(item), "slot": r["slot"],
		"power": GameState.item_power(item), "tags": r["tags"], "player_made": true,
	}
	adv["gold"] = int(adv["gold"]) - price
	GameState.remove_item(int(item["uid"]))
	GameState.add_gold(price)
	GameState.stats["sold"] += 1


func loot_price(adv: Dictionary) -> int:
	var total := 0
	for m in adv["loot"]:
		total += int(DataDB.materials[m]["price"]) * int(adv["loot"][m])
	return int(total * 0.8)


func buy_loot(adv: Dictionary) -> bool:
	var price := loot_price(adv)
	if price <= 0 or not GameState.spend_gold(price):
		return false
	for m in adv["loot"]:
		GameState.add_material(m, int(adv["loot"][m]))
	adv["gold"] = int(adv["gold"]) + price
	adv["loot"] = {}
	return true


# --- Daily visits ----------------------------------------------------------

## Decide who comes to the shop today and when.
func plan_day() -> void:
	schedule = []
	var tier: Dictionary = DataDB.tier_for_renown(GameState.renown)
	var count: int = int(tier["visitors"]) + GameState.upgrade_level("signboard")
	# Grow the roster as your fame spreads.
	var target_roster: int = min(MAX_ALIVE, count + 2 + GameState.day / 2)
	while alive().size() < target_roster:
		recruit(randi_range(1, int(tier["max_level"])))
	# Returning customers with coin or loot come first, then a random mix.
	var scores := {}
	for a in alive():
		scores[int(a["id"])] = _visit_score(a)
	var pool := alive()
	pool.sort_custom(func(a, b): return scores[int(a["id"])] > scores[int(b["id"])])
	var visitors := pool.slice(0, count)
	for a in alive():
		a["plan"] = choose_dungeon(a)["id"]
	var span := (TimeManager.SHOP_CLOSE - 60) - TimeManager.SHOP_OPEN
	for i in visitors.size():
		var t := TimeManager.SHOP_OPEN + int(span * (i + randf_range(0.1, 0.9)) / visitors.size())
		schedule.append({ "time": t, "id": int(visitors[i]["id"]) })


func _visit_score(adv: Dictionary) -> float:
	var s := randf() * 2.0
	if not adv["loot"].is_empty():
		s += 2.0
	if adv["gear"]["weapon"] == null or adv["gear"]["armor"] == null:
		s += 1.0
	if int(adv["gold"]) >= 60:
		s += 1.0
	return s


func _on_time_changed(minutes: int) -> void:
	while not schedule.is_empty() and minutes >= int(schedule[0]["time"]):
		var visit: Dictionary = schedule.pop_front()
		var adv := get_adv(int(visit["id"]))
		if not adv.is_empty() and adv["alive"] and TimeManager.is_shop_open():
			EventBus.adventurer_arrived.emit(adv)


# --- Overnight dungeon runs ------------------------------------------------

## Chance to clear a dungeon tonight, given who's living in it.
func success_chance(adv: Dictionary, dungeon: Dictionary) -> float:
	var cond := Village.conditions(dungeon["id"], GameState.day)
	var ratio := power(adv, cond["enemy"]) / float(dungeon["difficulty"])
	return clampf(ratio - 0.25, 0.05, 0.95)


## Heroes pick the hardest dungeon they feel good about. Bounties make them
## braver.
func choose_dungeon(adv: Dictionary) -> Dictionary:
	var boldness := randf_range(0.45, 0.75)
	var pick: Dictionary = DataDB.dungeons[0]
	for d in DataDB.dungeons:
		var bounty := int(Village.conditions(d["id"], GameState.day)["bounty"])
		if success_chance(adv, d) >= boldness - (0.15 if bounty > 0 else 0.0):
			pick = d
	return pick


## Fraction of a dungeon's renown you get per victory (scaled by how much of
## the winner's gear you made). Tune this to speed up / slow down progression.
const RENOWN_PER_WIN := 0.045
## Bonus the first time anyone wearing your gear clears each dungeon.
const FIRST_CLEAR_BONUS := 5


## Every living adventurer delves overnight. Returns report lines and the
## renown you earned from adventurers using your gear.
func run_night() -> Dictionary:
	var lines: Array = []
	var renown_gain := 0.0
	for adv in alive():
		var res := _run(adv)
		lines.append(res["text"])
		renown_gain += float(res["renown"])
	return { "lines": lines, "renown": int(round(renown_gain)) }


func _player_share(adv: Dictionary) -> float:
	var total := 0.0
	var mine := 0.0
	for slot in DataDB.SLOTS:
		var g = adv["gear"][slot]
		if g != null:
			total += float(g["power"])
			if g["player_made"]:
				mine += float(g["power"])
	return 0.0 if total == 0.0 else mine / total


func _run(adv: Dictionary) -> Dictionary:
	var d := DataDB.dungeon(adv.get("plan", ""))
	if d.is_empty():
		d = choose_dungeon(adv)
	adv["plan"] = ""
	var cond := Village.conditions(d["id"], GameState.day)
	var enemy_name: String = DataDB.enemies[cond["enemy"]]["name"]
	var chance := success_chance(adv, d)
	var share := _player_share(adv)
	var who := "%s (Lv %d %s)" % [adv["name"], int(adv["level"]), class_name_of(adv)]
	var renown := 0.0
	var text := ""
	adv["runs"] = int(adv["runs"]) + 1

	if randf() < chance:
		var gold := randi_range(int(d["gold"][0]), int(d["gold"][1])) + int(cond["bounty"])
		adv["gold"] = int(adv["gold"]) + gold
		adv["xp"] = int(adv["xp"]) + int(d["xp"])
		var leveled := false
		while int(adv["xp"]) >= int(adv["level"]) * 10:
			adv["xp"] = int(adv["xp"]) - int(adv["level"]) * 10
			adv["level"] = int(adv["level"]) + 1
			leveled = true
		for m in cond["loot"]:
			var n := randi_range(int(cond["loot"][m][0]), int(cond["loot"][m][1]))
			if n > 0:
				adv["loot"][m] = int(adv["loot"].get(m, 0)) + n
		text = "[color=#8fd18f]%s beat the %s in %s[/color] (+%dg%s)" % [
			who, enemy_name, d["name"], gold, ", bounty!" if int(cond["bounty"]) > 0 else ""]
		var counter := _best_counter(adv, cond["enemy"])
		if counter != "":
			text += " Their %s was deadly against them!" % counter
		if leveled:
			text += " and reached level %d!" % int(adv["level"])
		if share > 0.0:
			renown = float(d["renown"]) * share * RENOWN_PER_WIN
			if counter != "" and _is_player_made(adv, counter):
				renown *= 1.5  # word spreads that you knew exactly what they needed
			text += " [color=#ffc94a]Wearing your gear![/color]"
			if not d["id"] in GameState.first_clears:
				GameState.first_clears.append(d["id"])
				renown += FIRST_CLEAR_BONUS
				text += " [color=#ffc94a][b]First clear of %s with your gear! +%d renown[/b][/color]" % [d["name"], FIRST_CLEAR_BONUS]
		adv["last_result"] = "Cleared %s" % d["name"]
	else:
		var death_chance := 0.05 + 0.3 * (1.0 - chance)
		if randf() < death_chance:
			adv["alive"] = false
			text = "[color=#e06c6c]%s fell to the %s in %s.[/color]" % [who, enemy_name, d["name"]]
			if share > 0.0:
				renown = -1.0
				text += " Whispers say your gear failed them."
			adv["last_result"] = "Died in %s" % d["name"]
			return { "text": text, "renown": renown }
		text = "[color=#e0b06c]%s retreated from the %s in %s, battered.[/color]" % [who, enemy_name, d["name"]]
		adv["last_result"] = "Retreated from %s" % d["name"]

	# Gear wears out, which keeps them coming back to you.
	var break_chance := 0.08 if adv["last_result"].begins_with("Cleared") else 0.25
	for slot in DataDB.SLOTS:
		var g = adv["gear"][slot]
		if g != null and randf() < break_chance:
			text += " Their %s broke." % g["name"]
			adv["gear"][slot] = null
	return { "text": text, "renown": renown }


## Name of the gear piece that exploits this enemy's weakness, or "".
func _best_counter(adv: Dictionary, enemy: String) -> String:
	for slot in DataDB.SLOTS:
		var g = adv["gear"][slot]
		if g != null and counter_mult(g["tags"], slot, enemy) > 1.0:
			return g["name"]
	return ""


func _is_player_made(adv: Dictionary, gear_name: String) -> bool:
	for slot in DataDB.SLOTS:
		var g = adv["gear"][slot]
		if g != null and g["name"] == gear_name:
			return g["player_made"]
	return false


# --- Save / load -------------------------------------------------------------

func to_dict() -> Dictionary:
	return { "roster": roster, "next_id": next_id }


func from_dict(d: Dictionary) -> void:
	reset()
	next_id = int(d.get("next_id", 1))
	for a in d.get("roster", []):
		var adv: Dictionary = a.duplicate(true)
		for k in ["id", "level", "xp", "gold", "runs"]:
			adv[k] = int(adv[k])
		for slot in DataDB.SLOTS:
			var g = adv["gear"].get(slot)
			if g != null:
				g["power"] = int(g["power"])
			adv["gear"][slot] = g
		for m in adv["loot"]:
			adv["loot"][m] = int(adv["loot"][m])
		roster.append(adv)
