extends BaseMenu
## Buy raw materials; dump unwanted items on a wholesaler for a poor price.

const WHOLESALE_RATE := 0.4


func _init() -> void:
	super("Supply Order Board")


func build() -> void:
	add_label("Gold: %dg" % GameState.gold, 18, Color("ffd27a"))
	add_heading("Buy materials")
	for id in DataDB.materials:
		var m: Dictionary = DataDB.materials[id]
		if not m["buyable"]:
			continue
		var price := GameState.material_price(id)
		add_row("[b]%s[/b]  %dg each   [color=#b8b0a0](have %d)[/color]" % [m["name"], price, GameState.material_count(id)], [
			button("Buy 1", _buy.bind(id, 1), GameState.gold < price),
			button("Buy 5", _buy.bind(id, 5), GameState.gold < price * 5),
		])

	add_heading("Dungeon materials")
	add_label("Rare materials can't be ordered - buy them from adventurers returning with loot.", 15, Color("b8b0a0"))
	for id in DataDB.materials:
		if not DataDB.materials[id]["buyable"]:
			add_rich("%s: %d" % [DataDB.materials[id]["name"], GameState.material_count(id)])

	if not GameState.items.is_empty():
		add_heading("Wholesaler (sell for %d%% of fair value)" % int(WHOLESALE_RATE * 100))
		for item in GameState.items.duplicate():
			var price := _wholesale(item)
			add_row("%s - %dg" % [GameState.item_name(item), price], [button("Sell", _sell.bind(item))])


func _buy(id: String, count: int) -> void:
	if GameState.spend_gold(GameState.material_price(id) * count):
		GameState.add_material(id, count)
	refresh()


func _wholesale(item: Dictionary) -> int:
	return max(1, int(GameState.item_value(item) * WHOLESALE_RATE))


func _sell(item: Dictionary) -> void:
	GameState.add_gold(_wholesale(item))
	GameState.remove_item(int(item["uid"]))
	refresh()
