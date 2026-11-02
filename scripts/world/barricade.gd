class_name Barricade
extends Node3D
## A fixed entrance covered by boards. Local +Z points outward (toward the street).
## Host: zombies remove boards, players holding E restore them. `boards` replicates; everything else is derived.

const MAX_BOARDS := 5

@export var index := 0
@export var annex := false ## an annex window: zombies only come through it once the annex is open

var boards: int = MAX_BOARDS:
	set = _set_boards
var repair_progress := 0.0 ## 0..1 toward the next board (replicated, drives the HUD prompt)

var _damage_accum := 0.0

@onready var blocker: StaticBody3D = $Blocker
@onready var planks: Node3D = $Planks
@onready var slots: Node3D = $Slots


func _ready() -> void:
	add_to_group("barricades")
	blocker.collision_layer = GameConfig.L_BARRICADES if boards > 0 else 0
	blocker.collision_mask = 0
	_apply_boards()


# --- geometry helpers ------------------------------------------------------------------------------

func outward_dir() -> Vector3:
	return global_basis.z.normalized()


## Signed distance from the doorway plane; positive = street side.
func distance_outside(pos: Vector3) -> float:
	return (pos - global_position).dot(outward_dir())


func lateral(pos: Vector3) -> float:
	return (pos - global_position).dot(global_basis.x.normalized())


func is_inside(pos: Vector3) -> bool:
	return distance_outside(pos) < -0.5


## Whether zombies may spawn for this entrance right now.
func is_active() -> bool:
	if not annex:
		return true
	var a := get_tree().get_first_node_in_group("annex") as Annex
	return a != null and a.is_open


func slot_position(i: int) -> Vector3:
	return (slots.get_child(i % slots.get_child_count()) as Node3D).global_position


## True when a player at `pos` may hold E to add a board here.
func can_repair_from(pos: Vector3) -> bool:
	if boards >= MAX_BOARDS:
		return false
	if absf(lateral(pos)) > 2.4 or absf(distance_outside(pos)) > GameConfig.INTERACT_REACH:
		return false
	return not _occupied()


## An open doorway cannot be boarded up while something is standing in it.
func _occupied() -> bool:
	if boards > 0:
		return false
	for group in ["players", "enemies"]:
		for n in get_tree().get_nodes_in_group(group):
			var b := n as Node3D
			if b != null and absf(distance_outside(b.global_position)) < 0.9 and absf(lateral(b.global_position)) < 1.8:
				return true
	return false


# --- host logic --------------------------------------------------------------------------------------

func srv_damage(amount: float) -> void:
	if boards <= 0:
		return
	_damage_accum += amount
	while _damage_accum >= GameConfig.BOARD_HP and boards > 0:
		_damage_accum -= GameConfig.BOARD_HP
		boards -= 1
	repair_progress = 0.0


func srv_reset() -> void:
	boards = MAX_BOARDS
	repair_progress = 0.0
	_damage_accum = 0.0


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or boards >= MAX_BOARDS:
		return
	var workers := 0
	for p in Net.all_players():
		if p.status == Player.Status.ALIVE and p.interact_kind == Player.Interact.REPAIR and p.interact_target == index \
				and can_repair_from(p.global_position):
			workers += 1
	if workers == 0:
		return
	repair_progress += workers * delta / GameConfig.REPAIR_TIME_PER_BOARD
	if repair_progress >= 1.0:
		repair_progress = 0.0
		_damage_accum = 0.0
		boards += 1
		var wm := get_tree().get_first_node_in_group("wave_manager") as WaveManager
		if wm != null:
			wm.srv_add_cash(GameConfig.CASH_PER_BOARD)


# --- visuals (run on every peer when `boards` changes) -------------------------------------------------

func _set_boards(v: int) -> void:
	var old := boards
	boards = clampi(v, 0, MAX_BOARDS)
	if not is_node_ready() or boards == old:
		return
	_apply_boards()
	if boards < old:
		for i in range(boards, old):
			var plank := planks.get_child(i) as Node3D
			Fx.plank_debris(plank.global_position, outward_dir())
		Sfx.play_at(&"board_break", global_position + Vector3.UP, 0.0, randf_range(0.9, 1.1))
	else:
		Sfx.play_at(&"hammer", global_position + Vector3.UP, 0.0, randf_range(0.95, 1.1))


func _apply_boards() -> void:
	for i in planks.get_child_count():
		(planks.get_child(i) as Node3D).visible = i < boards
	blocker.collision_layer = GameConfig.L_BARRICADES if boards > 0 else 0
