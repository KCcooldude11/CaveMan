extends CanvasLayer
## Owns the HUD, plays UI sounds, and makes sure only one menu is open at a
## time. Opening a menu frees the mouse, freezes the player and pauses the clock.

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
const BriefingMenu := preload("res://scripts/ui/briefing_menu.gd")
const VillageHallMenu := preload("res://scripts/ui/village_hall_menu.gd")
const ChronicleMenu := preload("res://scripts/ui/chronicle_menu.gd")
const SOUNDS := {
	"coin": preload("res://assets/sounds/coin.wav"),
	"fanfare": preload("res://assets/sounds/fanfare.wav"),
}

var player: Node:
	set(p):
		player = p
		hud.player = p
var hud: Control
var current: BaseMenu = null
var _sfx: AudioStreamPlayer


func _ready() -> void:
	hud = HUD.new()
	add_child(hud)
	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)
	EventBus.sold.connect(func(_p): play("coin"))
	EventBus.celebrate.connect(func(_a, _b): play("fanfare"))


func play(key: String) -> void:
	_sfx.stream = SOUNDS[key]
	_sfx.play()


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
		"village_hall": open(VillageHallMenu.new())
		"chronicle": open(ChronicleMenu.new())
		"briefing": open(BriefingMenu.new())


func show_summary(report: Dictionary, on_continue: Callable) -> void:
	open(SummaryMenu.new(report, on_continue))


func show_briefing() -> void:
	open(BriefingMenu.new())


func summary_open() -> bool:
	return current is SummaryMenu


## The forge's first-person anvil: hide the craft menu, hand control to the
## anvil, and bring the menu back with the result.
func begin_anvil(menu: BaseMenu, level: int, power: int) -> void:
	menu.visible = false
	menu.set_process_unhandled_input(false)
	hud.visible = false
	var session: Node = get_tree().current_scene.start_forge_session(level, power)
	session.finished.connect(func(q):
		hud.visible = true
		if is_instance_valid(menu):
			menu.visible = true
			menu.set_process_unhandled_input(true)
			menu.on_minigame_finished(q))


func _unhandled_input(event: InputEvent) -> void:
	if current != null:
		return
	var menus := { "pause": PauseMenu, "ledger": LedgerMenu, "briefing": BriefingMenu, "chronicle": ChronicleMenu }
	for action in menus:
		if event.is_action_pressed(action):
			get_viewport().set_input_as_handled()
			open(menus[action].new())
			return
