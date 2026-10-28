extends CanvasLayer
## Owns the HUD and makes sure only one menu is open at a time.
## Opening a menu frees the mouse, freezes the player and pauses the clock.

const HUD := preload("res://scripts/ui/hud.gd")
const CraftMenu := preload("res://scripts/ui/craft_menu.gd")
const SaleMenu := preload("res://scripts/ui/sale_menu.gd")
const SupplyMenu := preload("res://scripts/ui/supply_menu.gd")
const UpgradeMenu := preload("res://scripts/ui/upgrade_menu.gd")
const LedgerMenu := preload("res://scripts/ui/ledger_menu.gd")
const SummaryMenu := preload("res://scripts/ui/summary_menu.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const NoticeBoardMenu := preload("res://scripts/ui/notice_board_menu.gd")
const TavernMenu := preload("res://scripts/ui/tavern_menu.gd")
const MerchantMenu := preload("res://scripts/ui/merchant_menu.gd")

var player: Node:
	set(p):
		player = p
		hud.player = p
var hud: Control
var current: BaseMenu = null


func _ready() -> void:
	hud = HUD.new()
	add_child(hud)


func _exit_tree() -> void:
	if current != null:
		EventBus.menu_closed.emit()


func open(menu: BaseMenu) -> void:
	if current != null:
		_close_current()
	current = menu
	menu.ui = self
	menu.closed.connect(_on_menu_closed.bind(menu))
	add_child(menu)
	EventBus.menu_opened.emit()


func _on_menu_closed(menu: BaseMenu) -> void:
	if menu == current:
		_close_current()


func _close_current() -> void:
	var m := current
	current = null
	m.queue_free()
	EventBus.menu_closed.emit()


func is_open() -> bool:
	return current != null


func shop_node() -> Node:
	return get_tree().current_scene.get_node("ShopFloor")


# --- Openers used by stations ------------------------------------------------

func open_craft(station: String) -> void:
	open(CraftMenu.new(station))


func open_sale(npc: Node) -> void:
	open(SaleMenu.new(npc))


func open_menu_by_name(menu_name: String) -> void:
	match menu_name:
		"supply": open(SupplyMenu.new())
		"upgrades": open(UpgradeMenu.new())
		"ledger": open(LedgerMenu.new())
		"notice_board": open(NoticeBoardMenu.new())
		"tavern": open(TavernMenu.new())
		"merchant": open(MerchantMenu.new())


func show_summary(day: int, lines: Array, renown: int, on_continue: Callable) -> void:
	open(SummaryMenu.new(day, lines, renown, on_continue))


func summary_open() -> bool:
	return current is SummaryMenu


func _unhandled_input(event: InputEvent) -> void:
	if current != null:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		open(PauseMenu.new())
	elif event.is_action_pressed("ledger"):
		get_viewport().set_input_as_handled()
		open(LedgerMenu.new())
