extends BaseMenu
## Buy raw materials at today's market price; dump unwanted items on the
## wholesaler (who never pays more than the raw materials are worth).


func _init() -> void:
	super("Supply Order Board")


func build() -> void:
	add_label("Gold: %dg" % GameState.gold, 18, Color("ffd27a"))
	add_heading("Buy materials")
	add_label("Prices move: every purchase pushes a price up, loot flowing into town pushes it down, and both drift back over a few days.", 14, Color("b8b0a0"))
	for id in DataDB.materials:
		var m: Dictionary = DataDB.materials[id]
		if not m["buyable"]:
			continue
		var price := GameState.material_price(id)
		add_row("[b]%s[/b]  %dg each %s  [color=#b8b0a0](have %d)[/color]" % [m["name"], price, Market.trend(id), GameState.material_count(id)], [
			button("Buy 1", _buy.bind(id, 1), GameState.gold < price),
			button("Buy 5", _buy.bind(id, 5), GameState.gold < price * 5),
		])

	add_heading("Dungeon materials")
	add_label("Rare materials come from heroes' loot, Zara's wagon, the mine and vaults. Infuse them into gear for special properties.", 14, Color("b8b0a0"))
	var any := false
	for id in DataDB.materials:
		if not DataDB.materials[id]["buyable"] and GameState.material_count(id) > 0:
			any = true
			add_rich("%s: %d  %s" % [DataDB.materials[id]["name"], GameState.material_count(id), Market.trend(id)])
	if not any:
		add_label("None yet.", 14, Color("777777"))

	if not GameState.items.is_empty():
		add_heading("Wholesaler (pays poorly, and less for repeats)")
		for item in GameState.items.duplicate():
			add_row("%s - %dg" % [GameState.item_name(item), Market.wholesale_offer(item)], [button("Sell", _sell.bind(item))])


func _buy(id: String, count: int) -> void:
	GameState.buy_material(id, count)
	refresh()


func _sell(item: Dictionary) -> void:
	if str(item.get("legend", "")) != "":
		EventBus.notify.emit("The wholesaler won't touch a legend. Sell it to a hero.")
		return
	var offer := Market.wholesale_offer(item)
	GameState.add_gold(offer)
	GameState.remove_item(int(item["uid"]))
	Market.on_item_dumped(item)
	refresh()
