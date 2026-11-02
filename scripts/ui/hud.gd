class_name Hud
extends Control
## In-game overlay. Pure view: it polls Net.local_player and the WaveManager every frame.

var waves: WaveManager

var _wave_label: Label
var _sub_label: Label
var _announce: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _status: Label
var _weapon: Label
var _ammo: Label
var _reload_bar: ProgressBar
var _team: VBoxContainer
var _prompt: Label
var _prompt_bar: ProgressBar
var _hit: Label
var _vignette: TextureRect
var _tint: ColorRect
var _mic: Label
var _fps: Label
var _cash: Label
var _cross: Control
var _announce_tween: Tween
var _notice: Label
var _notice_tween: Tween
var _team_timer := 0.0


func _ready() -> void:
	# NOT set_anchors_preset(): it keeps the current (zero) size when the parent has not been laid out yet.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func bind(wm: WaveManager) -> void:
	waves = wm
	wm.announce.connect(show_announce)
	wm.notice.connect(show_notice)


func show_notice(text: String) -> void:
	_notice.text = text
	_notice.modulate.a = 1.0
	if _notice_tween != null:
		_notice_tween.kill()
	_notice_tween = create_tween()
	_notice_tween.tween_interval(2.4)
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, 0.8)


func show_announce(text: String) -> void:
	_announce.text = text
	_announce.modulate.a = 1.0
	if _announce_tween != null:
		_announce_tween.kill()
	_announce_tween = create_tween()
	_announce_tween.tween_interval(2.2)
	_announce_tween.tween_property(_announce, "modulate:a", 0.0, 1.2)


func _build() -> void:
	# screen effects first so everything else draws on top
	_tint = ColorRect.new()
	_tint.color = Color(0.5, 0.0, 0.0, 0.0)
	_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tint)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(0.8, 0.0, 0.0, 0.0), Color(0.8, 0.0, 0.0, 0.0), Color(0.8, 0.0, 0.0, 0.9)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	_vignette = TextureRect.new()
	_vignette.texture = gt
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	add_child(_vignette)

	# crosshair
	_cross = Control.new()
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cross)
	for r in [Rect2(-13, -1, 8, 2), Rect2(5, -1, 8, 2), Rect2(-1, -13, 2, 8), Rect2(-1, 5, 2, 8)]:
		var cr := ColorRect.new()
		cr.color = Color(1, 1, 1, 0.85)
		cr.position = r.position
		cr.size = r.size
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cross.add_child(cr)
	_hit = UiKit.label("×", 46, Color.WHITE)
	_hit.position = Vector2(-14, -34)
	_hit.modulate.a = 0.0
	_cross.add_child(_hit)

	# top centre: wave info + announcements
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	top.offset_top = 14
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_wave_label = UiKit.label("", 34, UiKit.ACCENT)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_wave_label)
	_sub_label = UiKit.label("", 20)
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_sub_label)
	_announce = UiKit.label("", 52, Color.WHITE)
	_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce.modulate.a = 0.0
	_announce.add_theme_constant_override("outline_size", 8)
	_announce.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	top.add_child(_announce)
	_notice = UiKit.label("", 26, UiKit.ACCENT)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.modulate.a = 0.0
	_notice.add_theme_constant_override("outline_size", 6)
	_notice.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	top.add_child(_notice)

	# interaction prompt under the crosshair
	var pbox := VBoxContainer.new()
	pbox.set_anchors_preset(Control.PRESET_CENTER)
	pbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pbox.offset_top = 70
	pbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pbox)
	_prompt = UiKit.label("", 22)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	pbox.add_child(_prompt)
	_prompt_bar = UiKit.bar(UiKit.ACCENT, Vector2(260, 12))
	_prompt_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pbox.add_child(_prompt_bar)

	# bottom left: health + status + mic
	var bl := VBoxContainer.new()
	bl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bl.offset_left = 20
	bl.offset_bottom = -20
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bl)
	_status = UiKit.label("", 22, UiKit.BAD)
	bl.add_child(_status)
	_mic = UiKit.label("", 16, UiKit.DIM)
	bl.add_child(_mic)
	var hrow := HBoxContainer.new()
	_hp_bar = UiKit.bar(UiKit.GOOD, Vector2(280, 22))
	hrow.add_child(_hp_bar)
	_hp_label = UiKit.label("100", 26)
	hrow.add_child(_hp_label)
	bl.add_child(hrow)

	# bottom right: weapon
	var br := VBoxContainer.new()
	br.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	br.grow_vertical = Control.GROW_DIRECTION_BEGIN
	br.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	br.offset_right = -24
	br.offset_bottom = -20
	br.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(br)
	_weapon = UiKit.label("", 22, UiKit.DIM)
	_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(_weapon)
	_ammo = UiKit.label("", 40)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(_ammo)
	_reload_bar = UiKit.bar(UiKit.ACCENT, Vector2(160, 8))
	br.add_child(_reload_bar)

	# left: team list
	_team = VBoxContainer.new()
	_team.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_team.grow_vertical = Control.GROW_DIRECTION_BOTH
	_team.offset_left = 20
	_team.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_team)

	_cash = UiKit.label("", 30, Color(0.98, 0.84, 0.3))
	_cash.position = Vector2(20, 12)
	_cash.add_theme_constant_override("outline_size", 6)
	_cash.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(_cash)
	_fps = UiKit.label("", 14, UiKit.DIM)
	_fps.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fps.offset_right = -10
	_fps.offset_top = 6
	add_child(_fps)


func _process(delta: float) -> void:
	_fps.text = "%d fps" % Engine.get_frames_per_second()
	if waves != null:
		_cash.text = "$ %d" % waves.cash
	_update_top()
	var p := Net.local_player
	if p == null:
		return
	var hp_frac := p.hp / float(GameConfig.PLAYER_MAX_HP)
	_hp_bar.value = hp_frac
	_hp_bar.add_theme_stylebox_override("fill", _fill_style(UiKit.GOOD.lerp(UiKit.BAD, 1.0 - clampf(hp_frac * 1.6, 0.0, 1.0))))
	_hp_label.text = str(p.hp)
	match p.status:
		Player.Status.DOWNED:
			_status.text = "YOU ARE DOWN - crawl to a teammate!  Bleeding out in %ds" % ceili(p.bleed_left)
			if p.revive_progress > 0.0:
				_status.text = "Being revived... %d%%" % int(p.revive_progress * 100.0)
		Player.Status.ELIMINATED:
			_status.text = "OUT - you return when the wave is cleared (click to change spectate target)"
		_:
			_status.text = ""
	var w := p.weapons
	_weapon.text = w.list[w.current].display_name
	_ammo.text = "%d / ∞" % w.ammo[w.current]
	_reload_bar.visible = w.is_reloading()
	_reload_bar.value = w.reload_fraction()
	_prompt.text = p.prompt_text
	_prompt_bar.visible = p.prompt_progress >= 0.0 and p.prompt_text != ""
	_prompt_bar.value = maxf(p.prompt_progress, 0.0)
	if w.head_marker > 0.0 and w.kill_marker <= 0.0:
		_hit.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2)) # gold: headshot
		_hit.modulate.a = clampf(w.head_marker / 0.15, 0.0, 1.0)
	elif w.kill_marker > 0.0:
		_hit.add_theme_color_override("font_color", UiKit.BAD)
		_hit.modulate.a = clampf(w.kill_marker / 0.2, 0.0, 1.0)
	else:
		_hit.add_theme_color_override("font_color", Color.WHITE)
		_hit.modulate.a = clampf(w.hit_marker / 0.1, 0.0, 1.0)
	_vignette.modulate.a = clampf(p.damage_flash + (0.35 if hp_frac < 0.3 and p.status == Player.Status.ALIVE else 0.0), 0.0, 1.0)
	_tint.color.a = 0.28 if p.status == Player.Status.DOWNED else (0.55 if p.status == Player.Status.ELIMINATED else 0.0)
	_cross.visible = p.status != Player.Status.ELIMINATED
	_update_mic()
	_team_timer -= delta
	if _team_timer <= 0.0:
		_team_timer = 0.2
		_update_team()


func _fill_style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(4)
	return s


func _update_top() -> void:
	if waves == null:
		return
	match waves.state:
		WaveManager.State.BREAK:
			_wave_label.text = "WAVE %d / %d" % [mini(waves.wave + 1, waves.total_waves), waves.total_waves]
			_sub_label.text = "Next wave in %d s  -  repair the barricades [E]" % ceili(maxf(waves.break_left, 0.0))
		WaveManager.State.ACTIVE:
			_wave_label.text = "WAVE %d / %d" % [waves.wave, waves.total_waves]
			_sub_label.text = "Zombies left: %d" % (waves.enemies_alive + waves.to_spawn)
		WaveManager.State.VICTORY:
			_wave_label.text = "VICTORY"
			_sub_label.text = ""
		WaveManager.State.GAME_OVER:
			_wave_label.text = "GAME OVER"
			_sub_label.text = "Reached wave %d / %d" % [waves.wave, waves.total_waves]
		_:
			_wave_label.text = ""
			_sub_label.text = ""


func _update_mic() -> void:
	var t := "MIC "
	var c := UiKit.DIM
	match Voice.mode:
		Voice.Mode.MUTED:
			t += "muted [M]"
			c = UiKit.BAD
		Voice.Mode.PTT:
			t += "push-to-talk [V]"
			c = UiKit.GOOD if Voice.speaking else UiKit.DIM
		_:
			t += "open [M mutes]"
			c = UiKit.GOOD if Voice.speaking else UiKit.DIM
	_mic.text = t
	_mic.add_theme_color_override("font_color", c)


func _update_team() -> void:
	for c in _team.get_children():
		c.queue_free()
	for p in Net.all_players():
		if p == Net.local_player:
			continue
		var t := "%s  %d" % [p.player_name, p.hp]
		var col := p.color().lightened(0.3)
		if p.status == Player.Status.DOWNED:
			t = "%s  DOWN %ds" % [p.player_name, ceili(p.bleed_left)]
			col = UiKit.BAD
		elif p.status == Player.Status.ELIMINATED:
			t = "%s  out" % p.player_name
			col = UiKit.DIM
		if (p.sync_flags & Player.FLAG_SPEAK) != 0:
			t += "  ))"
		var l := UiKit.label(t, 18, col)
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_team.add_child(l)
