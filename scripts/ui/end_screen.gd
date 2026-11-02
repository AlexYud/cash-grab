class_name EndScreen
extends CenterContainer

signal restart_requested
signal lobby_requested
signal leave_requested

var _title: Label
var _detail: Label
var _restart: Button
var _lobby: Button
var _wait: Label


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(UiKit.margin(box, 26))
	_title = UiKit.label("", 48, UiKit.ACCENT)
	box.add_child(_title)
	_detail = UiKit.label("", 20)
	box.add_child(_detail)
	box.add_child(HSeparator.new())
	_wait = UiKit.label("Waiting for the host...", 18, UiKit.DIM)
	box.add_child(_wait)
	_restart = UiKit.button("Play again")
	_restart.pressed.connect(func() -> void: restart_requested.emit())
	box.add_child(_restart)
	_lobby = UiKit.button("Back to lobby")
	_lobby.pressed.connect(func() -> void: lobby_requested.emit())
	box.add_child(_lobby)
	var leave := UiKit.button("Leave game")
	leave.pressed.connect(func() -> void: leave_requested.emit())
	box.add_child(leave)


func show_result(victory: bool, wave: int, total: int) -> void:
	_title.text = "VICTORY" if victory else "GAME OVER"
	_title.add_theme_color_override("font_color", UiKit.GOOD if victory else UiKit.BAD)
	var lines := PackedStringArray()
	lines.append("Waves cleared: %d / %d" % [wave if victory else maxi(wave - 1, 0), total])
	var ps := Net.all_players()
	ps.sort_custom(func(a: Player, b: Player) -> bool: return a.kills > b.kills)
	for p in ps:
		lines.append("%s  -  %d kills" % [p.player_name, p.kills])
	_detail.text = "\n".join(lines)
	_restart.visible = Net.is_host()
	_lobby.visible = Net.is_host()
	_wait.visible = not Net.is_host()
