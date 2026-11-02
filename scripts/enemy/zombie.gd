class_name Zombie
extends CharacterBody3D
## Basic pursuer. The host runs all AI and replicates position/state; clients only render.
##
## Behaviour: spawn outside an entrance -> walk to a spot in front of that entrance's barricade -> hit its
## boards until it breaks -> chase the nearest standing player (navmesh) -> melee.

enum State { IDLE, CHASE, ATTACK, BARRICADE, STAGGER }
enum Swing { NONE, PLAYER, BOARD }

signal died(zombie: Zombie)

# --- replicated (host -> all) ---
var sync_pos := Vector3.ZERO
var sync_yaw := 0.0
var sync_speed := 0.0
var state: int = State.IDLE
var hp: int = 100:
	set = _set_hp

var net_id := 0
var max_hp := 100
var move_speed := 2.4
var entrance_idx := 0
var slot_idx := 0

# --- host-only ---
var _dead := false
var _target: Player = null
var _retarget := 0.0
var _swing := Swing.NONE
var _swing_left := 0.0
var _attack_cd := 0.0
var _board_cd := 0.0
var _stagger := 0.0
var _knock := Vector3.ZERO
var _path_timer := 0.0
var _level: SaloonLevel = null

# --- local ---
var _groan_timer := randf_range(1.5, 6.0)

@onready var puppet: Puppet = $Visual
@onready var agent: NavigationAgent3D = $Agent


func setup(data: Dictionary) -> void:
	net_id = data["id"]
	name = "Z%d" % net_id
	position = data["pos"]
	entrance_idx = data["entrance"]
	slot_idx = data["slot"]
	max_hp = data["hp"]
	hp = max_hp
	move_speed = data["speed"]
	sync_pos = position
	sync_yaw = data["yaw"]
	_attack_cd = randf_range(0.0, 0.9) # so a crowd does not swing in lockstep
	rotation.y = sync_yaw


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = GameConfig.L_ENEMIES
	collision_mask = GameConfig.MASK_ENEMY_BODY
	puppet.build(Puppet.Kind.ZOMBIE, Color.WHITE)
	agent.path_desired_distance = 0.5
	agent.target_desired_distance = 1.0
	agent.radius = 0.4
	agent.height = 1.8
	agent.avoidance_enabled = false
	_level = get_tree().get_first_node_in_group("level") as SaloonLevel
	if not multiplayer.is_server():
		agent.queue_free()


static func find_by_id(tree: SceneTree, id: int) -> Zombie:
	for n in tree.get_nodes_in_group("enemies"):
		var z := n as Zombie
		if z != null and z.net_id == id:
			return z
	return null


func is_dead() -> bool:
	return _dead


func _set_hp(v: int) -> void:
	var lost := v < hp
	hp = v
	if lost and is_node_ready():
		puppet.play_hurt()


# =================================================================================================
# Host: AI
# =================================================================================================

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _dead:
		return
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	var desired := Vector3.ZERO
	if _stagger > 0.0:
		_stagger -= delta
		state = State.STAGGER
	elif _swing_left > 0.0:
		_swing_left -= delta
		state = State.ATTACK if _swing == Swing.PLAYER else State.BARRICADE
		if _swing_left <= 0.0:
			_resolve_swing()
	else:
		desired = _think(delta)
	if desired.length() > 0.01:
		desired += _separation()
	_knock = _knock.move_toward(Vector3.ZERO, 12.0 * delta)
	velocity.x = desired.x + _knock.x
	velocity.z = desired.z + _knock.z
	if is_on_floor():
		velocity.y = maxf(velocity.y, 0.0)
	else:
		velocity.y -= GameConfig.GRAVITY * delta
	move_and_slide()
	var flat := Vector3(desired.x, 0.0, desired.z)
	if flat.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, _yaw_to(flat), 1.0 - exp(-10.0 * delta))
	sync_pos = global_position
	sync_yaw = rotation.y
	sync_speed = Vector2(desired.x, desired.z).length()


func _think(delta: float) -> Vector3:
	var bar := _my_barricade()
	var inside := bar != null and bar.is_inside(global_position)
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = 0.4
		_target = _pick_target()
	if bar != null and not inside and bar.boards > 0:
		return _approach_barricade(bar, delta)
	return _chase(delta)


func _approach_barricade(bar: Barricade, delta: float) -> Vector3:
	var out := bar.outward_dir()
	if bar.distance_outside(global_position) <= 1.55:
		# in reach of the boards: face them and hit
		rotation.y = lerp_angle(rotation.y, _yaw_to(-out), 1.0 - exp(-12.0 * delta))
		state = State.BARRICADE
		_board_cd -= delta
		if _board_cd <= 0.0:
			_board_cd = GameConfig.ZOMBIE_BOARD_INTERVAL
			_begin_swing(Swing.BOARD)
		return Vector3.ZERO
	var to := bar.slot_position(slot_idx) - global_position
	to.y = 0.0
	state = State.CHASE
	if to.length() < 0.25:
		return -out * move_speed * 0.5 # shuffle forward into reach
	return to.normalized() * move_speed


func _chase(delta: float) -> Vector3:
	if _target == null or not is_instance_valid(_target) or _target.status != Player.Status.ALIVE:
		state = State.IDLE
		return Vector3.ZERO
	var tp := _target.global_position
	var to := tp - global_position
	to.y = 0.0
	var d := to.length()
	if d <= GameConfig.ZOMBIE_ATTACK_RANGE - 0.15:
		rotation.y = lerp_angle(rotation.y, _yaw_to(to), 1.0 - exp(-12.0 * delta))
		state = State.IDLE
		if _attack_cd <= 0.0:
			_attack_cd = GameConfig.ZOMBIE_ATTACK_COOLDOWN
			_begin_swing(Swing.PLAYER)
		return Vector3.ZERO
	state = State.CHASE
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = 0.25
		agent.target_position = tp
	var next := _next_path_point(tp)
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		dir = to
	return dir.normalized() * move_speed


func _next_path_point(fallback: Vector3) -> Vector3:
	if agent == null or not is_instance_valid(agent):
		return fallback
	var map := agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return fallback
	if agent.is_navigation_finished():
		return fallback
	return agent.get_next_path_position()


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for n in get_tree().get_nodes_in_group("enemies"):
		if n == self:
			continue
		var o := n as Zombie
		if o == null:
			continue
		var away := global_position - o.global_position
		away.y = 0.0
		var d := away.length()
		if d < 0.9 and d > 0.001:
			push += away / d * (0.9 - d) / 0.9
	return push * 2.0


func _pick_target() -> Player:
	var best: Player = null
	var best_d := INF
	for p in Net.all_players():
		if p.status != Player.Status.ALIVE:
			continue
		var d := p.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _my_barricade() -> Barricade:
	if _level == null or entrance_idx < 0 or entrance_idx >= _level.barricades.size():
		return null
	return _level.barricades[entrance_idx]


func _yaw_to(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


func _begin_swing(kind: int) -> void:
	_swing = kind
	_swing_left = GameConfig.ZOMBIE_WINDUP
	fx_attack.rpc()


func _resolve_swing() -> void:
	var kind := _swing
	_swing = Swing.NONE
	if kind == Swing.PLAYER:
		if _target != null and is_instance_valid(_target) and _target.status == Player.Status.ALIVE:
			var flat := _target.global_position - global_position
			flat.y = 0.0
			if flat.length() <= GameConfig.ZOMBIE_ATTACK_RANGE + 0.4:
				_target.srv_take_damage(GameConfig.ZOMBIE_DAMAGE, global_position)
	elif kind == Swing.BOARD:
		var bar := _my_barricade()
		if bar != null and bar.boards > 0 and bar.distance_outside(global_position) <= 2.0:
			bar.srv_damage(GameConfig.ZOMBIE_BOARD_DAMAGE)


# =================================================================================================
# Host: taking hits
# =================================================================================================

func srv_hit(damage: int, knock: Vector3, stagger: float, source: Player) -> void:
	if _dead:
		return
	hp -= damage
	_knock += Vector3(knock.x, 0.0, knock.z)
	if _knock.length() > 10.0:
		_knock = _knock.normalized() * 10.0
	if knock.y > 0.1:
		velocity.y = maxf(velocity.y, knock.y)
	if stagger > 0.0:
		_stagger = maxf(_stagger, stagger)
		_swing_left = 0.0
		_swing = Swing.NONE
	if hp <= 0:
		_die(source)


func srv_shoved(dir: Vector3, from: Player) -> void:
	velocity.y = 2.5
	srv_hit(GameConfig.SHOVE_ENEMY_DAMAGE, dir * GameConfig.SHOVE_ENEMY_H, GameConfig.SHOVE_ENEMY_STAGGER, from)


func srv_explode(damage: int, impulse: Vector3, source: Player) -> void:
	velocity.y = maxf(velocity.y, impulse.y)
	srv_hit(damage, impulse, 1.4, source)


func _die(source: Player) -> void:
	_dead = true
	if source != null and is_instance_valid(source):
		source.kills += 1
		source.weapons.srv_notify_kill()
	Fx.enemy_died.rpc(global_position, rotation.y, _knock * 1.4 + Vector3(0, 3.0, 0))
	died.emit(self)
	queue_free()


# =================================================================================================
# Everyone: visuals
# =================================================================================================

func _process(delta: float) -> void:
	var spd := 0.0
	if multiplayer.is_server():
		spd = sync_speed
	else:
		var k := 1.0 - exp(-GameConfig.REMOTE_SMOOTHING * delta)
		if global_position.distance_to(sync_pos) > GameConfig.REMOTE_SNAP_DISTANCE:
			global_position = sync_pos
		else:
			global_position = global_position.lerp(sync_pos, k)
		rotation.y = lerp_angle(rotation.y, sync_yaw, k)
		spd = sync_speed
	puppet.animate(delta, spd * 1.4, false)
	_groan_timer -= delta
	if _groan_timer <= 0.0:
		_groan_timer = randf_range(4.0, 9.0)
		Sfx.play_at(&"zombie_groan" if randf() < 0.5 else &"zombie_groan2", global_position + Vector3.UP * 1.5, -6.0, randf_range(0.85, 1.15))


@rpc("authority", "call_local", "unreliable")
func fx_attack() -> void:
	puppet.play_attack()
	Sfx.play_at(&"zombie_attack", global_position + Vector3.UP * 1.4, -7.0, randf_range(0.9, 1.1))
