class_name PauseMenu
extends CenterContainer

signal resume_requested
signal leave_requested

var _mode_btn: Button
var _meter: ProgressBar
var _keys: Label
var _voice_players: VBoxContainer


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pad := UiKit.margin(box, 24)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	panel.add_child(scroll)
	box.add_child(UiKit.label("PAUSED", 40, UiKit.ACCENT))
	box.add_child(UiKit.label("The game keeps running for everyone else.", 16, UiKit.DIM))
	var resume := UiKit.button("Resume")
	resume.pressed.connect(func() -> void: resume_requested.emit())
	box.add_child(resume)
	box.add_child(HSeparator.new())

	box.add_child(UiKit.label("Voice chat", 20, UiKit.DIM))
	_mode_btn = UiKit.button("")
	_mode_btn.pressed.connect(func() -> void:
		Voice.cycle_mode()
		_refresh())
	box.add_child(_mode_btn)
	_meter = UiKit.bar(UiKit.GOOD, Vector2(0, 14))
	box.add_child(_meter)
	var tip := UiKit.label("Speak: the bar should move. Teammates hear you quieter the farther they are.", 15, UiKit.DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(420, 0)
	box.add_child(tip)

	var vv := _slider_row("Voice volume", Voice.master_gain, func(v: float) -> void: Voice.set_master_gain(v))
	box.add_child(vv)
	_voice_players = VBoxContainer.new()
	box.add_child(_voice_players)

	var vrow := HBoxContainer.new()
	vrow.add_child(UiKit.label("Master", 20, UiKit.DIM))
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol.value_changed.connect(func(v: float) -> void:
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
		UiKit.save_setting("audio", "master", v))
	vrow.add_child(vol)
	box.add_child(vrow)

	var srow := HBoxContainer.new()
	srow.add_child(UiKit.label("Mouse", 20, UiKit.DIM))
	var sens := HSlider.new()
	sens.min_value = 0.3
	sens.max_value = 3.0
	sens.step = 0.05
	sens.value = Net.sens_scale
	sens.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sens.value_changed.connect(func(v: float) -> void:
		Net.sens_scale = v
		UiKit.save_setting("audio", "sensitivity", v))
	srow.add_child(sens)
	box.add_child(srow)

	box.add_child(HSeparator.new())
	_keys = UiKit.label("WASD move   Shift sprint   Space jump   LMB fire   R reload   1-4/wheel weapon   F shove   G hold to grab   E hold to repair / revive   V push-to-talk   M mute", 15, UiKit.DIM)
	_keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keys.custom_minimum_size = Vector2(420, 0)
	box.add_child(_keys)
	var leave := UiKit.button("Leave game")
	leave.pressed.connect(func() -> void: leave_requested.emit())
	box.add_child(leave)
	visibility_changed.connect(_refresh)
	_refresh()


func _slider_row(label_text: String, value: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := UiKit.label(label_text, 18, UiKit.DIM)
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 2.0
	s.step = 0.05
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(on_change)
	row.add_child(s)
	return row


func _refresh() -> void:
	if _mode_btn != null:
		_mode_btn.text = "Mode: " + Voice.mode_name()
	if _voice_players != null and visible:
		for c in _voice_players.get_children():
			c.queue_free()
		for p in Net.all_players():
			if p != Net.local_player:
				var pname := p.player_name
				_voice_players.add_child(_slider_row("  " + pname, float(Voice.player_gains.get(pname, 1.0)), func(v: float) -> void: Voice.set_player_gain(pname, v)))


func _process(_delta: float) -> void:
	if visible and _meter != null:
		_meter.value = Voice.mic_level
