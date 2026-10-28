extends BaseMenu
## The travelling merchant: rare dungeon materials at a premium, and she buys
## your gear for more than the wholesaler does.


func _init() -> void:
	super(DataDB.village["merchant"]["name"])


func build() -> void:
	add_label("Gold: %dg" % GameState.gold, 18, Color("ffd27a"))
	add_heading("Rare materials")
	if Village.merchant_stock.is_empty():
		add_label("\"Sold out, friend. I'll be back on Day %d.\"" % Village.next_merchant_day(GameState.day + 1), 15, Color("b8b0a0"))
	for m in Village.merchant_stock:
		var n := int(Village.merchant_stock[m])
		var price := Village.merchant_price(m)
		add_row("[b]%s[/b]  %dg each   [color=#b8b0a0](%d left, you have %d)[/color]" % [DataDB.material_name(m), price, n, GameState.material_count(m)],
			[button("Buy", _buy.bind(m), n <= 0 or GameState.gold < price)])
	if not GameState.items.is_empty():
		add_heading("Sell gear (%d%% of fair value)" % int(float(DataDB.village["merchant"]["buy_rate"]) * 100))
		for item in GameState.items.duplicate():
			add_row("%s - %dg" % [GameState.item_name(item), Village.merchant_offer(item)], [button("Sell", _sell.bind(item))])


func _buy(m: String) -> void:
	Village.merchant_buy(m)
	refresh()


func _sell(item: Dictionary) -> void:
	GameState.add_gold(Village.merchant_offer(item))
	GameState.remove_item(int(item["uid"]))
	refresh()
