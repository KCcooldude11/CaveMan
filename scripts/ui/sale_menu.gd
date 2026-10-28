extends BaseMenu
## Haggling with an adventurer at the counter.

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
	add_rich("Purse: [color=#ffd27a]%dg[/color]   Power: %d   Looking for: [b]%s[/b]" % [
		int(adv["gold"]), int(AdventurerManager.power(adv)), w["slot"]])
	add_rich("Likes gear that is: [i]%s[/i]" % ", ".join(DataDB.classes[adv["cls"]]["likes"]))
	if w["enemy"] != "":
		var e: Dictionary = DataDB.enemies[w["enemy"]]
		add_rich("Heading to [b]%s[/b] tonight to face the [b]%s[/b]. [color=#e06c6c]Weak to: %s[/color]" % [
			DataDB.dungeon(adv["plan"])["name"], e["name"], ", ".join(e["weak"])])
	var gear: PackedStringArray = []
	for slot in DataDB.SLOTS:
		var g = adv["gear"][slot]
		if g == null:
			gear.append("%s: [color=#777]none[/color]" % slot)
		else:
			gear.append("%s: %s (%d)%s" % [slot, g["name"], int(g["power"]), " [color=#ffc94a]*yours*[/color]" if g["player_made"] else ""])
	add_rich("Wearing: " + "   ".join(gear))

	if not adv["loot"].is_empty():
		var lp := AdventurerManager.loot_price(adv)
		var loot: PackedStringArray = []
		for m in adv["loot"]:
			loot.append("%dx %s" % [int(adv["loot"][m]), DataDB.material_name(m)])
		add_row("[color=#9fd8ff]They're selling dungeon loot:[/color] %s for %dg" % [", ".join(loot), lp],
			[button("Buy loot", _buy_loot, GameState.gold < lp)])

	add_heading("Your shelf")
	if GameState.items.is_empty():
		add_label("You have nothing to sell. Craft something first!", 16, Color("e0b06c"))
	var sorted := GameState.items.duplicate()
	sorted.sort_custom(func(a, b): return int(GameState.item_slot(a) == w["slot"]) > int(GameState.item_slot(b) == w["slot"]))
	for item in sorted:
		var r: Dictionary = DataDB.recipes[item["recipe"]]
		var q: Dictionary = DataDB.QUALITIES[int(item["quality"])]
		var fit := " [color=#8fd18f](suits a %s)[/color]" % AdventurerManager.class_name_of(adv) if AdventurerManager.likes(adv, r["tags"]) else ""
		var cm := AdventurerManager.counter_mult(r["tags"], r["slot"], w["enemy"])
		if cm > 1.0:
			fit += " [color=#e06c6c](perfect for tonight's fight!)[/color]"
		elif cm < 1.0:
			fit += " [color=#9a8f86](tonight's enemy resists this)[/color]"
		var sel := " <" if not _selected.is_empty() and int(_selected["uid"]) == int(item["uid"]) else ""
		add_row("[color=#%s]%s[/color]  %s, power %d, fair %dg%s%s" % [
			hex(q["color"]), GameState.item_name(item), r["slot"], GameState.item_power(item),
			GameState.item_value(item), fit, sel], [button("Select", _select.bind(item))])

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
	row.add_child(button("Nothing for you today", _dismiss))
	content.add_child(row)
	_reply = add_rich("")


func _select(item: Dictionary) -> void:
	_selected = item
	refresh()


func _offer() -> void:
	if _selected.is_empty():
		return
	var price := int(_price.value)
	var res := AdventurerManager.evaluate_offer(adv, _selected, price)
	if res["accepted"]:
		var item_label := GameState.item_name(_selected)
		AdventurerManager.sell_item(adv, _selected, price)
		_bought = true
		EventBus.notify.emit("Sold %s to %s for %dg!" % [item_label, adv["name"], price])
		close()
		return
	_refusals += int(res["patience"])
	_reply.text = "[color=#e0b06c]\"%s\"[/color]" % res["reason"]
	if _refusals >= MAX_REFUSALS:
		EventBus.notify.emit("%s lost patience and left." % adv["name"])
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
