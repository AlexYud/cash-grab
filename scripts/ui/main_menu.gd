class_name MainMenu
extends CenterContainer

signal host_requested(player_name: String, port: int)
signal join_requested(player_name: String, address: String, port: int)
signal solo_requested(player_name: String)

var name_edit: LineEdit
var addr_edit: LineEdit
var port_edit: LineEdit
var status: Label


func _ready() -> void:
	var cfg := UiKit.load_settings()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(UiKit.margin(box, 26))

	box.add_child(UiKit.label("CASH GRAB", 54, UiKit.ACCENT))
	box.add_child(UiKit.label("Co-op wave survival  -  prototype 0.1", 18, UiKit.DIM))
	box.add_child(HSeparator.new())

	var row := HBoxContainer.new()
	row.add_child(UiKit.label("Name", 20, UiKit.DIM))
	name_edit = LineEdit.new()
	name_edit.text = cfg.get_value("menu", "name", "Player%d" % (randi() % 90 + 10))
	name_edit.max_length = 16
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_edit)
	row.add_child(UiKit.label("Port", 20, UiKit.DIM))
	port_edit = LineEdit.new()
	port_edit.text = str(cfg.get_value("menu", "port", Net.DEFAULT_PORT))
	port_edit.custom_minimum_size = Vector2(100, 0)
	row.add_child(port_edit)
	box.add_child(row)

	var solo := UiKit.button("Play solo")
	solo.pressed.connect(func() -> void:
		_save()
		solo_requested.emit(name_edit.text))
	box.add_child(solo)

	box.add_child(HSeparator.new())
	var host := UiKit.button("Host a game  (friends join your IP)")
	host.pressed.connect(func() -> void:
		_save()
		host_requested.emit(name_edit.text, _port()))
	box.add_child(host)

	var jrow := HBoxContainer.new()
	addr_edit = LineEdit.new()
	addr_edit.placeholder_text = "Host IP address"
	addr_edit.text = cfg.get_value("menu", "address", "127.0.0.1")
	addr_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jrow.add_child(addr_edit)
	var join := UiKit.button("Join")
	join.custom_minimum_size = Vector2(120, 42)
	join.pressed.connect(func() -> void:
		_save()
		set_status("Connecting...", UiKit.DIM)
		join_requested.emit(name_edit.text, addr_edit.text.strip_edges(), _port()))
	jrow.add_child(join)
	box.add_child(jrow)

	status = UiKit.label("", 18, UiKit.BAD)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(480, 28)
	box.add_child(status)

	var quit := UiKit.button("Quit")
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)


func set_status(text: String, color: Color = UiKit.BAD) -> void:
	status.text = text
	status.add_theme_color_override("font_color", color)


func _port() -> int:
	var p := port_edit.text.to_int()
	return p if p > 0 and p < 65536 else Net.DEFAULT_PORT


func _save() -> void:
	var cfg := UiKit.load_settings()
	cfg.set_value("menu", "name", name_edit.text)
	cfg.set_value("menu", "address", addr_edit.text)
	cfg.set_value("menu", "port", _port())
	cfg.save(UiKit.SETTINGS_PATH)
