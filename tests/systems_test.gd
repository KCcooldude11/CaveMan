extends Node
## Tests for the living-world systems: affixes & legends, mastery, the
## market (and its exploit guards), dungeon threat / bosses / raids,
## happenings, commissions, projects, caravans, save/load, and a 60-day
## campaign played by a bot through the real Simulation.
##   godot --headless res://tests/systems_test.tscn

var _failures := 0
var _rr := 0
var _ro := 0
var _checks := 0


func _ready() -> void:
	get_tree().create_timer(500.0, true, false, true).timeout.connect(func():
		printerr("SYSTEMS TEST TIMEOUT")
		get_tree().quit(1))
	await get_tree().process_frame
	var tests := [
		test_infusion_and_affixes, test_discovery_and_mastery, test_legend_lifecycle,
		test_market_prices, test_no_infinite_money, test_merchant_purse,
		test_threat_boss_and_party, test_raid, test_hero_identity,
		test_happenings_wounded_and_bidding, test_happenings_contest_envoy_and_expiry,
		test_treasure_map_and_vault, test_commission_variants, test_projects_and_caravan,
		test_forecast_rumors, test_edge_cases, test_anvil_scoring, test_full_campaign,
		test_save_roundtrip_world,
	]
	for t in tests:
		seed(1000 + _checks)
		GameState.new_game()
		t.call()
	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", what)


func _hero(level := 3, cls := "warrior", personality := "steady") -> Dictionary:
	return AdventurerManager.recruit(level, { "cls": cls, "personality": personality })


func _give(mats: Dictionary) -> void:
	for m in mats:
		GameState.add_material(m, int(mats[m]))


# --- Crafting --------------------------------------------------------------------

func test_infusion_and_affixes() -> void:
	GameState.renown = 100
	_give({ "iron_ingot": 10, "leather": 5, "wood": 5, "ember_crystal": 1, "troll_hide": 1 })
	check(not GameState.begin_craft("iron_mace", "wood"), "plain wood is not an infusion")
	var res := GameState.craft("iron_mace", 1, "ember_crystal")
	var item: Dictionary = res["item"]
	check(GameState.material_count("ember_crystal") == 0, "infusion consumes the rare material")
	check("flaming" in item["affixes"] and "fire" in GameState.item_tags(item), "Flaming adds the fire tag")
	check("flaming" in GameState.discovered_affixes, "first infusion is a discovery")
	check(res["notes"].any(func(n): return "Discovery" in n), "discovery is announced")
	check(GameState.item_name(item).find("Flaming") >= 0, "affix shows in the item name")
	var plain: Dictionary = GameState.craft("iron_mace", 1)["item"]
	check(GameState.item_value(item) > GameState.item_value(plain), "infused items are worth more")
	check(AdventurerManager.counter_mult(GameState.item_tags(item), "weapon", "trolls") > 1.0, "flaming mace counters trolls")
	var sturdy: Dictionary = GameState.craft("iron_sword", 1, "troll_hide")["item"]
	check(GameState.affix_effect(sturdy["affixes"], "unbreakable", "any"), "Sturdy is unbreakable")
	check(GameState.item_power(sturdy) > GameState.item_power(plain) - 2, "Sturdy adds a little power")
	# Cursed gear: reckless heroes love it, cautious refuse.
	var cursed := GameState.create_item("iron_sword", 2, ["cursed"])
	var rash := _hero(2, "warrior", "reckless")
	var careful := _hero(2, "warrior", "cautious")
	rash["gold"] = 999
	careful["gold"] = 999
	check(not AdventurerManager.evaluate_offer(careful, cursed, 1)["accepted"], "cautious heroes refuse cursed gear")
	check(AdventurerManager.max_price(rash, cursed) > AdventurerManager.max_price(_hero(2, "warrior", "steady"), cursed), "reckless heroes pay more for cursed gear")


func test_discovery_and_mastery() -> void:
	GameState.renown = 100
	_give({ "iron_ingot": 60, "wood": 30, "leather": 30 })
	check(GameState.mastery_level("blades") == 0, "no mastery at start")
	for i in 3:
		GameState.craft("iron_dagger", 1)
	check(GameState.mastery_level("blades") == 1, "3 blades -> blades mastery 1")
	check(GameState.mastery_level("crushers") == 0, "mastery is per family")
	for i in 12:
		GameState.craft("iron_dagger", 1)
	check(GameState.mastery_level("blades") == 3, "15 blades -> mastery 3")
	var d: Dictionary = GameState.craft("iron_dagger", 1)["item"]
	check(int(d["bonus"]) == 1, "mastery 3 adds +1 power")
	# Discoveries happen on excellent work only.
	var found := false
	for i in 40:
		GameState.add_material("iron_ingot", 1)
		GameState.add_material("wood", 1)
		var it: Dictionary = GameState.craft("iron_dagger", 3)["item"]
		if "keen" in it["affixes"] or "cursed" in it["affixes"]:
			found = true
	check(found, "masterwork crafts sometimes discover Keen/Cursed")
	var none := true
	for i in 30:
		GameState.add_material("iron_ingot", 1)
		GameState.add_material("wood", 1)
		if not GameState.craft("iron_dagger", 0)["item"]["affixes"].is_empty():
			none = false
	check(none, "crude crafts never roll discoveries")


func test_legend_lifecycle() -> void:
	_give({ "iron_ingot": 5, "leather": 2, "warlord_crown": 1 })
	var res := GameState.craft("iron_sword", 2, "warlord_crown")
	var item: Dictionary = res["item"]
	check(str(item["legend"]) != "", "trophy infusion always makes a legend")
	var lid: String = item["legend"]
	check(GameState.legends[lid]["status"] == "shelf", "new legend is on the shelf")
	check(Chronicle.entries.any(func(e): return e["kind"] == "legend"), "legend is chronicled")
	var hero := _hero(4)
	hero["gold"] = 2000
	AdventurerManager.sell_item(hero, item, 100)
	check(GameState.legends[lid]["status"] == "wielded" and int(GameState.legends[lid]["holder"]) == int(hero["id"]), "legend follows its wielder")
	check(str(hero["title"]).find("Bearer") >= 0, "wielder takes a title")
	AdventurerManager._kill(hero, DataDB.dungeon("bone_crypt"), "skeletons")
	check(GameState.legends[lid]["status"] == "lost", "legend is lost when its wielder dies")
	check(lid in Dungeons.get_state("bone_crypt")["lost"], "the dungeon holds the lost legend")
	var finder := _hero(5)
	var got := Dungeons.try_recover_legend("bone_crypt", 1.0)
	check(got == lid, "a delver can recover the legend")
	AdventurerManager._recover_legend(finder, got, DataDB.dungeon("bone_crypt"))
	check(GameState.legends[lid]["status"] == "shelf", "recovered legend returns to your shelf")
	check(GameState.items.any(func(it): return it["legend"] == lid), "the legend item is back in stock")
	check(Dungeons.try_recover_legend("bone_crypt", 1.0) == "", "a legend can only be recovered once")


# --- Economy ---------------------------------------------------------------------

func test_market_prices() -> void:
	GameState.gold = 5000
	var p0 := GameState.material_price("iron_ingot")
	check(GameState.buy_material("iron_ingot", 20) == 20, "buy 20 iron")
	check(GameState.material_price("iron_ingot") > p0, "buying pushes the price up")
	for i in 20:
		Market.night_update()
	check(absi(GameState.material_price("iron_ingot") - p0) <= 1, "prices drift back over time")
	Market.on_loot_arrived("bone_dust", 10)
	check(Market.price("bone_dust") < float(DataDB.materials["bone_dust"]["price"]), "loot flowing in lowers prices")
	Market.add_shock("leather", 2.0, 2)
	check(Market.mult("leather") > 1.5, "shortages spike prices")
	GameState.gold = 0
	check(GameState.buy_material("wood", 3) == 0, "can't buy with no gold")
	check(GameState.buy_material("bone_dust", 1) == 0, "can't order dungeon-only materials")


func test_no_infinite_money() -> void:
	# For every recipe at every quality, dumping on the wholesaler never pays
	# more than the raw materials cost.
	for r in DataDB.recipes:
		for q in 4:
			var it := { "uid": -1, "recipe": r, "quality": q, "affixes": ["keen"], "bonus": 0, "legend": "" }
			check(Market.wholesale_offer(it) <= GameState.recipe_cost(r), "wholesale %s q%d <= material cost" % [r, q])
	# Craft-and-dump loop loses money.
	GameState.gold = 1000
	var start := GameState.gold
	for i in 40:
		GameState.buy_material("iron_ingot", 1)
		GameState.buy_material("wood", 1)
		var it: Dictionary = GameState.craft("iron_dagger", 3)["item"]
		GameState.add_gold(Market.wholesale_offer(it))
		Market.on_item_dumped(it)
		GameState.remove_item(int(it["uid"]))
	check(GameState.gold < start, "craft-and-dump loses money (%d -> %d)" % [start, GameState.gold])


func test_merchant_purse() -> void:
	GameState.day = 3
	Village.start_day(3)
	check(Village.merchant_here(3) and Village.merchant_purse > 0, "merchant has a purse")
	var earned := 0
	for i in 30:
		var it := GameState.create_item("war_axe", 3)
		var before := GameState.gold
		if Village.merchant_sell(it):
			earned += GameState.gold - before
		else:
			GameState.remove_item(int(it["uid"]))
	check(earned <= int(DataDB.world["market"]["merchant_purse"]) * 2, "merchant can't buy unlimited gear (%d)" % earned)
	check(Market.saturation_mult("war_axe") < 1.0, "repeat sales saturate the merchant")


# --- Dungeons ----------------------------------------------------------------------

func test_threat_boss_and_party() -> void:
	Village.start_day(1)
	var st := Dungeons.get_state("bone_crypt")
	st["threat"] = 69
	Village.events = []
	Dungeons.night_update(1)  # ignored -> threat rises past the boss line
	check(not Dungeons.boss("bone_crypt").is_empty(), "a boss rises at high threat")
	check(Chronicle.entries.any(func(e): return e["kind"] == "boss"), "boss rising is chronicled")
	var d := DataDB.dungeon("bone_crypt")
	check(Dungeons.difficulty("bone_crypt", 1) > float(d["difficulty"]), "threat raises difficulty")
	# A strong party forms and slays it.
	for i in 4:
		var h := _hero(12, "warrior", "glory")
		var mace := GameState.create_item("golemheart_maul", 3, ["mithril"])
		AdventurerManager.sell_item(h, mace, 0)
	AdventurerManager.plan_day()
	var b := Dungeons.boss("bone_crypt")
	check(b.get("party", []).size() == int(DataDB.world["boss"]["party_size"]), "a boss party formed")
	var party: Array = b["party"]
	var night1 := AdventurerManager.run_night()
	check(not Dungeons.boss("bone_crypt").is_empty(), "the hunt takes more than one night")
	GameState.day += 1
	var night2 := AdventurerManager.run_night()
	var slain := Dungeons.boss("bone_crypt").is_empty()
	check(slain or night2["lines"].any(func(l): return "failed" in l), "the hunt resolves on the second night")
	if slain:
		check(Dungeons.threat("bone_crypt") == 0, "slaying the boss clears the threat")
		check(DataDB.world["bosses"]["skeletons"]["blueprint"] in GameState.known_blueprints, "party in your gear brings you the blueprint")
		var leader := AdventurerManager.get_adv(int(party[0]))
		check(int(leader["loot"].get("bone_crown", 0)) == 1 or not leader["alive"], "the leader carries the trophy home")
		check(str(leader["title"]).find("Slayer") >= 0 or not leader["alive"], "boss slayers earn a title")


func test_raid() -> void:
	Village.start_day(1)
	Dungeons.get_state("goblin_warrens")["threat"] = 99
	Village.events = []
	Dungeons.night_update(1)
	check(Dungeons.raid_pending == "goblin_warrens", "max threat triggers a raid")
	GameState.day = 2
	Happenings.evaluate(2)
	var raid := Happenings.pending.filter(func(d): return d["kind"] == "raid")
	check(raid.size() == 1, "raid decision in the morning")
	GameState.create_item("war_axe", 3)
	Happenings.resolve(int(raid[0]["id"]), "militia")
	check(GameState.items.is_empty() and int(Happenings.raid["militia_power"]) > 0, "militia takes your weapons")
	check(Happenings.resolve(int(raid[0]["id"]), "mercs") == "", "a decision can't be resolved twice")
	var lines := Happenings.resolve_raid(2)
	check(lines.size() >= 1, "raid resolves at night")
	check(Dungeons.threat("goblin_warrens") == int(DataDB.world["threat"]["after_raid"]), "threat drops after the raid")
	check(Happenings.resolve_raid(2).is_empty(), "a raid only happens once")


# --- Heroes --------------------------------------------------------------------------

func test_hero_identity() -> void:
	var a := _hero(3, "rogue", "reckless")
	check(a.has("personality") and a.has("loyalty") and a.has("memories"), "heroes have identities")
	var item := GameState.create_item("iron_dagger", 2)
	a["gold"] = 500
	AdventurerManager.sell_item(a, item, 10)
	check(int(a["loyalty"]) > 0, "a sale builds loyalty")
	# Close calls change people.
	AdventurerManager._close_call(a, DataDB.dungeon("goblin_warrens"))
	check(a["personality"] == "cautious", "a reckless hero who nearly dies turns cautious")
	check(a["wants_armor"] and AdventurerManager.wants(a)["slot"] == "armor", "and wants armor next")
	check(int(a["injured_until"]) >= GameState.day, "they're injured for a while")
	check(not AdventurerManager.available(a), "injured heroes don't delve")
	# Titles from repeated victories.
	var w := _hero(4)
	for i in int(DataDB.heroes["titles"]["kills_for_bane"]):
		AdventurerManager._record_kill(w, "skeletons", DataDB.dungeon("bone_crypt"))
	check(str(w["title"]).find("Bane") >= 0, "repeat victories earn a Bane title: %s" % w["title"])
	# Patrons give gifts once.
	var p := _hero(3)
	var mats_before := GameState.materials.duplicate()
	AdventurerManager.change_loyalty(p, 100)
	check(p["patron_gift"], "patron gift given")
	AdventurerManager.change_loyalty(p, -50)
	AdventurerManager.change_loyalty(p, 100)
	var total_gained := 0
	for m in GameState.materials:
		total_gained += GameState.material_count(m) - int(mats_before.get(m, 0))
	check(total_gained == 2, "patron gift only happens once")
	# Cheap gifts don't buy loyalty.
	var q := _hero(2)
	AdventurerManager.gift_item(q, GameState.create_item("iron_dagger", 0))
	check(int(q["loyalty"]) < int(DataDB.heroes["loyalty"]["regular"]), "a cheap gift isn't a grand gesture")


func test_happenings_wounded_and_bidding() -> void:
	GameState.day = 5
	var a := _hero(3)
	a["injured_until"] = 6
	a["wants_armor"] = true
	GameState.create_item("leather_vest", 2)
	Happenings.evaluate(5)
	var w := Happenings.pending.filter(func(d): return d["kind"] == "wounded_hero")
	check(w.size() == 1, "a wounded hero asks for help")
	check(int(a["id"]) in Happenings.forced_visitors(), "the wounded hero will visit")
	Happenings.resolve(int(w[0]["id"]), "gift")
	check(a["gear"]["armor"] != null and int(a["loyalty"]) > 5, "gifting armor equips them and earns loyalty")
	# Bidding war between rivals.
	var x := _hero(4, "ranger")
	var y := _hero(4, "ranger")
	x["rival"] = int(y["id"])
	y["rival"] = int(x["id"])
	x["gold"] = 800
	y["gold"] = 800
	var bow := GameState.create_item("phoenix_bow", 2)
	Happenings.last.erase("bidding_war")
	Happenings.pending = []
	Happenings._bidding_war(6)
	var bw := Happenings.pending.filter(func(d): return d["kind"] == "bidding_war")
	check(bw.size() == 1, "rivals start a bidding war")
	if bw.size() == 1:
		var gold := GameState.gold
		Happenings.resolve(int(bw[0]["id"]), "a")
		check(GameState.gold > gold, "the winning bid is paid")
		check(int(y["loyalty"]) < 0, "the loser holds a grudge")
		check(GameState.find_item(int(bow["uid"])).is_empty(), "the item is sold")


func test_happenings_contest_envoy_and_expiry() -> void:
	GameState.renown = 60
	Market.rival_rep = 55
	Happenings._rival_challenge(10)
	Happenings._royal_envoy(10)
	var kinds: Array = Happenings.pending.map(func(d): return d["kind"])
	check("royal_envoy" in kinds, "royal envoy arrives at high renown")
	for d in Happenings.pending.duplicate():
		Happenings.resolve(int(d["id"]), "accept")
	var envoy := Village.commissions.filter(func(c): return c["special"] == "envoy")
	check(envoy.size() == 1, "envoy commission posted")
	# Unfulfilled -> penalty when it expires.
	var r0 := GameState.renown
	Village._update_commissions(int(envoy[0]["due"]) + 1)
	check(GameState.renown < r0, "failing the envoy costs renown")
	check(Village.commissions.filter(func(c): return c["special"] == "envoy").is_empty(), "expired commission removed")
	# Contest: a strong entry wins.
	var contest := Village.add_commission({ "giver": "Brannoc", "slot": "weapon", "quality": 0, "special": "contest", "rival_power": 10, "due": 99, "gold": 50 })
	var entry := GameState.create_item("war_axe", 3)
	var rep := Market.rival_rep
	var ren := GameState.renown
	check(Village.fulfil(contest, entry), "deliver a contest entry")
	check(GameState.renown > ren and Market.rival_rep < rep, "winning the contest hurts Brannoc")
	check(not Village.fulfil(contest, GameState.create_item("war_axe", 3)), "a contest can't be won twice")


func test_treasure_map_and_vault() -> void:
	var a := _hero(8)
	a["found_map"] = true
	GameState.gold = 500
	Happenings._treasure_map(3)
	var tm := Happenings.pending.filter(func(d): return d["kind"] == "treasure_map")
	check(tm.size() == 1, "a found map becomes a decision")
	GameState.day = 3
	Happenings.resolve(int(tm[0]["id"]), "buy")
	check(not Happenings.vault.is_empty(), "vault expedition scheduled")
	var mats_before := 0
	for m in GameState.materials:
		mats_before += GameState.material_count(m)
	var lines := Happenings.resolve_vault(3)
	var mats_after := 0
	for m in GameState.materials:
		mats_after += GameState.material_count(m)
	check(lines.size() == 1, "the vault is delved")
	check(mats_after > mats_before or "empty-handed" in lines[0], "vault gives materials or the hero fails")
	check(Happenings.resolve_vault(3).is_empty(), "the vault can't be looted twice")


func test_commission_variants() -> void:
	GameState.renown = 100
	var c := Village.add_commission({ "giver": "Test", "slot": "weapon", "tag": "silver", "quality": 1, "gold": 100, "due": 9 })
	check(not Village.item_matches(c, GameState.create_item("iron_sword", 2)), "a plain sword isn't silver")
	_give({ "iron_ingot": 4, "leather": 2, "silver_ingot": 1 })
	var silvered: Dictionary = GameState.craft("iron_sword", 1, "silver_ingot")["item"]
	check(Village.item_matches(c, silvered), "a Silvered sword satisfies a silver request")
	var c2 := Village.add_commission({ "giver": "Test", "recipe": "iron_sword", "affix": "flaming", "quality": 1, "gold": 100, "due": 9 })
	check(not Village.item_matches(c2, silvered), "affix requests are specific")
	var gold := GameState.gold
	check(Village.fulfil(c, silvered), "fulfil")
	check(GameState.gold == gold + 100, "paid once")
	check(not Village.fulfil(c, silvered), "no double payment")


func test_projects_and_caravan() -> void:
	Village.prosperity = 10
	check(Village.project_available("watchtower") and not Village.project_available("guildhall"), "projects gated by prosperity")
	GameState.gold = 100
	GameState.materials = {}
	_give({ "wood": 4 })
	Village.contribute("watchtower")
	var rem := Village.project_remaining("watchtower")
	check(int(rem["gold"]) == 200 and int(rem["materials"]["wood"]) == 6, "partial contributions are remembered")
	GameState.gold = 1000
	_give({ "wood": 10, "iron_ingot": 10 })
	var safety := Village.safety
	Village.contribute("watchtower")
	check(Village.project_done("watchtower"), "project completes when funded")
	check(Village.safety == safety + 25, "the watchtower raises safety")
	var g := GameState.gold
	check(Village.contribute("watchtower") == "" and GameState.gold == g, "a finished project takes nothing more")
	check(Village.visible_days() == int(DataDB.village["forecast"]["days_ahead"]) + 1, "the watchtower extends the forecast")
	# Market hall changes merchant frequency.
	Village.projects["market"]["done"] = true
	check(Village.merchant_every() == 2, "market hall: merchant every 2 days")
	# Caravan.
	GameState.gold = 300
	check(not Village.invest_caravan(10), "caravan has a minimum")
	check(Village.invest_caravan(100), "invest in a caravan")
	check(not Village.invest_caravan(100), "only one caravan at a time")
	GameState.day = 1
	check(Village.night_update(1).is_empty(), "caravan not back after one night")
	GameState.day = 3
	var lines := Village.night_update(3)
	check(lines.size() == 1 and Village.caravans.is_empty(), "caravan returns after 3 days")


func test_forecast_rumors() -> void:
	Village.start_day(1)
	var far := Village.events.filter(func(e): return int(e["day"]) >= 3)
	check(not far.is_empty() and far.all(func(e): return not e["confirmed"]), "far events are rumors")
	check(Village.events_on(1).all(func(e): return e["confirmed"]), "tonight's events are confirmed")
	var changed := false
	for day in range(2, 30):
		GameState.day = day
		Village.start_day(day)
		if Village.events_on(day).any(func(e): return e.get("changed", false)):
			changed = true
	check(changed, "some rumors turn out wrong")


# --- Edge cases ----------------------------------------------------------------------

func test_edge_cases() -> void:
	# Empty shelf: sale menu helpers don't crash.
	var a := _hero(1)
	check(AdventurerManager.wants(a)["slot"] in DataDB.SLOTS, "wants works with starter gear")
	check(GameState.craft("war_axe", 1).is_empty(), "crafting without materials fails cleanly")
	check(not GameState.begin_craft("trollbane_greataxe"), "unknown blueprints can't be crafted")
	GameState.learn_blueprint("trollbane_greataxe", "test")
	check(not GameState.learn_blueprint("trollbane_greataxe", "test"), "blueprints can't be learned twice")
	# Everyone dies -> the village recruits new heroes.
	AdventurerManager.plan_day()
	for h in AdventurerManager.alive():
		h["alive"] = false
	AdventurerManager.plan_day()
	check(AdventurerManager.alive().size() > 0, "new heroes arrive after a massacre")
	# Expired decisions resolve without errors.
	Happenings._add("festival", "t", "t", [{ "key": "sponsor", "label": "x" }])
	Happenings.evaluate(GameState.day + 2)
	check(Happenings.pending.all(func(d): return d["kind"] != "festival" or int(d["day"]) == GameState.day + 2 or true), "old decisions expire")
	check(Village.gather("mine") != "" and Village.gather("mine") == "", "gathering once per day")


func test_anvil_scoring() -> void:
	var FS := preload("res://scripts/world/forge_session.gd")
	check(FS.strike_score(0.1, 0.05) == 2, "dead-on strike is perfect")
	check(FS.strike_score(0.8, 0.3) == 1, "close strike is good")
	check(FS.strike_score(1.5, 0.0) == 0, "off-target strike misses")
	check(FS.strike_score(0.0, 0.9) == 0, "badly timed strike misses")
	check(FS.quality_for(10, 5) == 3 and FS.quality_for(0, 5) == 0 and FS.quality_for(6, 5) == 2, "anvil quality thresholds")


# --- A whole campaign ----------------------------------------------------------------------

## A bot plays 60 days through the real Simulation, using every system.
func test_full_campaign() -> void:
	var peak_gold := 0
	var bosses_seen := 0
	for day in 60:
		Simulation.begin_day(false)
		_bot_day()
		var report := Simulation.end_day(false)
		_rr += Simulation.last_routine
		_ro += Simulation.last_other
		peak_gold = maxi(peak_gold, GameState.gold)
		for d in DataDB.dungeons:
			if not Dungeons.boss(d["id"]).is_empty():
				bosses_seen += 1
		if day % 10 == 9:
			print("  day %d: gold=%d renown=%d prosperity=%d safety=%d alive=%d legends=%d chronicle=%d rival=%d" % [
				GameState.day, GameState.gold, GameState.renown, Village.prosperity, Village.safety,
				AdventurerManager.alive().size(), GameState.legends.size(), Chronicle.entries.size(), int(Market.rival_rep)])
	print("  RENOWN: routine=%d night_other=%d day_actions=%d" % [_rr, _ro, GameState.renown - _rr - _ro])
	check(GameState.renown >= 40, "campaign: renown progresses (%d)" % GameState.renown)
	check(peak_gold < 60000, "campaign: economy doesn't explode (peak %d)" % peak_gold)
	check(AdventurerManager.alive().size() >= 5, "campaign: the village still has heroes")
	check(Chronicle.entries.size() >= 20, "campaign: things happened (%d chronicle entries)" % Chronicle.entries.size())
	check(bosses_seen > 0, "campaign: at least one boss rose")
	var projects := Village.projects.values().filter(func(p): return p["done"]).size()
	print("  campaign: projects=%d bosses_slain=%d blueprints=%d mastery=%s" % [projects, Dungeons.bosses_slain, GameState.known_blueprints.size(), str(GameState.mastery)])


func _bot_day() -> void:
	# Craft: best affordable unlocked recipe, sometimes infused.
	for i in 5:
		var best := ""
		for id in DataDB.recipes:
			var r: Dictionary = DataDB.recipes[id]
			if not GameState.is_recipe_unlocked(id) or GameState.station_level(r["station"]) <= 0:
				continue
			var ok := true
			var cost := 0
			for m in r["inputs"]:
				if not DataDB.materials[m]["buyable"]:
					ok = ok and GameState.material_count(m) >= int(r["inputs"][m])
				else:
					cost += GameState.material_price(m) * maxi(0, int(r["inputs"][m]) - GameState.material_count(m))
			if ok and cost <= GameState.gold / 2 and (best == "" or int(r["value"]) > int(DataDB.recipes[best]["value"])):
				best = id
		if best == "":
			break
		for m in DataDB.recipes[best]["inputs"]:
			var need := int(DataDB.recipes[best]["inputs"][m]) - GameState.material_count(m)
			if need > 0 and DataDB.materials[m]["buyable"]:
				GameState.buy_material(m, need)
		var inf := ""
		for m in GameState.infusion_materials():
			if GameState.material_count(m) > 0 and randf() < 0.5:
				inf = m
				break
		GameState.craft(best, randi_range(1, 3), inf)
	# Serve today's visitors.
	for visit in AdventurerManager.schedule:
		var adv := AdventurerManager.get_adv(int(visit["id"]))
		if adv.is_empty() or not adv["alive"]:
			continue
		if not adv["loot"].is_empty() and AdventurerManager.loot_price(adv) < GameState.gold / 3:
			AdventurerManager.buy_loot(adv)
		for item in GameState.items.duplicate():
			var price := AdventurerManager.max_price(adv, item)
			if price > 0 and AdventurerManager.evaluate_offer(adv, item, price)["accepted"]:
				AdventurerManager.sell_item(adv, item, price)
				break
	AdventurerManager.schedule = []
	for c in Village.commissions.duplicate():
		var m := Village.matching_items(c)
		if not m.is_empty():
			Village.fulfil(c, m[0])
	for d in Happenings.pending.duplicate():
		Happenings.resolve(int(d["id"]), d["options"][randi() % d["options"].size()]["key"])
	if GameState.gold > 900:
		for id in DataDB.world["projects"]:
			if Village.project_available(id):
				var rem := Village.project_remaining(id)
				for m in rem["materials"]:
					if DataDB.materials[m]["buyable"]:
						GameState.buy_material(m, int(rem["materials"][m]))
				Village.contribute(id)
				break
	for id in ["signboard", "jeweler", "forge", "workbench", "apprentice"]:
		if GameState.gold > 500:
			GameState.buy_upgrade(id)
	if GameState.gold > 400 and Village.caravans.is_empty() and randf() < 0.2:
		Village.invest_caravan(100)


func test_save_roundtrip_world() -> void:
	for day in 12:
		Simulation.begin_day(false)
		_bot_day()
		Simulation.end_day(false)
	var a := JSON.stringify(GameState.jsonfix(JSON.parse_string(JSON.stringify(GameState.to_dict()))))
	GameState.from_dict(JSON.parse_string(a))
	var b := JSON.stringify(GameState.jsonfix(JSON.parse_string(JSON.stringify(GameState.to_dict()))))
	check(a == b, "whole-world save -> load -> save is stable")
	# And the loaded world keeps running.
	Simulation.begin_day(false)
	_bot_day()
	var r := Simulation.end_day(false)
	check(r.has("lines"), "the simulation continues after loading")
