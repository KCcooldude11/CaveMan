extends Node
## Happenings: rare, state-driven village events. Every night the simulation
## looks at what is actually going on (wounded heroes, rivalries, your fame,
## the rival smith, dungeon threat, the market...) and may create a situation
## for the morning. Most are DECISIONS with real trade-offs; some are news.
##
## A decision: { id, kind, day, title, text, options: [{ key, label, hint }], data }

var pending: Array = []        # decisions waiting for the player
var news: Array = []           # this morning's informational items (strings)
var last: Dictionary = {}      # kind -> day it last happened (cooldowns)
var next_id := 1
var raid := {}                 # { dungeon, day, mercenaries, militia_power } when monsters march on the village
var vault := {}                # { day, hero } treasure-map expedition


func reset() -> void:
	pending = []
	news = []
	last = {}
	next_id = 1
	raid = {}
	vault = {}


func _cfg(kind: String) -> Dictionary:
	return DataDB.happenings[kind]


func _ready_for(kind: String, day: int) -> bool:
	return day - int(last.get(kind, -999)) >= int(_cfg(kind).get("cooldown", 0))


func _add(kind: String, title: String, text: String, options: Array, data := {}) -> Dictionary:
	var d := { "id": next_id, "kind": kind, "day": GameState.day, "title": title, "text": text,
		"options": options, "data": data }
	next_id += 1
	pending.append(d)
	last[kind] = GameState.day
	return d


func _news(kind: String, text: String) -> void:
	news.append(text)
	last[kind] = GameState.day


## Heroes who must visit the shop today (decisions involving them).
func forced_visitors() -> Array:
	var out: Array = []
	for d in pending:
		for id in d["data"].get("heroes", []):
			if not id in out:
				out.append(id)
	return out


# --- Generation (called at the start of each new day) --------------------------

func evaluate(day: int) -> void:
	news = []
	# Old undecided situations resolve themselves (badly, usually).
	for d in pending.duplicate():
		if day - int(d["day"]) >= 1:
			resolve(int(d["id"]), "_expired")
	_raid_check(day)
	_wounded_hero(day)
	_bidding_war(day)
	_legendary_hero(day)
	_royal_envoy(day)
	_rival_challenge(day)
	_festival(day)
	_bargain_trader(day)
	_treasure_map(day)
	_mine_vein(day)
	_shortage(day)


func _raid_check(day: int) -> void:
	var id := Dungeons.raid_pending
	if id == "" or not raid.is_empty():
		return
	var d := DataDB.dungeon(id)
	var enemy: String = Dungeons.get_state(id)["controller"]
	raid = { "dungeon": id, "day": day, "mercenaries": false, "militia_power": 0 }
	_add("raid", "RAID: the %s march on the village!" % DataDB.enemies[enemy]["name"],
		"Left unchecked, the %s have boiled out of the %s. They'll hit the village TONIGHT. How do you prepare?" % [DataDB.enemies[enemy]["name"], d["name"]],
		[{ "key": "mercs", "label": "Hire mercenaries (%dg)" % int(_cfg("raid")["mercenary_cost"]), "hint": "Reliable, expensive." },
		 { "key": "militia", "label": "Arm the militia with your shelf", "hint": "Donate every weapon and armor piece on your shelf. Their power defends the village." },
		 { "key": "trust", "label": "Trust the heroes and the walls", "hint": "Free. Risky if the heroes are weak or away." }],
		{ "dungeon": id })
	Chronicle.add("The %s marched on the village from the %s." % [DataDB.enemies[enemy]["name"], d["name"]], "village")


func _wounded_hero(day: int) -> void:
	if not _ready_for("wounded_hero", day):
		return
	for a in AdventurerManager.alive():
		if int(a.get("injured_until", 0)) >= day and a.get("wants_armor", false) and int(a.get("loyalty", 0)) >= 0 and a.get("expedition", {}).is_empty():
			var armor := GameState.items.filter(func(it): return GameState.item_slot(it) == "armor")
			var opts := [
				{ "key": "commission", "label": "Promise to make them armor (2 days)", "hint": "They'll pay what they have and remember you kept your word." },
				{ "key": "refuse", "label": "Not today", "hint": "They'll find someone else. They won't forget." }]
			if not armor.is_empty():
				opts.push_front({ "key": "gift", "label": "Give them your best armor for free", "hint": "Costs you the armor. Earns deep loyalty and renown." })
			_add("wounded_hero", "%s limps into your shop" % a["name"],
				"%s (Lv %d %s) barely survived last night. \"I can't go back in there without proper armor. Please.\"" % [a["name"], int(a["level"]), AdventurerManager.class_name_of(a)],
				opts, { "heroes": [int(a["id"])] })
			return


func _bidding_war(day: int) -> void:
	if not _ready_for("bidding_war", day) or GameState.items.is_empty():
		return
	for a in AdventurerManager.alive():
		var b := AdventurerManager.get_adv(int(a.get("rival", 0)))
		if b.is_empty() or not b["alive"] or not AdventurerManager.available(a) or not AdventurerManager.available(b):
			continue
		var best := {}
		for it in GameState.items:
			if (best.is_empty() or GameState.item_value(it) > GameState.item_value(best)) and GameState.item_slot(it) == "weapon":
				best = it
		if best.is_empty() or GameState.item_value(best) < 60:
			return
		var pa := int(AdventurerManager.max_price(a, best) * 1.1)
		var pb := int(AdventurerManager.max_price(b, best) * 1.1)
		if pa < 20 or pb < 20:
			return
		_add("bidding_war", "Bidding war: %s vs %s" % [a["name"], b["name"]],
			"The rivals both want your %s, and neither will let the other have it. Whoever loses won't take it well." % GameState.item_name(best),
			[{ "key": "a", "label": "Sell to %s for %dg (loyalty %d)" % [a["name"], pa, int(a.get("loyalty", 0))], "hint": "" },
			 { "key": "b", "label": "Sell to %s for %dg (loyalty %d)" % [b["name"], pb, int(b.get("loyalty", 0))], "hint": "" },
			 { "key": "keep", "label": "Sell to neither", "hint": "Both leave annoyed, but you keep the item." }],
			{ "heroes": [int(a["id"]), int(b["id"])], "item": int(best["uid"]), "price_a": pa, "price_b": pb })
		return


func _legendary_hero(day: int) -> void:
	var cfg := _cfg("legendary_hero")
	if not _ready_for("legendary_hero", day) or GameState.renown < int(cfg["min_renown"]) or randf() > 0.5:
		return
	var present: Array = AdventurerManager.alive().map(func(a): return a["name"])
	var defs: Array = DataDB.heroes["legendary_heroes"].filter(func(h): return not h["name"] in present and not AdventurerManager.roster.any(func(a): return a["name"] == h["name"]))
	if defs.is_empty():
		return
	var def: Dictionary = defs.pick_random()
	var hero := AdventurerManager.recruit_legendary(def)
	var liked: Array = DataDB.classes[def["cls"]]["likes"]
	var recipes: Array = DataDB.recipes.keys().filter(func(r):
		return DataDB.recipes[r]["slot"] == "weapon" and GameState.is_recipe_unlocked(r) and GameState.station_level(DataDB.recipes[r]["station"]) > 0 and DataDB.recipes[r]["tags"].any(func(t): return t in liked))
	if recipes.is_empty():
		recipes = DataDB.recipes.keys().filter(func(r): return DataDB.recipes[r]["slot"] == "weapon" and GameState.is_recipe_unlocked(r))
	var recipe: String = recipes.pick_random()
	Chronicle.add("%s, a living legend, arrived in the village." % def["name"], "hero")
	_add("legendary_hero", "%s has come to town" % def["name"],
		"The legendary %s wants to know if your forge is worth the walk. \"Make me a Masterwork %s within 5 days and I'll carry your name into every dungeon I enter.\"" % [AdventurerManager.class_name_of(hero), DataDB.recipes[recipe]["name"]],
		[{ "key": "accept", "label": "Accept the challenge", "hint": "Masterwork quality is hard. Pays 500g + 8 renown and makes them your patron; failing costs 4 renown." },
		 { "key": "decline", "label": "Politely decline", "hint": "No risk. They'll shop elsewhere." }],
		{ "heroes": [int(hero["id"])], "recipe": recipe })


func _royal_envoy(day: int) -> void:
	var cfg := _cfg("royal_envoy")
	if not _ready_for("royal_envoy", day) or GameState.renown < int(cfg["min_renown"]):
		return
	_add("royal_envoy", "A royal envoy arrives",
		"An envoy of the Crown wants a blade fit for the king's champion: a Fine-or-better weapon infused with any rare material, within %d days." % int(cfg["days"]),
		[{ "key": "accept", "label": "Accept the royal commission", "hint": "%dg + %d renown. Failing costs %d renown." % [int(cfg["gold"]), int(cfg["renown"]), -int(cfg["fail_renown"])] },
		 { "key": "decline", "label": "Decline", "hint": "Safer. The Crown will remember, though." }])


func _rival_challenge(day: int) -> void:
	var cfg := _cfg("rival_challenge")
	if not Market.rival_active or not _ready_for("rival_challenge", day) or GameState.renown < 12:
		return
	if absf(Market.rival_rep - GameState.renown) > 30 or randf() > 0.5:
		return
	var rp := int(10 + Market.rival_rep * 0.35)
	_add("rival_challenge", "%s challenges you" % DataDB.world["rival"]["name"],
		"\"Your so-called masterpieces are tin. Bring your best weapon to the square in %d days. My entry: power %d.\"" % [int(cfg["days"]), rp],
		[{ "key": "accept", "label": "Accept the contest", "hint": "Beat power %d: +%d renown, Brannoc loses customers. Lose: %d renown." % [rp, int(cfg["win_renown"]), int(cfg["lose_renown"])] },
		 { "key": "decline", "label": "Ignore him", "hint": "-1 renown; Brannoc gains confidence." }],
		{ "rival_power": rp })


func _festival(day: int) -> void:
	var cfg := _cfg("festival")
	if not _ready_for("festival", day) or Village.prosperity < int(cfg["min_prosperity"]):
		return
	Village.flags["festival_day"] = day + 1
	_add("festival", "The Harvest Festival is tomorrow!",
		"Tomorrow more heroes come to town and everyone pays %d%% more. The mayor asks if you'll sponsor it." % int(float(cfg["price_bonus"]) * 100),
		[{ "key": "sponsor", "label": "Sponsor the festival (%dg)" % int(cfg["sponsor_cost"]), "hint": "+%d prosperity, +%d renown." % [int(cfg["sponsor_prosperity"]), int(cfg["sponsor_renown"])] },
		 { "key": "skip", "label": "Just enjoy it", "hint": "The festival still happens." }])


func _bargain_trader(day: int) -> void:
	if not _ready_for("bargain_trader", day) or randf() > 0.4:
		return
	var rare: Array = DataDB.materials.keys().filter(func(m):
		return not DataDB.materials[m]["buyable"] and not DataDB.materials[m].get("trophy", false) and GameState.material_count(m) >= 2)
	var unknown: Array = DataDB.recipes.keys().filter(func(r): return DataDB.recipes[r].get("blueprint", false) and not r in GameState.known_blueprints)
	if rare.is_empty() or unknown.is_empty():
		return
	var want: String = rare.pick_random()
	var bp: String = unknown.pick_random()
	_add("bargain_trader", "A hooded trader at your door",
		"\"I have a schematic you won't find anywhere else - the %s. I'll trade it for 2 %s. Nothing else.\"" % [DataDB.recipes[bp]["name"], DataDB.material_name(want)],
		[{ "key": "trade", "label": "Trade 2 %s for the blueprint" % DataDB.material_name(want), "hint": "Rare material now vs. a new recipe forever." },
		 { "key": "decline", "label": "No deal", "hint": "Keep your materials." }],
		{ "material": want, "blueprint": bp })


func _treasure_map(day: int) -> void:
	if not _ready_for("treasure_map", day):
		return
	for a in AdventurerManager.alive():
		if a.get("found_map", false):
			a["found_map"] = false
			var cfg := _cfg("treasure_map")
			_add("treasure_map", "%s found a treasure map" % a["name"],
				"\"It points to a sunken vault under the old road. I could sell it to you... or chase it myself.\"",
				[{ "key": "buy", "label": "Buy the map and fund the expedition (%dg)" % int(cfg["price"]), "hint": "Tomorrow night %s delves the vault for YOU: rare materials, maybe a blueprint. They could fail." % a["name"] },
				 { "key": "let", "label": "Let them chase it", "hint": "+loyalty. The treasure is theirs." }],
				{ "heroes": [int(a["id"])], "hero": int(a["id"]) })
			return


func _mine_vein(day: int) -> void:
	var cfg := _cfg("mine_vein")
	if not _ready_for("mine_vein", day) or Village.gathers_total < int(cfg["min_gathers"]) or randf() > 0.35:
		return
	Village.flags["vein_until"] = day + int(cfg["days"])
	_news("mine_vein", "[color=#9fd8ff]Miners report a glittering vein in the Old Mine! For %d days, scavenging there yields Mithril Ore.[/color]" % int(cfg["days"]))
	Chronicle.add("A mithril vein was found in the Old Mine.", "village")


func _shortage(day: int) -> void:
	var cfg := _cfg("shortage")
	if not _ready_for("shortage", day) or Village.safety > int(cfg["max_safety"]) or randf() > 0.5:
		return
	var m: String = ["iron_ingot", "leather", "wood", "silver_ingot"].pick_random()
	Market.add_shock(m, float(cfg["price_mult"]), 3)
	_news("shortage", "[color=#e06c6c]Bandits on the roads (low village safety) robbed the supply carts: %s prices nearly double for 3 days.[/color]" % DataDB.material_name(m))
	Chronicle.add("Bandits robbed the supply carts; %s became scarce." % DataDB.material_name(m), "market")


# --- Resolution ---------------------------------------------------------------

func get_decision(id: int) -> Dictionary:
	for d in pending:
		if int(d["id"]) == id:
			return d
	return {}


## Apply the player's choice. "_expired" = they never decided. Returns a
## short description of what happened.
func resolve(id: int, key: String) -> String:
	var d := get_decision(id)
	if d.is_empty():
		return ""
	pending.erase(d)
	var data: Dictionary = d["data"]
	var out := ""
	match d["kind"]:
		"raid":
			match key:
				"mercs":
					if GameState.spend_gold(int(_cfg("raid")["mercenary_cost"])):
						raid["mercenaries"] = true
						out = "Mercenaries will hold the walls tonight."
					else:
						out = "You couldn't afford mercenaries."
				"militia":
					var p := 0
					for it in GameState.items.duplicate():
						if GameState.item_slot(it) in ["weapon", "armor"]:
							p += GameState.item_power(it)
							GameState.remove_item(int(it["uid"]))
					raid["militia_power"] = int(raid.get("militia_power", 0)) + p
					out = "You armed the militia (defense +%d)." % p
				_:
					out = "You trust the heroes to hold."
		"wounded_hero":
			var adv := AdventurerManager.get_adv(int(data["heroes"][0]))
			match key:
				"gift":
					var armor := GameState.items.filter(func(it): return GameState.item_slot(it) == "armor")
					if not armor.is_empty() and not adv.is_empty():
						armor.sort_custom(func(x, y): return GameState.item_power(x) > GameState.item_power(y))
						AdventurerManager.gift_item(adv, armor[0])
						GameState.add_renown(int(_cfg("wounded_hero")["gift_renown"]))
						Chronicle.add("You gave %s armor when they had nothing. They won't forget." % adv["name"], "hero")
						out = "%s will never forget this." % adv["name"]
				"commission":
					if not adv.is_empty():
						Village.add_commission({ "giver": adv["name"], "slot": "armor", "quality": 1,
							"gold": int(int(adv["gold"]) * 0.9), "renown": 1, "due": GameState.day + 2,
							"special": "hero", "hero": int(adv["id"]), "reason": "so they can go back in" })
						out = "Commission added to the notice board."
				_:
					if not adv.is_empty():
						AdventurerManager.change_loyalty(adv, int(DataDB.heroes["loyalty"]["turned_away"]))
						AdventurerManager.remember(adv, "Begged for armor at your forge. Got turned away.")
		"bidding_war":
			var a := AdventurerManager.get_adv(int(data["heroes"][0]))
			var b := AdventurerManager.get_adv(int(data["heroes"][1]))
			var item := GameState.find_item(int(data["item"]))
			if key in ["a", "b"] and not item.is_empty() and not a.is_empty() and not b.is_empty():
				var winner := a if key == "a" else b
				var loser := b if key == "a" else a
				var price := int(data["price_a"] if key == "a" else data["price_b"])
				price = mini(price, int(winner["gold"]))
				AdventurerManager.sell_item(winner, item, price)
				AdventurerManager.change_loyalty(loser, -10)
				AdventurerManager.remember(loser, "You sold %s to my rival %s. Noted." % [GameState.item_name(item), winner["name"]])
				AdventurerManager.remember(winner, "Outbid %s for %s." % [loser["name"], GameState.item_name(item)])
				Chronicle.add("%s outbid their rival %s for your %s (%dg)." % [winner["name"], loser["name"], GameState.item_name(item), price], "hero")
				out = "Sold for %dg. %s is furious." % [price, loser["name"]]
			elif not a.is_empty() and not b.is_empty():
				AdventurerManager.change_loyalty(a, -3)
				AdventurerManager.change_loyalty(b, -3)
		"legendary_hero":
			var adv := AdventurerManager.get_adv(int(data["heroes"][0]))
			if key == "accept" and not adv.is_empty():
				Village.add_commission({ "giver": adv["name"], "recipe": data["recipe"], "quality": 3,
					"gold": 500, "renown": 8, "due": GameState.day + 5, "special": "hero",
					"hero": int(adv["id"]), "fail_renown": -4, "reason": "to prove your forge's worth" })
				out = "The challenge is on the notice board."
		"royal_envoy":
			if key == "accept":
				var cfg := _cfg("royal_envoy")
				Village.add_commission({ "giver": "The Royal Envoy", "slot": "weapon", "quality": 2, "affix": "any",
					"gold": int(cfg["gold"]), "renown": int(cfg["renown"]), "due": GameState.day + int(cfg["days"]),
					"special": "envoy", "fail_renown": int(cfg["fail_renown"]), "reason": "for the king's champion" })
				out = "The royal commission is on the notice board."
		"rival_challenge":
			if key == "accept":
				var cfg := _cfg("rival_challenge")
				Village.add_commission({ "giver": DataDB.world["rival"]["name"], "slot": "weapon", "quality": 0,
					"gold": 50, "renown": 0, "due": GameState.day + int(cfg["days"]), "special": "contest",
					"rival_power": int(data["rival_power"]), "reason": "to beat power %d" % int(data["rival_power"]) })
				out = "Contest accepted. Deliver your entry at the notice board."
			else:
				GameState.add_renown(-1)
				Market.rival_rep += 3.0
		"festival":
			if key == "sponsor":
				var cfg := _cfg("festival")
				if GameState.spend_gold(int(cfg["sponsor_cost"])):
					Village.change_prosperity(int(cfg["sponsor_prosperity"]))
					GameState.add_renown(int(cfg["sponsor_renown"]))
					Chronicle.add("You sponsored the Harvest Festival.", "village")
					out = "The village cheers your name."
		"bargain_trader":
			if key == "trade" and GameState.consume_materials({ data["material"]: 2 }):
				GameState.learn_blueprint(data["blueprint"], "traded from a hooded stranger")
				out = "You learned the %s." % DataDB.recipes[data["blueprint"]]["name"]
		"treasure_map":
			var adv := AdventurerManager.get_adv(int(data["hero"]))
			if key == "buy" and not adv.is_empty() and GameState.spend_gold(int(_cfg("treasure_map")["price"])):
				vault = { "day": GameState.day, "hero": int(adv["id"]) }
				out = "%s will delve the vault for you tonight." % adv["name"]
			elif not adv.is_empty():
				AdventurerManager.change_loyalty(adv, 5)
				adv["gold"] = int(adv["gold"]) + 120
				AdventurerManager.remember(adv, "Followed my own treasure map. Worth it.")
	if out != "":
		EventBus.notify.emit(out)
	return out


# --- Night resolution (called by Simulation) -------------------------------------

## Monsters attack the village. Returns report lines.
func resolve_raid(day: int) -> Array:
	if raid.is_empty() or int(raid["day"]) != day:
		return []
	var lines: Array = []
	var id: String = raid["dungeon"]
	var d := DataDB.dungeon(id)
	var defense := Village.safety * 0.6 + int(raid.get("militia_power", 0)) * float(_cfg("raid")["militia_per_item"])
	if raid.get("mercenaries", false):
		defense += float(_cfg("raid")["mercenary_power"])
	if Village.project_done("watchtower"):
		defense += 40.0
	var defenders := AdventurerManager.alive().filter(func(a): return AdventurerManager.available(a))
	for a in defenders:
		defense += AdventurerManager.power(a) * 0.35
	var attack := float(d["difficulty"]) * 2.0 + 60.0
	if randf() * (defense + attack) < defense:
		lines.append("[color=#ffc94a][b]The village held![/b] The raid from the %s was broken at the walls.[/color]" % d["name"])
		GameState.add_renown(3)
		Village.change_safety(10)
		Chronicle.add("The village repelled a raid from the %s." % d["name"], "village")
		EventBus.celebrate.emit("The village held!", "The raid from the %s was broken" % d["name"])
	else:
		var lost_gold := mini(200, GameState.gold / 5)
		GameState.spend_gold(lost_gold)
		var stolen := 0
		for it in GameState.items.duplicate():
			if stolen >= 2:
				break
			if str(it.get("legend", "")) == "":
				GameState.remove_item(int(it["uid"]))
				stolen += 1
		Village.change_prosperity(-12)
		Village.change_safety(-10)
		lines.append("[color=#e06c6c][b]The raid broke through.[/b] Monsters looted the village: you lost %dg and %d items from your shelf.[/color]" % [lost_gold, stolen])
		Chronicle.add("A raid from the %s broke into the village." % d["name"], "death")
		if not defenders.is_empty() and randf() < 0.5:
			var victim: Dictionary = defenders.pick_random()
			AdventurerManager._kill(victim, d, "raiders")
			lines.append("[color=#e06c6c]%s died defending the gate.[/color]" % victim["name"])
	Dungeons.after_raid(id)
	raid = {}
	return lines


## The treasure-map vault expedition, delved by the map's finder for you.
func resolve_vault(day: int) -> Array:
	if vault.is_empty() or int(vault["day"]) != day:
		return []
	var adv := AdventurerManager.get_adv(int(vault["hero"]))
	vault = {}
	if adv.is_empty() or not adv["alive"]:
		return ["[color=#9a8f86]Nobody went to the sunken vault.[/color]"]
	var chance := clampf(AdventurerManager.power(adv) / 40.0 - 0.1, 0.2, 0.9)
	if randf() < chance:
		var rare: Array = DataDB.materials.keys().filter(func(m): return not DataDB.materials[m]["buyable"] and not DataDB.materials[m].get("trophy", false))
		var got: PackedStringArray = []
		for i in randi_range(3, 5):
			var m: String = rare.pick_random()
			GameState.add_material(m, 1)
			got.append(DataDB.material_name(m))
		var text := "[color=#ffc94a]%s delved the sunken vault for you and brought back: %s.[/color]" % [adv["name"], ", ".join(got)]
		if randf() < 0.35:
			var unknown: Array = DataDB.recipes.keys().filter(func(r): return DataDB.recipes[r].get("blueprint", false) and not r in GameState.known_blueprints)
			if not unknown.is_empty():
				var bp: String = unknown.pick_random()
				GameState.learn_blueprint(bp, "found in a sunken vault")
				text += " [color=#c77dff]And a schematic: %s![/color]" % DataDB.recipes[bp]["name"]
		AdventurerManager.change_loyalty(adv, 8)
		Chronicle.add("%s plundered a sunken vault on your behalf." % adv["name"], "hero")
		return [text]
	adv["injured_until"] = day + 1
	return ["[color=#e0b06c]%s found the sunken vault flooded and trapped, and came back empty-handed and hurt.[/color]" % adv["name"]]


func to_dict() -> Dictionary:
	return { "pending": pending, "news": news, "last": last, "next_id": next_id, "raid": raid, "vault": vault }


func from_dict(d: Dictionary) -> void:
	reset()
	pending = d.get("pending", [])
	news = d.get("news", [])
	last = d.get("last", {})
	next_id = int(d.get("next_id", 1))
	raid = d.get("raid", {})
	vault = d.get("vault", {})
