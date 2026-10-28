extends BaseMenu
## Haggling with a hero at the counter. Shows who they are (personality,
## loyalty, what they remember about you), where they're going tonight and
## exactly why each item on your shelf would or wouldn't help them.

const MAX_REFUSALS := 3

var npc: Node
var adv: Dictionary
var _selected: Dictionary = {}
var _price: SpinBox
var _reply: RichTextLabel
var _refusals := 0
var _bought := false


func _init(customer: Node) -> void:
	npc = customer
	adv = customer.adv
	super("Customer")


func build() -> void:
	title_label.text = AdventurerManager.title(adv)
	var w := AdventurerManager.wants(adv)
	var p := AdventurerManager.personality_of(adv)
	add_rich("[b]%s[/b] [color=#b8b0a0](%s)[/color]   %s   Purse [color=#ffd27a]%dg[/color]   Power %d   Wants: [b]%s[/b]%s" % [
		p["name"], p["desc"], AdventurerManager.loyalty_label(adv), int(adv["gold"]), int(AdventurerManager.power(adv)), w["slot"],
		"   [color=#c77dff]Legendary hero: only Fine work or better will do[/color]" if adv.get("legendary", false) else ""])
	if not adv["memories"].is_empty():
		add_rich("[color=#9a8f86][i]\"%s\"[/i][/color]" % str(adv["memories"][-1]).split(": ", true, 1)[-1])
	if w["boss"]:
		var b := Dungeons.boss(str(adv["plan"]).trim_prefix("boss:"))
		add_rich("[color=#ff9a6a][b]Hunting %s[/b] with a party. They'll pay a premium for the right gear.[/color]" % b.get("name", "a boss"))
	if w["enemy"] != "":
		var e: Dictionary = DataDB.enemies[w["enemy"]]
		var plan_d := DataDB.dungeon(str(adv["plan"]).trim_prefix("boss:"))
		var mod := AdventurerManager.planned_mod(adv)
		add_rich("Tonight: [b]%s[/b] vs the [b]%s[/b]%s. [color=#e06c6c]Weak to: %s[/color]" % [
			plan_d["name"], e["name"], " [color=#c77dff](%s: %s)[/color]" % [mod["name"], mod["desc"]] if not mod.is_empty() else "", ", ".join(e["weak"])])
	var gear: PackedStringArray = []
	for slot in DataDB.SLOTS:
		var g = adv["gear"][slot]
		if g == null:
			gear.append("%s: [color=#777]none[/color]" % slot)
		else:
			var mark := " [color=#ffc94a]*yours*[/color]" if g["player_made"] else (" [color=#9a8f86](Brannoc's)[/color]" if g.get("rival_made", false) else "")
			gear.append("%s: %s (%d)%s" % [slot, g["name"], int(g["power"]), mark])
	add_rich("Wearing: " + "   ".join(gear))

	if not adv["loot"].is_empty():
		var lp := AdventurerManager.loot_price(adv)
		var loot: PackedStringArray = []
		for m in adv["loot"]:
			loot.append("%dx %s" % [int(adv["loot"][m]), DataDB.material_name(m)])
		add_row("[color=#9fd8ff]Selling dungeon loot:[/color] %s for %dg%s" % [", ".join(loot), lp,
			" [color=#8fd18f](regular's discount)[/color]" if int(adv["loyalty"]) >= int(DataDB.heroes["loyalty"]["regular"]) else ""],
			[button("Buy loot", _buy_loot, GameState.gold < lp)])

	add_heading("Your shelf")
	if GameState.items.is_empty():
		add_label("You have nothing to sell. Craft something first!", 16, Color("e0b06c"))
	var sorted := GameState.items.duplicate()
	sorted.sort_custom(func(a, b): return _appeal(a) > _appeal(b))
	for item in sorted:
		var q: Dictionary = DataDB.QUALITIES[int(item["quality"])]
		var col := "ffc94a" if str(item.get("legend", "")) != "" else hex(q["color"])
		var sel := "  [b]<[/b]" if not _selected.is_empty() and int(_selected["uid"]) == int(item["uid"]) else ""
		add_row("[color=#%s]%s[/color]  [color=#b8b0a0]%s, power %d, fair %dg[/color]%s\n    %s" % [
			col, GameState.item_name(item), GameState.item_slot(item), GameState.item_power(item),
			GameState.item_value(item), sel, "  ".join(AdventurerManager.item_reasons(adv, item))],
			[button("Select", _select.bind(item))])

	add_heading("Offer")
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Price (g): "
	row.add_child(lbl)
	_price = SpinBox.new()
	_price.min_value = 1
	_price.max_value = 99999
	_price.value = GameState.item_value(_selected) if not _selected.is_empty() else 10
	_price.editable = not _selected.is_empty()
	row.add_child(_price)
	row.add_child(button("Make offer", _offer, _selected.is_empty()))
	row.add_child(button("Give it free", _gift, _selected.is_empty()))
	row.add_child(button("Nothing today", _dismiss))
	content.add_child(row)
	_reply = add_rich("")
	if not GameState.items.is_empty() and _selected.is_empty():
		_reply.text = "[color=#b8b0a0]Items are sorted by how much they'd help %s tonight.[/color]" % adv["name"]


## Rough "how good a fit is this" score for sorting the shelf.
func _appeal(item: Dictionary) -> float:
	var slot := GameState.item_slot(item)
	var tags := GameState.item_tags(item)
	var enemy := AdventurerManager.planned_enemy(adv)
	var cur = adv["gear"][slot]
	var gain := AdventurerManager.gear_power_for(adv, GameState.item_power(item), tags, slot, enemy, AdventurerManager.planned_mod(adv))
	gain -= 0.0 if cur == null else AdventurerManager.gear_power_for(adv, int(cur["power"]), cur["tags"], slot, enemy, AdventurerManager.planned_mod(adv))
	if GameState.item_value(item) > int(adv["gold"]):
		gain -= 50.0
	return gain


func _select(item: Dictionary) -> void:
	_selected = item
	refresh()


func _offer() -> void:
	if _selected.is_empty():
		return
	var price := int(_price.value)
	if adv.get("legendary", false) and int(_selected["quality"]) < 2:
		_reply.text = "[color=#e0b06c]\"Common work? I've broken better on goblin skulls.\"[/color]"
		_refusals += 1
		return
	var res := AdventurerManager.evaluate_offer(adv, _selected, price)
	if res["accepted"]:
		var item_label := GameState.item_name(_selected)
		AdventurerManager.sell_item(adv, _selected, price)
		_bought = true
		EventBus.notify.emit("Sold %s to %s for %dg!" % [item_label, adv["name"], price])
		EventBus.sold.emit(price)
		close()
		return
	_refusals += int(res["patience"])
	_reply.text = "[color=#e0b06c]\"%s\"[/color]" % res["reason"]
	if _refusals >= MAX_REFUSALS:
		EventBus.notify.emit("%s lost patience and left." % adv["name"])
		close()


func _gift() -> void:
	if _selected.is_empty():
		return
	var item_label := GameState.item_name(_selected)
	AdventurerManager.gift_item(adv, _selected)
	_bought = true
	EventBus.notify.emit("You gave %s to %s. They're touched." % [item_label, adv["name"]])
	close()


func _buy_loot() -> void:
	if AdventurerManager.buy_loot(adv):
		EventBus.notify.emit("Bought dungeon loot from %s." % adv["name"])
	refresh()


func _dismiss() -> void:
	close()


func close() -> void:
	ui.shop_node().finish_service(npc, _bought)
	super()
