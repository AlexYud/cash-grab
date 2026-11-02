class_name PlayerInputState
extends RefCounted
## One physics tick of player intent. Filled from the keyboard/mouse, or written directly by a test bot.

var move := Vector2.ZERO ## x: right(+), y: back(+) - same convention as Input.get_vector
var sprint := false
var fire_held := false
var interact_held := false
var grab_held := false
# edge-triggered: true for exactly one physics tick
var jump := false
var fire_pressed := false
var reload := false
var shove := false
var weapon_slot := -1 ## 0/1 to pick a weapon, -1 for no change
var weapon_cycle := 0 ## +1 / -1 from the mouse wheel
# bot overrides: NAN means "use the mouse"
var aim_yaw := NAN
var aim_pitch := NAN


func clear_edges() -> void:
	jump = false
	fire_pressed = false
	reload = false
	shove = false
	weapon_slot = -1
	weapon_cycle = 0


func clear_all() -> void:
	move = Vector2.ZERO
	sprint = false
	fire_held = false
	interact_held = false
	grab_held = false
	clear_edges()
