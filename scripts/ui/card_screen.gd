class_name CardScreen
extends Control
## The between-rounds reward screen: three cards (a new weapon, or a buff for one you own), a rotating 3D preview of
## each weapon, and the Ready button. Pure view: Main feeds it the offers and forwards the clicks to the WaveManager.

signal pick_requested(index: int)
signal ready_requested(is_ready: bool)

const CARD_SIZE := Vector2(280, 380)
const PREVIEW_SIZE := Vector2i(256, 170)

var _title: Label
var _row: HBoxContainer
var _ready_button: Button
var _status: Label
var _cards: Array[Button] = []
var _spinners: Array[Node3D] = []
var _t := 0.0
var _is_ready := false
var _lock := 0.0 ## seconds after opening during which clicks and keys do nothing (stray clicks while fighting)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visibility_changed.connect(func() -> void:
		if visible:
			_lock = 0.9)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	_title = UiKit.label("CHOOSE YOUR REWARD", 40, UiKit.ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 20)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_row)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 24)
	box.add_child(bottom)
	_ready_button = UiKit.button("READY  [Enter]")
	_ready_button.custom_minimum_size = Vector2(240, 52)
	_ready_button.toggle_mode = true
	_ready_button.toggled.connect(func(on: bool) -> void:
		_is_ready = on
		ready_requested.emit(on))
	bottom.add_child(_ready_button)
	_status = UiKit.label("", 20, UiKit.DIM)
	bottom.add_child(_status)
	var hint := UiKit.label("[1] [2] [3] pick a card   -   [Tab] hide this screen   -   the next wave starts when everyone is ready", 16, UiKit.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


## Rebuilds the three cards for these offers (see WeaponCards.roll).
func show_offers(offers: Array, weapons: PlayerWeapons) -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	_spinners.clear()
	for i in offers.size():
		var offer: Dictionary = offers[i]
		var b := Button.new()
		b.custom_minimum_size = CARD_SIZE
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: pick_requested.emit(i))
		_row.add_child(b)
		_cards.append(b)
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 10
		v.offset_right = -10
		v.offset_top = 10
		v.offset_bottom = -10
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 6)
		b.add_child(v)
		var is_new := WeaponCards.is_new(offer)
		var tag := UiKit.label(WeaponCards.tag(offer, weapons), 18, UiKit.GOOD if is_new else UiKit.ACCENT)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(tag)
		v.add_child(_preview(int(offer["w"])))
		var nm := UiKit.label(WeaponCards.title(offer, weapons), 22)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(nm)
		var d := UiKit.label(WeaponCards.description(offer, weapons), 17, UiKit.DIM)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.size_flags_vertical = Control.SIZE_EXPAND_FILL
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(d)
		var key := UiKit.label("[%d]" % (i + 1), 18, UiKit.ACCENT)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(key)


## The little rotating 3D view of a weapon (its own world, so it never mixes with the game).
func _preview(weapon_idx: int) -> Control:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(PREVIEW_SIZE)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.size = PREVIEW_SIZE
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_energy = 1.1
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.position = Vector3(0, 0.08, 1.42)
	vp.add_child(cam)
	var holder := Node3D.new()
	vp.add_child(holder)
	var model := GunModels.build(weapon_idx, false)
	model.rotation = Vector3.ZERO # melee models are tilted for the first-person view; the card shows them level
	var muzzle: Vector3 = model.get_meta("muzzle")
	model.position = Vector3(0, 0, -muzzle.z * 0.5)
	holder.add_child(model)
	_spinners.append(holder)
	return svc


## Called every frame by Main while visible.
func refresh(ready_names: Array, waiting_names: Array, i_am_ready: bool) -> void:
	if _ready_button.button_pressed != i_am_ready:
		_ready_button.set_pressed_no_signal(i_am_ready)
	_is_ready = i_am_ready
	_ready_button.text = "READY!  (click to undo)" if i_am_ready else "READY  [Enter]"
	_title.text = "CHOOSE YOUR REWARD" if not _cards.is_empty() else "GET READY"
	if waiting_names.is_empty():
		_status.text = "Everyone is ready..."
	else:
		_status.text = "Waiting for: %s" % ", ".join(PackedStringArray(waiting_names))


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_lock = maxf(_lock - delta, 0.0)
	for c in _cards:
		c.disabled = _lock > 0.0
	_ready_button.disabled = _lock > 0.0
	for i in _spinners.size():
		if is_instance_valid(_spinners[i]):
			_spinners[i].rotation.y = -PI / 2.0 + sin(_t * 0.9 + i) * 0.7
			_spinners[i].rotation.x = sin(_t * 0.6 + i * 2.0) * 0.12


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or _lock > 0.0 or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).physical_keycode
	var idx := -1
	if k == KEY_1:
		idx = 0
	elif k == KEY_2:
		idx = 1
	elif k == KEY_3:
		idx = 2
	if idx >= 0 and idx < _cards.size():
		pick_requested.emit(idx)
		get_viewport().set_input_as_handled()
	elif k == KEY_ENTER or k == KEY_KP_ENTER:
		_ready_button.button_pressed = not _ready_button.button_pressed # emits toggled
		get_viewport().set_input_as_handled()
