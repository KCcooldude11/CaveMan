extends BaseMenu
## Spend gold (gated by renown) on permanent shop improvements.


func _init() -> void:
	super("Upgrade Lectern")


func build() -> void:
	add_label("Gold: %dg   Renown: %d" % [GameState.gold, GameState.renown], 18, Color("ffd27a"))
	for id in DataDB.upgrades:
		var u: Dictionary = DataDB.upgrades[id]
		var lvl := GameState.upgrade_level(id)
		var nxt := GameState.upgrade_next(id)
		var text := "[b]%s[/b]  Lv %d/%d\n[color=#b8b0a0]%s[/color]" % [u["name"], lvl, GameState.upgrade_max(id), u["desc"]]
		if nxt.is_empty():
			add_row(text, [button("MAX", func(): pass, true)])
			continue
		var locked := GameState.renown < int(nxt["renown"])
		var label := "Needs %d renown" % nxt["renown"] if locked else "Buy %dg" % nxt["cost"]
		add_row(text, [button(label, _buy.bind(id), locked or GameState.gold < int(nxt["cost"]))])


func _buy(id: String) -> void:
	if GameState.buy_upgrade(id):
		EventBus.notify.emit("Upgraded %s!" % DataDB.upgrades[id]["name"])
	refresh()
