class_name BaseMenu
extends PanelContainer
## Shared look & helpers for every popup menu. Subclasses override build()
## to fill `content` and call refresh() whenever data changes.

signal closed

var ui: Node
var content: VBoxContainer
var title_label: Label
var _title: String


func _init(title: String = "") -> void:
	_title = title


func _ready() -> void:
	# Centered 780x600 panel.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -390
	offset_right = 390
	offset_top = -300
	offset_bottom = 300
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.06, 1.0)
	style.border_color = Color("c8862f")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	add_theme_stylebox_override("panel", style)

	var outer := VBoxContainer.new()
	add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	title_label = Label.new()
	title_label.text = _title
	title_label.add_theme_font_size_override("font_size", 26)
	title_label.add_theme_color_override("font_color", Color("ffd27a"))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var close_btn := Button.new()
	close_btn.text = "Close [Esc]"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)
	outer.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	refresh()


func refresh() -> void:
	for c in content.get_children():
		c.queue_free()
	build()


## Override in subclasses.
func build() -> void:
	pass


func close() -> void:
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


# --- Little widget helpers ---------------------------------------------------

func add_label(text: String, size := 16, color := Color("e8e2d6")) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	content.add_child(l)
	return l


func add_rich(bbcode: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.text = bbcode
	r.add_theme_font_size_override("normal_font_size", 16)
	content.add_child(r)
	return r


func add_heading(text: String) -> Label:
	var l := add_label(text, 20, Color("ffd27a"))
	return l


## A row: rich-text description on the left, buttons on the right.
func add_row(bbcode: String, buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	var desc := RichTextLabel.new()
	desc.bbcode_enabled = true
	desc.fit_content = true
	desc.text = bbcode
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.add_theme_font_size_override("normal_font_size", 16)
	row.add_child(desc)
	for b in buttons:
		row.add_child(b)
	content.add_child(row)
	return row


static func button(text: String, cb: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.custom_minimum_size.x = 110
	b.focus_mode = Control.FOCUS_NONE  # keeps Space/E free for the game
	b.pressed.connect(cb)
	return b


static func hex(c: Color) -> String:
	return c.to_html(false)
