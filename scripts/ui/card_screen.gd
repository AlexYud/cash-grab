class_name CardScreen
extends Control
## Two jobs, both pure view (Main feeds it and forwards the clicks to the WaveManager):
##  - the upgrader machines' three cards (weapon effects, or armor gear effects), with a rotating 3D preview and the
##    price you pay for the one you take;
##  - between waves, a small "get ready" panel with the Ready button (Tab opens it).

signal pick_requested(index: int)
signal ready_requested(is_ready: bool)

const CARD_SIZE := Vector2(280, 380)
const PREVIEW_SIZE := Vector2i(256, 170)

var _title: Label
var _row: HBoxContainer
var _ready_button: Button
var _status: Label
var _hint: Label
var _cards: Array[Button] = []
var _spinners: Array[Node3D] = []
var _t := 0.0
var _is_ready := false
var _lock := 0.0 ## seconds after opening during which clicks and keys do nothing (stray clicks while fighting)
var _show_ready := false


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
	_title = UiKit.label("UPGRADE", 40, UiKit.ACCENT)
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
	_hint = UiKit.label("", 16, UiKit.DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint)


## Rebuilds the cards for these offers (WeaponCards / ArmorCards format). Empty = just the ready panel.
func show_offers(offers: Array, weapons: PlayerWeapons) -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	_spinners.clear()
	for i in offers.size():
		var offer: Dictionary = offers[i]
		var gear := bool(offer.get("gear", false))
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
		var tag_text := ArmorCards.tag(offer) if gear else WeaponCards.tag(offer)
		var new_one := int(offer["lvl"]) == 1
		var tag := UiKit.label(tag_text, 18, UiKit.GOOD if new_one else UiKit.ACCENT)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(tag)
		v.add_child(_preview(-1 if gear else int(offer["w"])))
		var nm := UiKit.label(ArmorCards.title(offer) if gear else WeaponCards.title(offer), 24)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(nm)
		if not gear:
			var wn := UiKit.label("for the " + weapons.list[int(offer["w"])].display_name, 16, UiKit.DIM)
			wn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			wn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(wn)
		var d := UiKit.label(ArmorCards.description(offer) if gear else WeaponCards.description(offer), 17, UiKit.DIM)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.size_flags_vertical = Control.SIZE_EXPAND_FILL
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(d)
		var key := UiKit.label(("[%d]   $%d" % [i + 1, int(offer["cost"])]) if int(offer.get("cost", 0)) > 0 else "[%d]" % (i + 1), 20, UiKit.ACCENT)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(key)
	if not offers.is_empty():
		var g := bool(offers[0].get("gear", false))
		_title.text = "UPGRADE YOUR GEAR" if g else "UPGRADE YOUR %s" % weapons.list[int(offers[0]["w"])].display_name.to_upper()


## The little rotating 3D view of a weapon, or of a vest for gear cards (its own world, so it never mixes with the game).
func _preview(weapon_idx: int) -> Control:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(PREVIEW_SIZE)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.size = PREVIEW_SIZE
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.22, 0.29)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.ambient_light_energy = 1.3
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_energy = 1.6
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.position = Vector3(0, 0.08, 1.42)
	vp.add_child(cam)
	var holder := Node3D.new()
	vp.add_child(holder)
	if weapon_idx < 0:
		holder.add_child(GunModels.build_vest())
		_spinners.append(holder)
		return svc
	var model := GunModels.build(weapon_idx, false)
	model.rotation = Vector3.ZERO # melee models are tilted for the first-person view; the card shows them level
	var muzzle: Vector3 = model.get_meta("muzzle")
	var fit := clampf(0.8 / maxf(absf(muzzle.z), 0.1), 1.0, 2.6) # small guns are blown up so every card shows its weapon big
	model.scale = Vector3.ONE * fit
	model.position = Vector3(0, 0, -muzzle.z * 0.5 * fit)
	holder.add_child(model)
	_spinners.append(holder)
	return svc


## Called by Main every frame while visible. show_ready: it is a break, so the Ready button makes sense.
func refresh(waiting_names: Array, i_am_ready: bool, show_ready: bool) -> void:
	_show_ready = show_ready
	_ready_button.visible = show_ready
	_status.visible = show_ready
	if _ready_button.button_pressed != i_am_ready:
		_ready_button.set_pressed_no_signal(i_am_ready)
	_is_ready = i_am_ready
	_ready_button.text = "READY!  (click to undo)" if i_am_ready else "READY  [Enter]"
	if _cards.is_empty():
		_title.text = "GET READY"
		_hint.text = "[Tab] closes this - the next wave starts when everyone is ready"
	else:
		_hint.text = "[1] [2] [3] or click to pick one and get your item back  -  close this and it stays in the machine (use the machine again to come back)"
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
	elif (k == KEY_ENTER or k == KEY_KP_ENTER) and _show_ready:
		_ready_button.button_pressed = not _ready_button.button_pressed # emits toggled
		get_viewport().set_input_as_handled()
