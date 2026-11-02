class_name PauseMenu
extends CenterContainer

signal resume_requested
signal leave_requested

var _mode_btn: Button
var _meter: ProgressBar
var _keys: Label


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(UiKit.margin(box, 24))
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

	var vrow := HBoxContainer.new()
	vrow.add_child(UiKit.label("Volume", 20, UiKit.DIM))
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol.value_changed.connect(func(v: float) -> void: AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001))))
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
	sens.value_changed.connect(func(v: float) -> void: Net.sens_scale = v)
	srow.add_child(sens)
	box.add_child(srow)

	box.add_child(HSeparator.new())
	_keys = UiKit.label("WASD move   Shift sprint   Space jump   LMB fire   R reload   1/2/wheel weapon   F shove   G hold to grab   E hold to repair / revive   V push-to-talk   M mute", 15, UiKit.DIM)
	_keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keys.custom_minimum_size = Vector2(420, 0)
	box.add_child(_keys)
	var leave := UiKit.button("Leave game")
	leave.pressed.connect(func() -> void: leave_requested.emit())
	box.add_child(leave)
	visibility_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if _mode_btn != null:
		_mode_btn.text = "Mode: " + Voice.mode_name()


func _process(_delta: float) -> void:
	if visible and _meter != null:
		_meter.value = Voice.mic_level
