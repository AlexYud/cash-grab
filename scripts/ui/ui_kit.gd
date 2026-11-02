class_name UiKit
extends RefCounted
## Tiny helpers so the code-built screens look consistent.

const ACCENT := Color(0.96, 0.73, 0.26)
const PANEL := Color(0.07, 0.08, 0.1, 0.94)
const TEXT := Color(0.93, 0.92, 0.88)
const DIM := Color(0.64, 0.64, 0.62)
const BAD := Color(0.95, 0.36, 0.3)
const GOOD := Color(0.46, 0.86, 0.5)

const SETTINGS_PATH := "user://settings.cfg"


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	t.set_stylebox("panel", "PanelContainer", _flat(PANEL, 14, ACCENT.darkened(0.45), 2))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var c := Color(0.17, 0.18, 0.22)
		match state:
			"hover":
				c = Color(0.26, 0.27, 0.33)
			"pressed":
				c = ACCENT.darkened(0.35)
			"disabled":
				c = Color(0.11, 0.11, 0.13)
		if state == "focus":
			t.set_stylebox(state, "Button", _flat(Color(0, 0, 0, 0), 6, ACCENT, 2))
		else:
			t.set_stylebox(state, "Button", _flat(c, 6))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", DIM.darkened(0.3))
	t.set_stylebox("normal", "LineEdit", _flat(Color(0.12, 0.13, 0.16), 6, Color(0.3, 0.3, 0.36), 1))
	t.set_stylebox("focus", "LineEdit", _flat(Color(0.12, 0.13, 0.16), 6, ACCENT, 2))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("background", "ProgressBar", _flat(Color(0.1, 0.1, 0.12, 0.85), 4))
	t.set_stylebox("fill", "ProgressBar", _flat(GOOD, 4))
	return t


static func _flat(color: Color, radius: int, border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border_w)
	s.border_color = border
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func label(text: String, size: int = 20, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 42)
	return b


static func bar(fill: Color, size: Vector2) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = size
	p.show_percentage = false
	p.min_value = 0.0
	p.max_value = 1.0
	var s := _flat(fill, 4)
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	p.add_theme_stylebox_override("fill", s)
	return p


static func margin(child: Control, px: int) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, px)
	m.add_child(child)
	return m


static func load_settings() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	return cfg
