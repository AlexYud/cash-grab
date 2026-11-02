class_name Annex
extends Node3D
## The saloon's east extension, locked behind a gate. Two levers (in the saloon) each cost cash from the shared pot.
## Pulling one latches it for LEVER_WINDOW seconds; pulling the other in time runs the door animation and opens
## the gate for good. A latched lever can be cancelled (refund) and refunds itself if the window runs out, so one
## player can do the whole thing alone: pull, walk over, pull. Host drives it; the few vars replicate.

signal opened

var lever1 := false
var lever2 := false
var latch_left := 0.0 ## seconds left to pull the second lever (replicated, drives the prompt)
var door_t := 0.0 ## 0..1 while the gate is rising (replicated)
var is_open := false:
	set = _set_open

var _door_vis := 0.0 ## smoothed locally so the 10 Hz replication does not look steppy
var _gate_base_y := 0.0

@onready var gate: StaticBody3D = $Gate


func _ready() -> void:
	add_to_group("annex")
	_gate_base_y = gate.position.y
	_apply_gate()


func lever_pulled(slot: int) -> bool:
	return lever1 if slot == 0 else lever2


func door_running() -> bool:
	return lever1 and lever2 and not is_open


# --- host ------------------------------------------------------------------------------------------------

func srv_reset() -> void:
	lever1 = false
	lever2 = false
	latch_left = 0.0
	door_t = 0.0
	is_open = false


## Host: `slot` 0/1 was pulled. The caller already checked can-afford; this takes the money.
func srv_pull(slot: int) -> bool:
	if is_open or door_running() or lever_pulled(slot):
		return false
	var wm := get_tree().get_first_node_in_group("wave_manager") as WaveManager
	if wm == null or not wm.srv_spend(GameConfig.LEVER_COST):
		return false
	if slot == 0:
		lever1 = true
	else:
		lever2 = true
	if not (lever1 and lever2):
		latch_left = GameConfig.LEVER_WINDOW
	else:
		latch_left = 0.0
	return true


## Host: put a latched lever back and give the money back (only before both are down).
func srv_cancel(slot: int) -> bool:
	if is_open or door_running() or not lever_pulled(slot):
		return false
	if slot == 0:
		lever1 = false
	else:
		lever2 = false
	latch_left = 0.0
	_refund()
	return true


func _refund() -> void:
	var wm := get_tree().get_first_node_in_group("wave_manager") as WaveManager
	if wm != null:
		wm.srv_add_cash(GameConfig.LEVER_COST)


func _physics_process(delta: float) -> void:
	_door_vis = move_toward(_door_vis, door_t, delta / GameConfig.DOOR_TIME * 1.5)
	var y := _gate_base_y + _door_vis * 3.4
	if not is_equal_approx(gate.position.y, y):
		gate.position.y = y
	if not multiplayer.is_server():
		return
	if lever1 != lever2 and not is_open:
		latch_left -= delta
		if latch_left <= 0.0:
			latch_left = 0.0
			lever1 = false
			lever2 = false
			_refund()
			var wm := get_tree().get_first_node_in_group("wave_manager") as WaveManager
			if wm != null:
				wm.cl_notice.rpc("The levers slipped back - refunded")
	elif door_running():
		door_t = minf(door_t + delta / GameConfig.DOOR_TIME, 1.0)
		if door_t >= 1.0:
			is_open = true


# --- every peer --------------------------------------------------------------------------------------------

func _set_open(v: bool) -> void:
	var was := is_open
	is_open = v
	if not is_node_ready():
		return
	_apply_gate()
	if v and not was:
		Sfx.play_at(&"explosion", gate.global_position, -8.0, 0.5)
		var wm := get_tree().get_first_node_in_group("wave_manager") as WaveManager
		if wm != null:
			wm.announce.emit("THE EAST ANNEX IS OPEN")
		opened.emit()
	elif not v and not is_zero_approx(_door_vis):
		_door_vis = 0.0 # restart: the gate slams back down


func _apply_gate() -> void:
	gate.collision_layer = 0 if is_open else GameConfig.L_WORLD
	if not is_open and door_t <= 0.0:
		_door_vis = 0.0
