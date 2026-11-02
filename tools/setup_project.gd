extends SceneTree
## Applies the project settings this prototype relies on (autoloads, input map, physics layer names, mic input).
## Re-runnable. Close the editor first (or reload the project afterwards) so it does not overwrite the result:
##   godot --headless --path . --script res://tools/setup_project.gd


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.device = -1 # "any device", what the editor's Input Map writes
	e.physical_keycode = code
	return e


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.device = -1
	e.button_index = button
	return e


func _init() -> void:
	var autoloads := {
		"Net": "res://scripts/autoload/net.gd",
		"Sfx": "res://scripts/autoload/sfx.gd",
		"Fx": "res://scripts/autoload/fx.gd",
		"Voice": "res://scripts/autoload/voice.gd",
	}
	var order := 0
	for key in autoloads:
		ProjectSettings.set_setting("autoload/" + key, "*" + autoloads[key])
		ProjectSettings.set_order("autoload/" + key, order)
		order += 1

	var actions := {
		"move_forward": [_key(KEY_W), _key(KEY_UP)],
		"move_back": [_key(KEY_S), _key(KEY_DOWN)],
		"move_left": [_key(KEY_A), _key(KEY_LEFT)],
		"move_right": [_key(KEY_D), _key(KEY_RIGHT)],
		"jump": [_key(KEY_SPACE)],
		"sprint": [_key(KEY_SHIFT)],
		"fire": [_mouse(MOUSE_BUTTON_LEFT)],
		"reload": [_key(KEY_R)],
		"shove": [_key(KEY_F)],
		"interact": [_key(KEY_E)],
		"grab": [_key(KEY_G)],
		"weapon_1": [_key(KEY_1)],
		"weapon_2": [_key(KEY_2)],
		"weapon_next": [_mouse(MOUSE_BUTTON_WHEEL_DOWN)],
		"weapon_prev": [_mouse(MOUSE_BUTTON_WHEEL_UP)],
		"push_to_talk": [_key(KEY_V)],
		"toggle_mute": [_key(KEY_M)],
		"pause": [_key(KEY_ESCAPE)],
	}
	for a in actions:
		ProjectSettings.set_setting("input/" + a, {"deadzone": 0.5, "events": actions[a]})

	var layers := ["world", "players", "enemies", "barricades", "ragdolls", "props"]
	for i in layers.size():
		ProjectSettings.set_setting("layer_names/3d_physics/layer_%d" % (i + 1), layers[i])

	ProjectSettings.set_setting("application/run/main_scene", "res://scenes/main.tscn")
	ProjectSettings.set_setting("audio/driver/enable_input", true)
	ProjectSettings.set_setting("display/window/size/viewport_width", 1280)
	ProjectSettings.set_setting("display/window/size/viewport_height", 720)
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", 1)

	var err := ProjectSettings.save()
	print("setup_project: saved project.godot (err=%d)" % err)
	quit()
