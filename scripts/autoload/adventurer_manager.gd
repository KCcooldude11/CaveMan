extends Node
## The adventurers of the village: who they are, what they remember, what gear
## they carry, who visits your shop, and what happens to them in the dungeons.
##
## Heroes are plain dictionaries (they save straight to JSON):
## { id, name, cls, level, xp, gold, haggle, alive, gear: {slot: gear|null},
##   loot, runs, last_result, personality, loyalty, memories, title, kills,
##   wins, near_deaths, injured_until, expedition, plan, rival, served_day }
## Gear entries are snapshots (see GameState.item_to_gear).

const FIRST_NAMES := ["Bram", "Elsa", "Torvin", "Mira", "Kael", "Sorrel", "Dunstan", "Ysolde",
	"Garrick", "Lysa", "Fenn", "Odessa", "Rurik", "Tamsin", "Corwin", "Nell", "Haldor", "Isra",
	"Wren", "Brigid", "Osric", "Talia", "Edric", "Maeve", "Ansel", "Petra", "Jory", "Sable"]
const EPITHETS := ["the Bold", "the Quick", "Ironjaw", "the Lucky", "Ashborn", "the Quiet",
	"Stormeye", "the Green", "Half-Elf", "Oakheart", "the Wanderer", "Two-Coins", "Redcloak", "of Highmarch"]
const STARTER_GEAR := {
	"weapon": { "name": "Rusty Blade", "slot": "weapon", "recipe": "", "power": 2, "tags": [],
		"player_made": false, "affixes": [], "legend": "" },
	"armor": null,
	"trinket": null,
}
const MAX_ALIVE := 26
const MAX_MEMORIES := 8

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


# --- Roster & identity -----------------------------------------------------------

func get_adv(id: int) -> Dictionary:
	for a in roster:
		if int(a["id"]) == id:
			return a
	return {}


func alive() -> Array:
	return roster.filter(func(a): return a["alive"])


## Alive, not injured and not away on an expedition.
func available(adv: Dictionary) -> bool:
	return adv["alive"] and int(adv.get("injured_until", 0)) < GameState.day and adv.get("expedition", {}).is_empty()


func recruit(level: int = 1, opts := {}) -> Dictionary:
	var cls: String = opts.get("cls", DataDB.classes.keys().pick_random())
	var personality: String = opts.get("personality", DataDB.heroes["personalities"].keys().pick_random())
	var used: Array = roster.map(func(a): return a["name"])
	var hero_name: String = opts.get("name", "")
	for attempt in 30:
		if hero_name != "" and not hero_name in used:
			break
		hero_name = "%s %s" % [FIRST_NAMES.pick_random(), EPITHETS.pick_random()]
	var adv := {
		"id": next_id, "name": hero_name, "cls": cls, "level": level, "xp": 0,
		"gold": 40 + level * 30 + randi_range(0, 30),
		"haggle": randf_range(0.9, 1.2) + float(DataDB.heroes["personalities"][personality]["haggle"]),
		"alive": true, "gear": STARTER_GEAR.duplicate(true), "loot": {}, "runs": 0,
		"last_result": "Fresh in town.", "personality": personality, "loyalty": 0,
		"memories": [], "title": "", "kills": {}, "wins": 0, "near_deaths": 0,
		"injured_until": 0, "expedition": {}, "plan": "", "rival": 0, "served_day": 0,
		"legendary": opts.get("legendary", false), "patron_gift": false,
	}
	next_id += 1
	# Heroes of the same class and level tend to become rivals.
	for other in alive():
		if int(other["rival"]) == 0 and other["cls"] == cls and absi(int(other["level"]) - level) <= 1 and randf() < 0.35:
			adv["rival"] = int(other["id"])
			other["rival"] = int(adv["id"])
			remember(adv, "Sized up %s at the tavern. Rivals from the first drink." % other["name"])
			remember(other, "A new %s in town, %s, thinks they're better. We'll see." % [class_name_of(other), hero_name])
			break
	roster.append(adv)
	return adv


func class_name_of(adv: Dictionary) -> String:
	return DataDB.classes[adv["cls"]]["name"]


func personality_of(adv: Dictionary) -> Dictionary:
	return DataDB.heroes["personalities"][adv.get("personality", "steady")]


func full_name(adv: Dictionary) -> String:
	return adv["name"] if str(adv.get("title", "")) == "" else "%s, %s" % [adv["name"], adv["title"]]


func title(adv: Dictionary) -> String:
	return "%s (Lv %d %s)" % [full_name(adv), int(adv["level"]), class_name_of(adv)]


func remember(adv: Dictionary, text: String) -> void:
	adv["memories"].append("Day %d: %s" % [GameState.day, text])
	if adv["memories"].size() > MAX_MEMORIES:
		adv["memories"].pop_front()


func loyalty_label(adv: Dictionary) -> String:
	var l := int(adv.get("loyalty", 0))
	var cfg: Dictionary = DataDB.heroes["loyalty"]
	if l >= int(cfg["patron"]):
		return "[color=#ffc94a]Patron[/color]"
	if l >= int(cfg["regular"]):
		return "[color=#8fd18f]Regular[/color]"
	if l > 0:
		return "Acquainted"
	if l < 0:
		return "[color=#e06c6c]Sour[/color]"
	return "Stranger"


func change_loyalty(adv: Dictionary, amount: int) -> void:
	var cfg: Dictionary = DataDB.heroes["loyalty"]
	var before := int(adv.get("loyalty", 0))
	adv["loyalty"] = clampi(before + amount, -50, 100)
	if before < int(cfg["patron"]) and int(adv["loyalty"]) >= int(cfg["patron"]) and not adv.get("patron_gift", false):
		adv["patron_gift"] = true
		var rare: Array = DataDB.materials.keys().filter(func(m): return not DataDB.materials[m]["buyable"] and not DataDB.materials[m].get("trophy", false))
		var gift: String = rare.pick_random()
		GameState.add_material(gift, 2)
		remember(adv, "Became a patron of your forge.")
		Chronicle.add("%s became a patron of your forge and gifted you 2 %s." % [adv["name"], DataDB.material_name(gift)], "hero")
		EventBus.notify.emit("%s is now your patron! They gift you 2 %s." % [adv["name"], DataDB.material_name(gift)])


func likes(adv: Dictionary, tags: Array) -> bool:
	for t in tags:
		if t in DataDB.classes[adv["cls"]]["likes"]:
			return true
	return false


# --- Power, counters & affixes --------------------------------------------------

## How well gear does against an enemy (and tonight's dungeon modifier):
## 1.3 if it exploits a weakness, 0.7 for a weapon the enemy resists, times
## any modifier tag bonuses (e.g. Darkness favours fire).
static func counter_mult(tags: Array, slot: String, enemy: String, mod := {}) -> float:
	var m := 1.0
	if enemy != "":
		var e: Dictionary = DataDB.enemies[enemy]
		var weak := false
		for t in tags:
			if t in e["weak"]:
				weak = true
		if weak:
			m = 1.3
		elif slot == "weapon":
			for t in tags:
				if t in e["resist"]:
					m = 0.7
					break
	var mt: Dictionary = mod.get("tags", {})
	for t in tags:
		if mt.has(t):
			m *= float(mt[t])
	if slot == "armor":
		m *= float(mod.get("armor_mult", 1.0))
	return m


## Effective power of a gear piece for this adventurer.
func gear_power_for(adv: Dictionary, power: int, tags: Array, slot := "", enemy := "", mod := {}) -> float:
	return power * (1.25 if likes(adv, tags) else 1.0) * counter_mult(tags, slot, enemy, mod)


func power(adv: Dictionary, enemy := "", mod := {}) -> float:
	var p := 2.0 + int(adv["level"]) * 2.5
	for slot in DataDB.SLOTS:
		var g = adv["gear"][slot]
		if g != null:
			p += gear_power_for(adv, int(g["power"]), g["tags"], slot, enemy, mod)
	return p


## All affix ids on the hero's current gear.
func gear_affixes(adv: Dictionary) -> Array:
	var out: Array = []
	for slot in DataDB.SLOTS:
		var g = adv["gear"][slot]
		if g != null:
			out.append_array(g.get("affixes", []))
	return out


## The enemy this adventurer plans to fight tonight ("" if no plan yet).
func planned_enemy(adv: Dictionary) -> String:
	var plan: String = adv.get("plan", "")
	if plan == "":
		return ""
	return Dungeons.conditions(plan.trim_prefix("boss:"), GameState.day)["enemy"]


func planned_mod(adv: Dictionary) -> Dictionary:
	var plan: String = adv.get("plan", "")
	if plan == "" or plan.begins_with("boss:"):
		return {}
	return Dungeons.conditions(plan, GameState.day)["modifier"]


## Which slot this adventurer most wants to upgrade, budget, and tonight's foe.
func wants(adv: Dictionary) -> Dictionary:
	var best_slot := "weapon"
	var lowest := INF
	for slot in DataDB.SLOTS:
		var g = adv["gear"][slot]
		var p: float = 0.0 if g == null else float(g["power"])
		if slot == personality_of(adv).get("prefers_slot", "") or (slot == "armor" and int(adv.get("near_deaths", 0)) > 0 and adv.get("wants_armor", false)):
			p *= 0.6  # cautious / shaken heroes favour armor
		if p < lowest:
			lowest = p
			best_slot = slot
	return { "slot": best_slot, "budget": int(int(adv["gold"]) * 0.8), "enemy": planned_enemy(adv),
		"boss": str(adv.get("plan", "")).begins_with("boss:") }


## Why this item would (or wouldn't) appeal to this hero - for the UI.
func item_reasons(adv: Dictionary, item: Dictionary) -> Array:
	var reasons: Array = []
	var tags := GameState.item_tags(item)
	var slot := GameState.item_slot(item)
	var enemy := planned_enemy(adv)
	if likes(adv, tags):
		reasons.append("[color=#8fd18f]suits a %s[/color]" % class_name_of(adv))
	var cm := counter_mult(tags, slot, enemy, planned_mod(adv))
	if cm > 1.05:
		reasons.append("[color=#e06c6c]perfect for tonight[/color]")
	elif cm < 0.95:
		reasons.append("[color=#9a8f86]bad for tonight[/color]")
	var affixes: Array = item.get("affixes", [])
	if "cursed" in affixes:
		if personality_of(adv).get("hates_cursed", false):
			reasons.append("[color=#e06c6c]won't touch cursed gear[/color]")
		elif personality_of(adv).get("loves_cursed", false):
			reasons.append("[color=#c77dff]loves the curse[/color]")
	var dl := Market.demand_label(tags)
	if dl != "":
		reasons.append(dl)
	var cur = adv["gear"][slot]
	var new_p := gear_power_for(adv, GameState.item_power(item), tags, slot, enemy, planned_mod(adv))
	var cur_p := 0.0 if cur == null else gear_power_for(adv, int(cur["power"]), cur["tags"], slot, enemy, planned_mod(adv))
	var diff := int(round(new_p - cur_p))
	reasons.push_front("[color=%s]%+d vs their %s[/color]" % ["#8fd18f" if diff > 0 else "#e06c6c", diff, "nothing" if cur == null else cur["name"]])
	return reasons


## Would they buy `item` at `price`? Returns { accepted, reason, patience }.
func evaluate_offer(adv: Dictionary, item: Dictionary, price: int) -> Dictionary:
	var slot := GameState.item_slot(item)
	var tags := GameState.item_tags(item)
	var enemy := planned_enemy(adv)
	var mod := planned_mod(adv)
	if "cursed" in item.get("affixes", []) and personality_of(adv).get("hates_cursed", false):
		return { "accepted": false, "reason": "Cursed? Keep that thing away from me.", "patience": 1 }
	var new_p := gear_power_for(adv, GameState.item_power(item), tags, slot, enemy, mod)
	var cur = adv["gear"][slot]
	var cur_p := 0.0 if cur == null else gear_power_for(adv, int(cur["power"]), cur["tags"], slot, enemy, mod)
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


## The most this adventurer is willing to pay (hidden; the UI shows fair value).
func max_price(adv: Dictionary, item: Dictionary) -> int:
	var r: Dictionary = DataDB.recipes[item["recipe"]]
	var tags := GameState.item_tags(item)
	var m: float = adv["haggle"]
	if likes(adv, tags):
		m += 0.25
	if wants(adv)["slot"] == r["slot"]:
		m += 0.1
	if counter_mult(tags, r["slot"], planned_enemy(adv), planned_mod(adv)) > 1.05:
		m += 0.2  # exactly what they need for tonight
	if wants(adv)["boss"]:
		m += 0.15  # facing a boss: money is no object
	if "cursed" in item.get("affixes", []) and personality_of(adv).get("loves_cursed", false):
		m += 0.3
	if str(item.get("legend", "")) != "" and adv.get("personality", "") == "glory":
		m += 0.3
	m += 0.002 * int(adv.get("loyalty", 0))
	m += Market.demand(tags)
	if Village.is_festival(GameState.day):
		m += float(DataDB.happenings["festival"]["price_bonus"])
	return mini(int(adv["gold"]), int(GameState.item_value(item) * m))


func sell_item(adv: Dictionary, item: Dictionary, price: int) -> void:
	_equip(adv, item)
	adv["gold"] = int(adv["gold"]) - price
	GameState.add_gold(price)
	GameState.stats["sold"] += 1
	change_loyalty(adv, int(DataDB.heroes["loyalty"]["sale"]))
	Market.on_sold_to_hero(GameState.item_tags(item))


## Give an item away (wounded hero, a patron's favour...).
func gift_item(adv: Dictionary, item: Dictionary) -> void:
	var value := GameState.item_value(item)
	_equip(adv, item)
	# Generosity counts, but a cheap trinket is not a grand gesture.
	change_loyalty(adv, mini(int(DataDB.heroes["loyalty"]["gift"]), maxi(2, value / 4)))
	remember(adv, "You gave me the %s when I needed it most. I won't forget." % GameState.item_name(item))


func _equip(adv: Dictionary, item: Dictionary) -> void:
	var gear := GameState.item_to_gear(item)
	adv["gear"][gear["slot"]] = gear
	adv["served_day"] = GameState.day
	adv["wants_armor"] = false
	GameState.remove_item(int(item["uid"]))
	var lid: String = gear["legend"]
	if lid != "" and GameState.legends.has(lid):
		var l: Dictionary = GameState.legends[lid]
		l["status"] = "wielded"
		l["holder"] = int(adv["id"])
		l["holder_name"] = adv["name"]
		GameState.legend_event(lid, "Taken up by %s." % adv["name"])
		if str(adv.get("title", "")) == "":
			adv["title"] = DataDB.heroes["titles"]["legend_bearer"].format({ "legend": l["name"] })
		remember(adv, "Took up %s, a legend from your forge." % l["name"])
		Chronicle.add("%s took up %s." % [adv["name"], l["name"]], "legend")


func loot_price(adv: Dictionary) -> int:
	var total := 0.0
	for m in adv["loot"]:
		total += Market.price(m) * int(adv["loot"][m])
	var discount := 0.85 if int(adv.get("loyalty", 0)) >= int(DataDB.heroes["loyalty"]["regular"]) else 1.0
	return int(total * 0.8 * discount)


func buy_loot(adv: Dictionary) -> bool:
	var price := loot_price(adv)
	if price <= 0 or not GameState.spend_gold(price):
		return false
	for m in adv["loot"]:
		GameState.add_material(m, int(adv["loot"][m]))
	adv["gold"] = int(adv["gold"]) + price
	adv["loot"] = {}
	change_loyalty(adv, 2)
	return true


# --- Daily visits ----------------------------------------------------------

## Decide who comes to the shop today and when, and who goes where tonight.
## `extra_visitors`: heroes who must visit (happenings, boss parties).
func plan_day(extra_visitors: Array = []) -> void:
	schedule = []
	var tier: Dictionary = DataDB.tier_for_renown(GameState.renown)
	var count: int = int(tier["visitors"]) + GameState.upgrade_level("signboard") + Village.prosperity / 30
	if Village.project_done("guildhall"):
		count += 2
	if Village.is_festival(GameState.day):
		count += int(DataDB.happenings["festival"]["extra_visitors"])
	# Grow the roster as your fame spreads.
	var target_roster: int = min(MAX_ALIVE, count + 2 + GameState.day / 2)
	var max_level := int(tier["max_level"]) + (2 if Village.project_done("guildhall") else 0)
	while alive().size() < target_roster:
		var a := recruit(randi_range(1, max_level))
		Chronicle.add("%s, a %s %s, arrived in the village." % [a["name"], personality_of(a)["name"].to_lower(), class_name_of(a)], "hero")
	_form_boss_parties()
	for a in alive():
		if available(a):
			a["plan"] = choose_dungeon(a)["id"]
		elif a.get("expedition", {}).is_empty():
			a["plan"] = ""
	# Returning customers, loyal regulars, the wounded and boss parties first.
	var scores := {}
	var pool: Array = []
	for a in alive():
		if not a.get("expedition", {}).is_empty() and int(a["expedition"]["depart_day"]) != GameState.day:
			continue  # away in the dungeon
		scores[int(a["id"])] = _visit_score(a)
		pool.append(a)
	pool.sort_custom(func(a, b): return scores[int(a["id"])] > scores[int(b["id"])])
	var visitors: Array = []
	for id in extra_visitors:
		var a := get_adv(int(id))
		if not a.is_empty() and a["alive"]:
			visitors.append(a)
	for a in pool:
		if visitors.size() >= count + extra_visitors.size():
			break
		if not a in visitors:
			visitors.append(a)
	var span := (TimeManager.SHOP_CLOSE - 60) - TimeManager.SHOP_OPEN
	for i in visitors.size():
		var t := TimeManager.SHOP_OPEN + int(span * (i + randf_range(0.1, 0.9)) / visitors.size())
		schedule.append({ "time": t, "id": int(visitors[i]["id"]) })


func _visit_score(adv: Dictionary) -> float:
	var s := randf() * 2.0
	if not adv["loot"].is_empty():
		s += 2.0
	if adv["gear"]["weapon"] == null or adv["gear"]["armor"] == null or adv.get("wants_armor", false):
		s += 1.0
	if int(adv["gold"]) >= 60:
		s += 1.0
	s += int(adv.get("loyalty", 0)) / 25.0
	if str(adv.get("plan", "")).begins_with("boss:"):
		s += 4.0
	return s


func _on_time_changed(minutes: int) -> void:
	while not schedule.is_empty() and minutes >= int(schedule[0]["time"]):
		var visit: Dictionary = schedule.pop_front()
		var adv := get_adv(int(visit["id"]))
		if not adv.is_empty() and adv["alive"] and TimeManager.is_shop_open():
			EventBus.adventurer_arrived.emit(adv)


# --- Dungeon choice ---------------------------------------------------------------

## Chance to clear a dungeon tonight, given who's living in it.
func success_chance(adv: Dictionary, dungeon: Dictionary) -> float:
	var cond := Dungeons.conditions(dungeon["id"], GameState.day)
	var ratio := power(adv, cond["enemy"], cond["modifier"]) / float(cond["difficulty"])
	var bonus := float(GameState.affix_effect(gear_affixes(adv), "success_bonus", "add"))
	return clampf(ratio - 0.25 + bonus, 0.05, 0.95)


## Heroes pick the hardest dungeon they feel good about. Personality, bounties
## and recent scares all shift what "good" means.
func choose_dungeon(adv: Dictionary) -> Dictionary:
	var p := personality_of(adv)
	var boldness := randf_range(0.45, 0.75) + float(p["boldness"]) + 0.05 * int(adv.get("near_deaths", 0))
	var pick: Dictionary = DataDB.dungeons[0]
	for d in DataDB.dungeons:
		var cond := Dungeons.conditions(d["id"], GameState.day)
		var lure := 0.0
		if int(cond["bounty"]) > 0:
			lure = 0.25 if p.get("loves_bounty", false) else 0.15
		if success_chance(adv, d) >= boldness - lure:
			pick = d
	return pick


## Bosses: gather the strongest willing heroes into a party that leaves
## tonight on a multi-night expedition.
func _form_boss_parties() -> void:
	var bc: Dictionary = DataDB.world["boss"]
	var size := int(bc["party_size"]) + (1 if Village.project_done("guildhall") else 0)
	for d in DataDB.dungeons:
		var b := Dungeons.boss(d["id"])
		if b.is_empty() or not b.get("party", []).is_empty():
			continue
		var candidates := alive().filter(func(a):
			return available(a) and a.get("personality", "") != "cautious" and int(a["level"]) >= 2)
		if candidates.size() < size:
			continue
		candidates.sort_custom(func(a, b2): return power(a) > power(b2))
		var party := candidates.slice(0, size)
		var ids: Array = []
		for a in party:
			a["expedition"] = { "dungeon": d["id"], "depart_day": GameState.day,
				"return_day": GameState.day + int(bc["expedition_nights"]) - 1 }
			a["plan"] = "boss:" + d["id"]
			ids.append(int(a["id"]))
			remember(a, "Joined the hunt for %s." % b["name"])
		b["party"] = ids
		var names: Array = party.map(func(a): return a["name"])
		Chronicle.add("%s formed a party to hunt %s." % [", ".join(names), b["name"]], "boss")
		EventBus.notify.emit("A party is gearing up to hunt %s. They'll visit you today!" % b["name"])


# --- Overnight -------------------------------------------------------------------

## Fraction of a dungeon's renown you get per victory (scaled by how much of
## the winner's gear you made). Tune this to speed up / slow down progression.
const RENOWN_PER_WIN := 0.028
## Bonus the first time anyone wearing your gear clears each dungeon.
const FIRST_CLEAR_BONUS := 5


## Every available adventurer delves overnight; boss parties fight when their
## expedition ends. Returns report lines, renown earned and who you didn't serve.
func run_night() -> Dictionary:
	var lines: Array = []
	var renown_gain := 0.0
	var unserved: Array = []
	for adv in alive():
		if int(adv.get("served_day", 0)) != GameState.day and adv.get("expedition", {}).is_empty():
			unserved.append(adv)
	# Boss expeditions that end tonight.
	for d in DataDB.dungeons:
		var b := Dungeons.boss(d["id"])
		if b.is_empty() or b.get("party", []).is_empty():
			continue
		var party: Array = b["party"].map(func(id): return get_adv(int(id))).filter(func(a): return not a.is_empty() and a["alive"])
		if party.is_empty():
			b["party"] = []
			continue
		if int(party[0]["expedition"]["return_day"]) > GameState.day:
			lines.append("[color=#b8b0a0]%s's party is still deep in the %s, hunting %s.[/color]" % [party[0]["name"], d["name"], b["name"]])
			continue
		var res := _boss_fight(d, b, party)
		lines.append_array(res["lines"])
		renown_gain += float(res["renown"])
	for adv in alive():
		if not adv.get("expedition", {}).is_empty():
			continue
		if int(adv.get("injured_until", 0)) >= GameState.day:
			lines.append("[color=#9a8f86]%s is still nursing their wounds.[/color]" % adv["name"])
			continue
		var res := _run(adv)
		lines.append(res["text"])
		renown_gain += float(res["renown"])
	return { "lines": lines, "renown": int(round(renown_gain)), "unserved": unserved }


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


func _death_mult(adv: Dictionary, mod: Dictionary) -> float:
	var affixes := gear_affixes(adv)
	var m := float(GameState.affix_effect(affixes, "death_mult", "mult"))
	if "cursed" in affixes:
		m *= float(mod.get("curse_risk", 1.0))
	if Village.project_done("chapel"):
		m *= 0.75
	return m


func _run(adv: Dictionary) -> Dictionary:
	var d := DataDB.dungeon(adv.get("plan", ""))
	if d.is_empty():
		d = choose_dungeon(adv)
	adv["plan"] = ""
	var cond := Dungeons.conditions(d["id"], GameState.day)
	var enemy: String = cond["enemy"]
	var enemy_name: String = DataDB.enemies[enemy]["name"]
	var mod: Dictionary = cond["modifier"]
	var chance := success_chance(adv, d)
	var share := _player_share(adv)
	var who := "%s (Lv %d %s)" % [full_name(adv), int(adv["level"]), class_name_of(adv)]
	var renown := 0.0
	var text := ""
	var affixes := gear_affixes(adv)
	var loot_mult := float(GameState.affix_effect(affixes, "loot_mult", "mult"))
	var p := personality_of(adv)
	var mod_note := " [color=#c77dff](%s)[/color]" % mod["name"] if not mod.is_empty() else ""
	adv["runs"] = int(adv["runs"]) + 1
	var won := randf() < chance
	Dungeons.record_run(d["id"], won)

	if won:
		var gold := int((randi_range(int(d["gold"][0]), int(d["gold"][1])) + int(cond["bounty"])) * loot_mult)
		adv["gold"] = int(adv["gold"]) + gold
		adv["wins"] = int(adv.get("wins", 0)) + 1
		adv["xp"] = int(adv["xp"]) + int(d["xp"])
		var leveled := false
		while int(adv["xp"]) >= int(adv["level"]) * 10:
			adv["xp"] = int(adv["xp"]) - int(adv["level"]) * 10
			adv["level"] = int(adv["level"]) + 1
			leveled = true
		var found := {}
		for m in cond["loot"]:
			var n := int(round(randi_range(int(cond["loot"][m][0]), int(cond["loot"][m][1])) * loot_mult))
			if n > 0:
				found[m] = n
		text = "[color=#8fd18f]%s beat the %s in %s[/color]%s (+%dg%s)" % [
			who, enemy_name, d["name"], mod_note, gold, ", bounty!" if int(cond["bounty"]) > 0 else ""]
		# Pressing deeper: more loot and strange finds, more danger.
		var press := float(p["press_on"]) + (0.2 if loot_mult > 1.0 else 0.0)
		if randf() < press:
			if randf() < 0.7:
				for m in found:
					found[m] = int(found[m]) * 2
				text += " Pressed deeper for more treasure!"
				var lid := Dungeons.try_recover_legend(d["id"], 0.3 + (0.3 if loot_mult > 1.0 else 0.0))
				if lid != "":
					text += _recover_legend(adv, lid, d)
				elif randf() < 0.12 * loot_mult and not adv.get("found_map", false):
					adv["found_map"] = true
					text += " [color=#ffd27a]They found an old treasure map![/color]"
					remember(adv, "Found a treasure map deep in %s." % d["name"])
			else:
				text += " [color=#e0b06c]Pressed too deep and barely made it out.[/color]"
				adv["injured_until"] = GameState.day + (0 if Village.project_done("chapel") else 1)
				remember(adv, "Went too deep in %s. Never again... probably." % d["name"])
		for m in found:
			adv["loot"][m] = int(adv["loot"].get(m, 0)) + int(found[m])
			Market.on_loot_arrived(m, int(found[m]))
		if leveled:
			text += " Reached level %d!" % int(adv["level"])
		var counter := _best_counter(adv, enemy, mod)
		if counter != "":
			text += " Their %s was deadly against them!" % counter
		_record_kill(adv, enemy, d)
		if _has_rival_gear(adv):
			Market.rival_gear_won()
		if share > 0.0:
			renown = float(d["renown"]) * share * RENOWN_PER_WIN
			if counter != "" and _is_player_made(adv, counter):
				renown *= 1.5  # word spreads that you knew exactly what they needed
				change_loyalty(adv, int(DataDB.heroes["loyalty"]["counter_win"]))
			text += " [color=#ffc94a]Wearing your gear![/color]"
			if not d["id"] in GameState.first_clears:
				GameState.first_clears.append(d["id"])
				renown += FIRST_CLEAR_BONUS
				text += " [color=#ffc94a][b]First clear of %s with your gear! +%d renown[/b][/color]" % [d["name"], FIRST_CLEAR_BONUS]
		adv["last_result"] = "Cleared %s" % d["name"]
	else:
		var death_chance := (0.05 + 0.3 * (1.0 - chance)) * _death_mult(adv, mod)
		if randf() < death_chance:
			_kill(adv, d, enemy_name)
			text = "[color=#e06c6c]%s fell to the %s in %s.[/color]%s" % [who, enemy_name, d["name"], mod_note]
			if share > 0.0:
				renown = -1.0
				text += " Whispers say your gear failed them."
			if _has_rival_gear(adv):
				Market.rival_gear_failed()
			return { "text": text, "renown": renown }
		text = "[color=#e0b06c]%s retreated from the %s in %s, battered.[/color]%s" % [who, enemy_name, d["name"], mod_note]
		adv["last_result"] = "Retreated from %s" % d["name"]
		if chance < 0.35:
			_close_call(adv, d)
			text += " A close call."
		elif not Village.project_done("chapel"):
			adv["injured_until"] = GameState.day + 1
		if _has_rival_gear(adv):
			Market.rival_gear_failed()
		if share > 0.0:
			change_loyalty(adv, -2)

	# Gear wears out (unless Sturdy or legendary), which keeps them coming back.
	var break_chance := (0.08 if won else 0.25) * float(mod.get("break_mult", 1.0))
	for slot in DataDB.SLOTS:
		var g = adv["gear"][slot]
		if g == null or GameState.affix_effect(g.get("affixes", []), "unbreakable", "any") or str(g.get("legend", "")) != "":
			continue
		if randf() < break_chance:
			text += " Their %s broke." % g["name"]
			adv["gear"][slot] = null
			if g["player_made"]:
				adv["wants_armor"] = slot == "armor"
	return { "text": text, "renown": renown }


func _record_kill(adv: Dictionary, enemy: String, d: Dictionary) -> void:
	adv["kills"][enemy] = int(adv["kills"].get(enemy, 0)) + 1
	var need := int(DataDB.heroes["titles"]["kills_for_bane"])
	if int(adv["kills"][enemy]) == need and str(adv.get("title", "")).find("Slayer") < 0:
		var short: String = DataDB.enemies[enemy]["name"].split(" ")[-1].trim_suffix("s")
		adv["title"] = DataDB.heroes["titles"]["bane"].format({ "enemy": short })
		remember(adv, "Earned the name %s." % adv["title"])
		Chronicle.add("%s earned the title %s after their %dth victory over the %s." % [adv["name"], adv["title"], need, DataDB.enemies[enemy]["name"]], "hero")
	for slot in DataDB.SLOTS:
		var g = adv["gear"][slot]
		if g != null and str(g.get("legend", "")) != "" and GameState.legends.has(g["legend"]):
			var l: Dictionary = GameState.legends[g["legend"]]
			l["kills"] = int(l["kills"]) + 1
			if int(l["kills"]) in [5, 15, 30]:
				GameState.legend_event(g["legend"], "%d victories in the hands of %s." % [int(l["kills"]), adv["name"]])
				Chronicle.add("%s has now seen %d victories." % [l["name"], int(l["kills"])], "legend")


func _close_call(adv: Dictionary, d: Dictionary) -> void:
	adv["near_deaths"] = int(adv.get("near_deaths", 0)) + 1
	adv["injured_until"] = GameState.day + (0 if Village.project_done("chapel") else 2)
	adv["wants_armor"] = true
	if adv.get("personality", "") == "reckless":
		adv["personality"] = "cautious"
		remember(adv, "Nearly died in %s. Something in me changed." % d["name"])
		Chronicle.add("%s nearly died in the %s and swore off recklessness." % [adv["name"], d["name"]], "hero")
	else:
		remember(adv, "Barely escaped %s alive." % d["name"])
	if int(adv["near_deaths"]) == 3 and str(adv.get("title", "")) == "":
		adv["title"] = DataDB.heroes["titles"]["survivor"]
		Chronicle.add("%s survived a third brush with death and is now called %s." % [adv["name"], adv["title"]], "hero")


func _kill(adv: Dictionary, d: Dictionary, enemy_name: String) -> void:
	adv["alive"] = false
	adv["last_result"] = "Died in %s" % d["name"]
	adv["expedition"] = {}
	Chronicle.add("%s fell to the %s in the %s." % [full_name(adv), enemy_name, d["name"]], "death")
	for slot in DataDB.SLOTS:
		var g = adv["gear"][slot]
		if g != null and str(g.get("legend", "")) != "" and GameState.legends.has(g["legend"]):
			var lid: String = g["legend"]
			GameState.legends[lid]["status"] = "lost"
			GameState.legends[lid]["location"] = d["name"]
			GameState.legend_event(lid, "Lost in %s when %s fell." % [d["name"], adv["name"]])
			Dungeons.lose_legend(d["id"], lid)
			Chronicle.add("%s was lost in the %s." % [GameState.legends[lid]["name"], d["name"]], "legend")
	var rival := get_adv(int(adv.get("rival", 0)))
	if not rival.is_empty() and rival["alive"]:
		remember(rival, "My rival %s fell in %s. I'll finish what they started." % [adv["name"], d["name"]])
		rival["personality"] = "glory"


func _recover_legend(adv: Dictionary, lid: String, d: Dictionary) -> String:
	if not GameState.legends.has(lid):
		return ""
	var l: Dictionary = GameState.legends[lid]
	GameState.legend_event(lid, "Recovered from %s by %s." % [d["name"], adv["name"]])
	GameState.restore_legend(lid)
	change_loyalty(adv, 10)
	GameState.add_renown(2)
	remember(adv, "Found %s in %s and brought it home to its maker." % [l["name"], d["name"]])
	Chronicle.add("%s recovered the lost %s from the %s and returned it to your forge." % [adv["name"], l["name"], d["name"]], "legend")
	return " [color=#ffc94a][b]They found the lost %s and brought it back to you![/b][/color]" % l["name"]


func _boss_fight(d: Dictionary, b: Dictionary, party: Array) -> Dictionary:
	var lines: Array = []
	var bc: Dictionary = DataDB.world["boss"]
	var enemy: String = b["enemy"]
	var team := 0.0
	for a in party:
		team += power(a, enemy)
	var need := float(d["difficulty"]) * float(bc["difficulty_mult"]) * 2.2
	var bonus := 0.0
	for a in party:
		bonus += float(GameState.affix_effect(gear_affixes(a), "success_bonus", "add"))
	var chance := clampf(team / need - 0.25 + bonus / party.size(), 0.05, 0.92)
	var names: Array = party.map(func(a): return a["name"])
	var renown := 0.0
	for a in party:
		a["expedition"] = {}
		a["plan"] = ""
	if randf() < chance:
		Dungeons.slay_boss(d["id"], names)
		var share := 0.0
		for a in party:
			share += _player_share(a) / party.size()
			_record_kill(a, enemy, d)
			a["title"] = DataDB.heroes["titles"]["boss"].format({ "boss": b["name"].replace("the ", "").split(" ")[0] })
			a["gold"] = int(a["gold"]) + int(bc["bounty"]) / party.size()
			a["level"] = int(a["level"]) + 1
			remember(a, "Slew %s with %s." % [b["name"], ", ".join(names.filter(func(n): return n != a["name"]))])
			if randf() < 0.1 * _death_mult(a, {}):
				_kill(a, d, b["name"])
				lines.append("[color=#e06c6c]%s fell in the final blow.[/color]" % a["name"])
		party[0]["loot"][b["trophy"]] = int(party[0]["loot"].get(b["trophy"], 0)) + 1
		lines.push_front("[color=#ffc94a][b]%s slew %s in the %s![/b][/color] %s carries home the %s." % [
			", ".join(names), b["name"], d["name"], party[0]["name"], DataDB.material_name(b["trophy"])])
		if share > 0.0:
			renown = float(bc["renown"]) * maxf(share, 0.4)
			GameState.learn_blueprint(b["blueprint"], "a schematic from %s's lair" % b["name"])
			lines.append("[color=#ffc94a]They bring you a schematic from the lair: %s! (+%d renown)[/color]" % [DataDB.recipes[b["blueprint"]]["name"], int(renown)])
			for a in party:
				change_loyalty(a, 15)
		else:
			Market.rival_rep += 4.0
			lines.append("[color=#e0b06c]None of them wore your gear. They sold the lair's schematic to %s.[/color]" % DataDB.world["rival"]["name"])
		EventBus.celebrate.emit("%s is slain!" % b["name"], "%s brought peace to the %s" % [" & ".join(names), d["name"]])
	else:
		b["party"] = []
		Dungeons._change_threat(d["id"], 10)
		lines.append("[color=#e06c6c][b]The hunt for %s failed.[/b][/color]" % b["name"])
		for a in party:
			if randf() < 0.35 * _death_mult(a, {}):
				_kill(a, d, b["name"])
				lines.append("[color=#e06c6c]%s did not come back.[/color]" % a["name"])
			else:
				a["injured_until"] = GameState.day + (1 if Village.project_done("chapel") else 2)
				a["near_deaths"] = int(a.get("near_deaths", 0)) + 1
				a["wants_armor"] = true
				remember(a, "Fled from %s. We weren't ready." % b["name"])
		Chronicle.add("A party failed to slay %s." % b["name"], "boss")
	return { "lines": lines, "renown": renown }


## Name of the gear piece that exploits this enemy's weakness, or "".
func _best_counter(adv: Dictionary, enemy: String, mod := {}) -> String:
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


func _has_rival_gear(adv: Dictionary) -> bool:
	for slot in DataDB.SLOTS:
		var g = adv["gear"][slot]
		if g != null and g.get("rival_made", false):
			return true
	return false


## Heroes spend part of their purse in the village every night (inns,
## healers, ale). Keeps hero wealth - and your prices - from inflating
## forever, and their spending feeds the village's prosperity.
func spend_in_village() -> Array:
	var spent := 0
	for a in alive():
		var s := int(int(a["gold"]) * 0.12) + int(a["level"]) * 2
		s = mini(s, int(a["gold"]))
		a["gold"] = int(a["gold"]) - s
		spent += s
	Village.add_trade(spent)
	return []


## Legendary visitor (happenings): joins the roster as a powerful hero.
func recruit_legendary(def: Dictionary) -> Dictionary:
	var a := recruit(int(def["level"]), { "name": def["name"], "cls": def["cls"],
		"personality": def["personality"], "legendary": true })
	a["gold"] = 400 + int(def["level"]) * 40
	a["title"] = "the Legendary"
	return a


# --- Save / load -------------------------------------------------------------

func to_dict() -> Dictionary:
	return { "roster": roster, "next_id": next_id }


func from_dict(d: Dictionary) -> void:
	reset()
	next_id = int(d.get("next_id", 1))
	for a in d.get("roster", []):
		var adv: Dictionary = {
			"personality": "steady", "loyalty": 0, "memories": [], "title": "", "kills": {},
			"wins": 0, "near_deaths": 0, "injured_until": 0, "expedition": {}, "plan": "",
			"rival": 0, "served_day": 0, "legendary": false, "patron_gift": false,
		}
		adv.merge(a, true)
		for slot in DataDB.SLOTS:
			var g = adv["gear"].get(slot)
			if g != null:
				var fixed := { "recipe": "", "affixes": [], "legend": "", "player_made": false }
				fixed.merge(g, true)
				g = fixed
			adv["gear"][slot] = g
		roster.append(adv)
