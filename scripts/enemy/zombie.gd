class_name Zombie
extends CharacterBody3D
## The pursuer family. The host runs all AI and replicates position/state; clients only render.
##
## NORMAL: walks to its entrance, breaks the boards, chases the nearest standing player, melee.
## BRUTE : big and slow, shrugs off knockback, winds up and charges in a straight line (launches what it hits,
##         bonks into walls and stuns itself).
## HUGGER: small and fast, clings to a player (slows them, drains a little HP) until it is shoved off or shot.
## All of them are clumsy: they trip over junk on the ground, over fallen zombies and over each other, and spend
## a moment on the floor (just slowed down, not easier to hurt).

enum State { IDLE, CHASE, ATTACK, BARRICADE, STAGGER, FALLEN, LATCHED, CHARGE, LEAP, DANCE, CLIMB, CEILING, DROP }
enum Swing { NONE, PLAYER, BOARD }
enum Kind { NORMAL, BRUTE, HUGGER, LEAPER, BLOATER, CRAWLER }

signal died(zombie: Zombie)

# --- replicated (host -> all) ---
var sync_pos := Vector3.ZERO
var sync_yaw := 0.0
var sync_speed := 0.0
var state: int = State.IDLE:
	set = _set_state
var hp: int = 100:
	set = _set_hp

var net_id := 0
var kind: int = Kind.NORMAL
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
var _fall_left := 0.0
var _getup_left := 0.0
var _trip_cd := 0.0
var _windup := 0.0
var _charge_left := 0.0
var _charge_cd := 3.0
var _charge_dir := Vector3.ZERO
var _charge_hit: Array[int] = []
var _latched: Player = null
var _hug_tick := 0.0
var _dance_left := 0.0
var _leap_left := 0.0
var _leap_vel := Vector3.ZERO
var _leap_hit := false
var _leap_cd := 2.0
var _bowl_cd := 0.0
var _crawl_phase := 3 ## crawlers: 0 climbing the wall, 1 walking the ceiling, 2 dropping, 3 on the ground like anyone else
var _drop_left := 0.0
var _bleed_left := 0.0
var _bleed_dps := 0.0
var _bleed_accum := 0.0
var _bleed_src: Player = null
var _freeze_left := 0.0
var _freeze_mult := 1.0
var _last_hit_head := false
var _level: SaloonLevel = null

# --- local ---
var _groan_timer := randf_range(1.5, 6.0)
var _vis_vel := Vector3.ZERO ## smoothed velocity of the rendered body (clients have no real one)
var _last_pos := Vector3.ZERO

@onready var puppet: ZombieRig = $Visual
@onready var agent: NavigationAgent3D = $Agent
@onready var body_shape: CollisionShape3D = $Collision
@onready var fallen_shape: CollisionShape3D = $FallenShape


func setup(data: Dictionary) -> void:
	net_id = data["id"]
	name = "Z%d" % net_id
	position = data["pos"]
	kind = data.get("kind", Kind.NORMAL)
	entrance_idx = data["entrance"]
	slot_idx = data["slot"]
	max_hp = data["hp"]
	hp = max_hp
	move_speed = data["speed"]
	sync_pos = position
	sync_yaw = data["yaw"]
	rotation.y = sync_yaw
	_attack_cd = randf_range(0.0, 0.9) # so a crowd does not swing in lockstep
	_trip_cd = randf_range(1.0, 3.0)
	if kind == Kind.CRAWLER:
		_crawl_phase = 0
		state = State.CLIMB


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = GameConfig.L_ENEMIES
	collision_mask = GameConfig.MASK_ENEMY_BODY
	var st := Zombie.style(kind)
	puppet.build(st)
	var s: float = st["scale"]
	puppet.scale = Vector3.ONE * s
	body_shape.scale = Vector3.ONE * s
	body_shape.position.y = 0.85 * s
	fallen_shape.disabled = true
	_apply_surface_shape()
	if state == State.FALLEN: # joined while it was on the floor
		puppet.start_ragdoll(Vector3.ZERO, self)
		body_shape.disabled = true
		fallen_shape.disabled = false
	agent.path_desired_distance = 0.5
	agent.target_desired_distance = 1.0
	agent.radius = 0.4
	agent.height = 1.8
	agent.avoidance_enabled = false
	_level = get_tree().get_first_node_in_group("level") as SaloonLevel
	if not multiplayer.is_server():
		agent.queue_free()


func _exit_tree() -> void:
	if multiplayer.is_server():
		_release_latch()


## Look of each kind (also used for the death ragdoll): shirt colour, skin colour (alpha 0 = default), body scale.
static func style(k: int) -> Dictionary:
	match k:
		Kind.BRUTE:
			return {"kind": k, "shirt": Color(0.5, 0.16, 0.12), "skin": Color(0.58, 0.42, 0.36), "scale": 1.35}
		Kind.HUGGER:
			return {"kind": k, "shirt": Color(0.78, 0.66, 0.18), "skin": Color(0.72, 0.78, 0.36), "scale": 0.7}
		Kind.LEAPER:
			return {"kind": k, "shirt": Color(0.75, 0.25, 0.3), "skin": Color(0.82, 0.5, 0.42), "scale": 0.9}
		Kind.BLOATER:
			return {"kind": k, "shirt": Color(0.45, 0.6, 0.2), "skin": Color(0.62, 0.78, 0.35), "scale": 1.25}
		Kind.CRAWLER:
			return {"kind": k, "shirt": Color(0.2, 0.12, 0.3), "skin": Color(0.5, 0.52, 0.66), "scale": 0.85}
	return {"kind": k, "shirt": Color.WHITE, "skin": Color(0, 0, 0, 0), "scale": 1.0}


static func find_by_id(tree: SceneTree, id: int) -> Zombie:
	for n in tree.get_nodes_in_group("enemies"):
		var z := n as Zombie
		if z != null and z.net_id == id:
			return z
	return null


func is_dead() -> bool:
	return _dead


func is_fallen() -> bool:
	return state == State.FALLEN


func _set_hp(v: int) -> void:
	var lost := v < hp
	hp = v
	if lost and is_node_ready():
		puppet.play_hurt()


## Runs on every peer (the state is replicated): lie down / get up, swap the hit shape to match the pose.
func _set_state(v: int) -> void:
	if v == state:
		return
	var was := state
	state = v
	if not is_node_ready():
		return
	var down := v == State.FALLEN
	body_shape.set_deferred("disabled", down)
	fallen_shape.set_deferred("disabled", not down)
	_apply_surface_shape()
	if down and was != State.FALLEN: # no more control: the skeleton goes limp
		puppet.start_ragdoll(_ragdoll_velocity(), self)
		Sfx.play_at(&"hit_world", global_position + Vector3.UP * 0.3, -2.0, randf_range(0.45, 0.6))
	elif was == State.FALLEN and not down:
		puppet.end_ragdoll()


## A crawler on the wall or hanging from the ceiling has its hit shape where its body really is.
func _apply_surface_shape() -> void:
	var s := puppet.scale.x
	match state:
		State.CLIMB: # lying along the wall, feet at the bottom
			body_shape.rotation.x = PI / 2.0
			body_shape.position = Vector3(0.0, 0.0, 0.85 * s)
		State.CEILING: # hanging by its feet
			body_shape.rotation.x = 0.0
			body_shape.position = Vector3(0.0, -0.85 * s, 0.0)
		_:
			body_shape.rotation.x = 0.0
			body_shape.position = Vector3(0.0, 0.85 * s, 0.0)


## How fast the body was going when it went limp: exact on the host, estimated from the replicated motion elsewhere.
func _ragdoll_velocity() -> Vector3:
	if multiplayer.is_server():
		return Vector3(velocity.x + _knock.x, maxf(velocity.y, 0.0), velocity.z + _knock.z)
	return _vis_vel


# =================================================================================================
# Host: AI
# =================================================================================================

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _dead:
		return
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_trip_cd = maxf(_trip_cd - delta, 0.0)
	_charge_cd = maxf(_charge_cd - delta, 0.0)
	_leap_cd = maxf(_leap_cd - delta, 0.0)
	_bowl_cd = maxf(_bowl_cd - delta, 0.0)
	_tick_status(delta)
	if _dead:
		return
	if _crawl_phase < 3:
		_tick_crawl(delta)
		return
	if _latched != null:
		_tick_latched(delta)
		return
	var desired := Vector3.ZERO
	if _fall_left > 0.0:
		_fall_left -= delta
		state = State.FALLEN
		if _fall_left <= 0.0:
			_getup_left = GameConfig.GETUP_TIME
	elif _getup_left > 0.0:
		_getup_left -= delta
		state = State.STAGGER
	elif _dance_left > 0.0:
		_dance_left -= delta
		state = State.DANCE
	elif _stagger > 0.0:
		_stagger -= delta
		state = State.STAGGER
	elif _leap_left > 0.0:
		desired = _tick_leap(delta)
	elif _windup > 0.0:
		_windup -= delta
		state = State.ATTACK
		if _target != null and is_instance_valid(_target):
			var to := _target.global_position - global_position
			to.y = 0.0
			if to.length() > 0.1:
				rotation.y = lerp_angle(rotation.y, _yaw_to(to), 1.0 - exp(-12.0 * delta))
				_charge_dir = to.normalized()
		if _windup <= 0.0:
			if kind == Kind.LEAPER:
				_begin_leap()
			else:
				_charge_left = GameConfig.BRUTE_CHARGE_TIME
				_charge_hit.clear()
				fx_roar.rpc()
	elif _charge_left > 0.0:
		desired = _tick_charge(delta)
	elif _swing_left > 0.0:
		_swing_left -= delta
		state = State.ATTACK if _swing == Swing.PLAYER else State.BARRICADE
		if _swing_left <= 0.0:
			_resolve_swing()
	else:
		desired = _think(delta)
		_check_trip(desired, delta)
	if desired.length() > 0.01:
		desired += _separation(delta)
	_knock = _knock.move_toward(Vector3.ZERO, 12.0 * delta)
	if _freeze_left > 0.0:
		desired *= _freeze_mult
	velocity.x = desired.x + _knock.x
	velocity.z = desired.z + _knock.z
	if is_on_floor():
		velocity.y = maxf(velocity.y, 0.0)
	else:
		velocity.y -= GameConfig.GRAVITY * delta
	move_and_slide()
	if state == State.FALLEN and _knock.length() > 3.5:
		_bowl_neighbours()
	var flat := Vector3(desired.x, 0.0, desired.z)
	if flat.length() > 0.1 and _charge_left <= 0.0:
		rotation.y = lerp_angle(rotation.y, _yaw_to(flat), 1.0 - exp(-10.0 * delta))
	sync_pos = global_position
	sync_yaw = rotation.y
	sync_speed = Vector2(desired.x, desired.z).length()


## Bleeding and freezing from the card buffs.
func _tick_status(delta: float) -> void:
	if _freeze_left > 0.0:
		_freeze_left -= delta
	if _bleed_left > 0.0:
		_bleed_left -= delta
		_bleed_accum += _bleed_dps * delta
		if _bleed_accum >= 1.0:
			var tick := int(_bleed_accum)
			_bleed_accum -= tick
			var src := _bleed_src if is_instance_valid(_bleed_src) else null
			hp -= tick # not srv_hit: bleeding does not flinch or push
			if hp <= 0:
				_die(src)


func srv_bleed(dps: float, seconds: float, source: Player) -> void:
	if _dead:
		return
	_bleed_dps = maxf(_bleed_dps if _bleed_left > 0.0 else 0.0, dps)
	_bleed_left = seconds
	_bleed_src = source
	fx_status.rpc(0, seconds)


## mult: speed multiplier while frozen (0.5 = half speed).
func srv_freeze(mult: float, seconds: float) -> void:
	if _dead or kind == Kind.BRUTE and mult < 0.5:
		mult = 0.5 # the brute only half-listens to the cold
	_freeze_mult = clampf(mult, 0.2, 1.0)
	_freeze_left = seconds
	fx_status.rpc(1, seconds)


# --- crawler: wall -> ceiling -> drop on someone ------------------------------------------------------------

## Phase 0 climbs the wall to the ceiling, phase 1 walks the ceiling upside down towards the nearest player, phase 2
## is the drop. After landing it is a normal (fast, low) zombie.
func _tick_crawl(delta: float) -> void:
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = 0.4
		_target = _pick_target()
	match _crawl_phase:
		0:
			state = State.CLIMB
			sync_speed = GameConfig.CRAWLER_CLIMB_SPEED
			global_position.y += GameConfig.CRAWLER_CLIMB_SPEED * delta
			if global_position.y >= GameConfig.CEILING_Y:
				global_position.y = GameConfig.CEILING_Y
				_crawl_phase = 1
		1:
			state = State.CEILING
			global_position.y = GameConfig.CEILING_Y
			var dir := Vector3.ZERO
			if _target != null and is_instance_valid(_target):
				var to := _target.global_position - global_position
				to.y = 0.0
				if to.length() <= GameConfig.CRAWLER_DROP_RANGE:
					_begin_drop(to)
					return
				dir = to.normalized()
			sync_speed = move_speed if dir != Vector3.ZERO else 0.0
			if dir != Vector3.ZERO:
				var step := dir * move_speed * (_freeze_mult if _freeze_left > 0.0 else 1.0) * delta
				global_position += step
				rotation.y = lerp_angle(rotation.y, _yaw_to(dir), 1.0 - exp(-10.0 * delta)) # upside down is only the rig's roll: the body still faces where it walks
		2:
			state = State.DROP
			_drop_left -= delta
			velocity.y -= GameConfig.GRAVITY * delta
			move_and_slide()
			sync_speed = 0.0
			if is_on_floor() and _drop_left < 0.45 or _drop_left <= 0.0:
				_land()
	sync_pos = global_position
	sync_yaw = rotation.y


func _begin_drop(to: Vector3) -> void:
	_crawl_phase = 2
	_drop_left = 0.9
	velocity = Vector3(to.x, 0.0, to.z).limit_length(4.0)
	velocity.y = 0.0
	state = State.DROP
	fx_roar.rpc()


func _land() -> void:
	_crawl_phase = 3
	state = State.CHASE
	velocity = Vector3.ZERO
	_attack_cd = 0.4
	for p in Net.all_players():
		var d := p.global_position - global_position
		d.y = 0.0
		if p.status == Player.Status.ALIVE and d.length() < 1.5 and absf(p.global_position.y - global_position.y) < 1.8:
			p.srv_take_damage(damage_amount(), global_position)
			p.srv_launch(d.normalized() * 4.0 + Vector3.UP * 2.5, 0.5)
	srv_trip(Vector3.ZERO) # lands in a heap
	_fall_left = 0.9


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
		return -out * move_speed * 0.5
	return to.normalized() * move_speed


func _chase(delta: float) -> Vector3:
	if _target == null or not is_instance_valid(_target) or _target.status != Player.Status.ALIVE:
		state = State.IDLE
		return Vector3.ZERO
	var tp := _target.global_position
	var to := tp - global_position
	to.y = 0.0
	var d := to.length()
	var in_reach := d <= GameConfig.ZOMBIE_ATTACK_RANGE + 0.2 and _clear_line(tp) # no swinging through walls: go around
	if kind == Kind.HUGGER and d <= 1.35 and in_reach:
		_latch(_target)
		return Vector3.ZERO
	if kind == Kind.BRUTE and _charge_cd <= 0.0 and d > GameConfig.BRUTE_CHARGE_MIN and d < GameConfig.BRUTE_CHARGE_MAX and _clear_line(tp):
		_windup = GameConfig.BRUTE_CHARGE_WINDUP
		_charge_cd = GameConfig.BRUTE_CHARGE_COOLDOWN
		_charge_dir = to.normalized()
		return Vector3.ZERO
	if kind == Kind.LEAPER and _leap_cd <= 0.0 and d > GameConfig.LEAPER_MIN and d < GameConfig.LEAPER_MAX and _clear_line(tp):
		_windup = GameConfig.LEAPER_WINDUP
		_leap_cd = GameConfig.LEAPER_COOLDOWN
		_charge_dir = to.normalized()
		fx_attack.rpc()
		return Vector3.ZERO
	if d <= GameConfig.ZOMBIE_ATTACK_RANGE - 0.15 and kind != Kind.HUGGER and in_reach:
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


func _clear_line(tp: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.9, 0), tp + Vector3(0, 0.9, 0), GameConfig.L_WORLD | GameConfig.L_BARRICADES, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _next_path_point(fallback: Vector3) -> Vector3:
	if agent == null or not is_instance_valid(agent):
		return fallback
	var map := agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return fallback
	if agent.is_navigation_finished():
		return fallback
	return agent.get_next_path_position()


## Soft separation, plus the goofy part: crowded zombies shove each other and sometimes knock one over.
func _separation(delta: float) -> Vector3:
	var push := Vector3.ZERO
	for n in get_tree().get_nodes_in_group("enemies"):
		if n == self:
			continue
		var o := n as Zombie
		if o == null or o.is_dead() or o.is_fallen() or o.state == State.LATCHED:
			continue
		var away := global_position - o.global_position
		away.y = 0.0
		var d := away.length()
		if d < 0.9 and d > 0.001:
			push += away / d * (0.9 - d) / 0.9
			if d < 0.55 and o.kind != Kind.BRUTE and randf() < 0.5 * delta:
				var dir := -away / d # shove the neighbour; now and then it goes down
				o.add_knock(dir * 2.5)
				if randf() < 0.2:
					o.srv_trip(dir * 2.0)
	return push * 2.0


## A limp zombie sliding or flying across the floor flattens whoever stands in its way (a domino of ragdolls).
func _bowl_neighbours() -> void:
	var dir := _knock.normalized()
	for n in get_tree().get_nodes_in_group("enemies"):
		var o := n as Zombie
		if o == null or o == self or o.is_dead() or o.is_fallen() or o.kind == Kind.BRUTE or o.state == State.LATCHED:
			continue
		var d := o.global_position - global_position
		d.y = 0.0
		if d.length() < 1.1:
			o.srv_trip(dir * minf(_knock.length(), 7.0) * 0.8)
			_knock *= 0.7 # it gave up some speed doing so


func _check_trip(desired: Vector3, delta: float) -> void:
	if _trip_cd > 0.0 or kind == Kind.BRUTE or desired.length() < 1.0:
		return
	var tripped := false
	for n in get_tree().get_nodes_in_group("trip_spots"):
		var m := n as Node3D
		var d := m.global_position - global_position
		d.y = 0.0
		if d.length() < 0.75:
			tripped = randf() < GameConfig.TRIP_CHANCE
			_trip_cd = 2.0 # one roll per obstacle pass
			break
	if not tripped:
		for n in get_tree().get_nodes_in_group("enemies"):
			var o := n as Zombie
			if o != null and o != self and o.is_fallen() and o.global_position.distance_to(global_position) < 0.95:
				tripped = randf() < GameConfig.TRIP_CHANCE
				_trip_cd = 2.0
				break
	if not tripped and randf() < GameConfig.TRIP_RANDOM_PER_SEC * delta:
		tripped = true
	if tripped:
		srv_trip(desired.normalized() * 2.5)


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


func damage_amount() -> int:
	match kind:
		Kind.BRUTE:
			return GameConfig.BRUTE_DAMAGE
		Kind.LEAPER:
			return GameConfig.LEAPER_DAMAGE
		Kind.BLOATER:
			return GameConfig.BLOATER_DAMAGE
		Kind.CRAWLER:
			return GameConfig.CRAWLER_DAMAGE
	return GameConfig.ZOMBIE_DAMAGE


func _begin_swing(swing_kind: int) -> void:
	_swing = swing_kind as Swing
	_swing_left = GameConfig.ZOMBIE_WINDUP
	fx_attack.rpc()
	if swing_kind == Swing.PLAYER: # wild swings sometimes whack a neighbour
		for n in get_tree().get_nodes_in_group("enemies"):
			var o := n as Zombie
			if o != null and o != self and not o.is_fallen() and o.kind != Kind.BRUTE and o.global_position.distance_to(global_position) < 1.1 and randf() < 0.18:
				var away := o.global_position - global_position
				away.y = 0.0
				o.srv_trip(away.normalized() * 3.0)


func _resolve_swing() -> void:
	var swing_kind := _swing
	_swing = Swing.NONE
	if swing_kind == Swing.PLAYER:
		if _target != null and is_instance_valid(_target) and _target.status == Player.Status.ALIVE:
			var flat := _target.global_position - global_position
			flat.y = 0.0
			if flat.length() <= GameConfig.ZOMBIE_ATTACK_RANGE + 0.4:
				_target.srv_take_damage(damage_amount(), global_position)
	elif swing_kind == Swing.BOARD:
		var bar := _my_barricade()
		if bar != null and bar.boards > 0 and bar.distance_outside(global_position) <= 2.0:
			var mult := GameConfig.BRUTE_BOARD_MULT if kind == Kind.BRUTE else (0.5 if kind == Kind.HUGGER else 1.0)
			bar.srv_damage(GameConfig.ZOMBIE_BOARD_DAMAGE * mult)


# --- brute charge ------------------------------------------------------------------------------------

func _tick_charge(delta: float) -> Vector3:
	_charge_left -= delta
	state = State.CHARGE
	rotation.y = _yaw_to(_charge_dir)
	for p in Net.all_players():
		if p.status != Player.Status.ALIVE or _charge_hit.has(p.peer_id):
			continue
		var d := p.global_position - global_position
		d.y = 0.0
		if d.length() < 1.45:
			_charge_hit.append(p.peer_id)
			p.srv_take_damage(damage_amount(), global_position)
			p.srv_launch(_charge_dir * 11.0 + Vector3.UP * 4.5, 0.9, true)
			_charge_left = 0.0
			_stagger = 0.6
	for n in get_tree().get_nodes_in_group("enemies"):
		var o := n as Zombie
		if o != null and o != self and o.kind != Kind.BRUTE and not o.is_fallen() and o.global_position.distance_to(global_position) < 1.3:
			o.srv_trip(_charge_dir * 6.0) # bowling pins
	if _charge_left > 0.0 and _charge_left < GameConfig.BRUTE_CHARGE_TIME - 0.25:
		for i in get_slide_collision_count():
			if get_slide_collision(i).get_normal().y < 0.5: # ran into a wall: bonk
				_charge_left = 0.0
				_stagger = 1.4
				fx_bonk.rpc()
				break
	return _charge_dir * GameConfig.BRUTE_CHARGE_SPEED if _charge_left > 0.0 else Vector3.ZERO


# --- leaper -------------------------------------------------------------------------------------------

func _begin_leap() -> void:
	var dist := 5.0
	if _target != null and is_instance_valid(_target):
		var to := _target.global_position - global_position
		to.y = 0.0
		dist = to.length()
		if dist > 0.1:
			_charge_dir = to.normalized()
	_leap_vel = _charge_dir * clampf(dist / 0.68, 4.0, 11.0)
	velocity.y = 5.5
	_leap_left = 1.0
	_leap_hit = false
	state = State.LEAP
	fx_roar.rpc()


func _tick_leap(delta: float) -> Vector3:
	_leap_left -= delta
	state = State.LEAP
	rotation.y = _yaw_to(_leap_vel)
	if not _leap_hit:
		for p in Net.all_players():
			var d := p.global_position - global_position
			d.y = 0.0
			if p.status == Player.Status.ALIVE and d.length() < 1.2 and absf(p.global_position.y - global_position.y) < 1.6:
				_leap_hit = true
				p.srv_take_damage(damage_amount(), global_position)
				p.srv_launch(_charge_dir * 5.0 + Vector3.UP * 3.0, 0.6) # pounced: bowled over
				break
	if is_on_floor() and _leap_left < 0.9 or _leap_left <= 0.0:
		_leap_left = 0.0
		srv_trip(_charge_dir * 2.0) # lands in a heap, hit or miss
		_fall_left = 1.0 if _leap_hit else _fall_left # a hit leaves it dazed for less time than a faceplant
		return Vector3.ZERO
	return _leap_vel


# --- bloater -----------------------------------------------------------------------------------------

func _burst() -> void:
	Fx.goo_burst.rpc(global_position)
	for p in Net.all_players():
		var d := p.global_position - global_position
		d.y = 0.0
		if p.status == Player.Status.ALIVE and d.length() < GameConfig.BLOATER_BURST_RADIUS:
			p.srv_take_damage(8, global_position)
			p.srv_launch(d.normalized() * 9.0 + Vector3.UP * 4.0, 0.7)
	for n in get_tree().get_nodes_in_group("enemies"):
		var o := n as Zombie
		if o != null and o != self and not o.is_dead():
			var d := o.global_position - global_position
			d.y = 0.0
			if d.length() < GameConfig.BLOATER_BURST_RADIUS:
				o.srv_trip(d.normalized() * 5.0)


# --- hugger ------------------------------------------------------------------------------------------

func _latch(p: Player) -> void:
	_latched = p
	p.hugged += 1
	state = State.LATCHED
	collision_layer = GameConfig.L_HUG
	collision_mask = 0
	_hug_tick = 0.0
	fx_attack.rpc()


func _release_latch() -> void:
	if _latched != null and is_instance_valid(_latched):
		_latched.hugged = maxi(_latched.hugged - 1, 0)
	_latched = null


func _unlatch(stun: float) -> void:
	_release_latch()
	collision_layer = GameConfig.L_ENEMIES
	collision_mask = GameConfig.MASK_ENEMY_BODY
	_stagger = stun
	state = State.STAGGER


func _tick_latched(delta: float) -> void:
	if not is_instance_valid(_latched) or _latched.status != Player.Status.ALIVE:
		_unlatch(1.0)
		return
	var fwd := Basis(Vector3.UP, _latched.rotation.y) * Vector3(0, 0, -1)
	global_position = _latched.global_position + fwd * 0.45 + Vector3(0, 0.15, 0)
	rotation.y = _latched.rotation.y + PI
	velocity = Vector3.ZERO
	sync_pos = global_position
	sync_yaw = rotation.y
	sync_speed = 0.0
	state = State.LATCHED
	_hug_tick += delta
	if _hug_tick >= 0.5:
		_hug_tick = 0.0
		_latched.srv_take_damage(int(round(GameConfig.HUGGER_DPS * 0.5)), global_position)


# =================================================================================================
# Host: taking hits and other external pushes
# =================================================================================================

func add_knock(v: Vector3) -> void:
	_knock += Vector3(v.x, 0.0, v.z)


## Falls flat for a moment (state replication does the visuals on every peer).
func srv_trip(push: Vector3 = Vector3.ZERO) -> void:
	if _dead or kind == Kind.BRUTE or _fall_left > 0.0 or _latched != null or _crawl_phase < 3:
		return
	_fall_left = randf_range(GameConfig.FALL_MIN, GameConfig.FALL_MAX)
	_swing_left = 0.0
	_swing = Swing.NONE
	_windup = 0.0
	_charge_left = 0.0
	_leap_left = 0.0
	_dance_left = 0.0
	_trip_cd = GameConfig.TRIP_COOLDOWN + _fall_left
	add_knock(push)
	state = State.FALLEN
	if push.length() > 0.1:
		fx_kick.rpc(push * 0.6 + Vector3.UP * 1.5)


## Disco Blaster: the zombie dances instead of attacking for a few seconds.
func srv_dance(seconds: float) -> void:
	if _dead:
		return
	if _latched != null:
		_unlatch(0.0)
	_dance_left = minf(seconds, 1.5) if kind == Kind.BRUTE else seconds
	_swing_left = 0.0
	_swing = Swing.NONE
	_windup = 0.0
	_charge_left = 0.0
	_leap_left = 0.0
	state = State.DANCE


## Yank Gun: reeled in toward the shooter, tumbling.
func srv_yank(origin: Vector3) -> void:
	if _dead:
		return
	if _latched != null:
		_unlatch(0.5)
	var to := origin - global_position
	to.y = 0.0
	add_knock(to.normalized() * minf(to.length() * 2.4 + 4.0, 14.0) * (0.5 if kind == Kind.BRUTE else 1.0))
	srv_trip(Vector3.ZERO)


## Boing Gun: launched into the air, comes down in a heap.
func srv_boing() -> void:
	if _dead:
		return
	if _latched != null:
		_unlatch(0.0)
	_fall_left = 0.0 # so srv_trip is allowed even if it was already down
	srv_trip(Vector3.ZERO)
	velocity.y = 9.0 if kind != Kind.BRUTE else 4.0
	fx_kick.rpc(Vector3(0.0, velocity.y * 0.7, 0.0))
	if kind == Kind.BRUTE:
		_stagger = 0.8


## A fast-flying player (thrown, shoved, blown up) ploughs into this zombie.
func srv_bowled(dir: Vector3, source: Player) -> void:
	if _dead or _bowl_cd > 0.0:
		return
	_bowl_cd = 1.0
	if _latched != null:
		_unlatch(1.0)
	add_knock(dir * 6.0)
	srv_trip(dir * 6.0)
	srv_hit(GameConfig.BOWLING_DAMAGE, Vector3.ZERO, 0.0, source)


func srv_hit(damage: int, knock: Vector3, stagger: float, source: Player, head: bool = false) -> void:
	if _dead:
		return
	hp -= damage
	_last_hit_head = head # only a headshot that lands the killing blow pays the bonus
	var k := 0.25 if kind == Kind.BRUTE else 1.0 # the brute barely notices being pushed
	if _crawl_phase < 3:
		k = 0.0 # stuck to a wall or the ceiling: shots hurt but do not push or stun
		stagger = 0.0
	add_knock(knock * k)
	if _knock.length() > 10.0:
		_knock = _knock.normalized() * 10.0
	if knock.y > 0.1 and kind != Kind.BRUTE:
		velocity.y = maxf(velocity.y, knock.y)
	if stagger > 0.0:
		if _latched != null:
			_unlatch(1.5) # shoved or shot off the player
		if kind == Kind.BRUTE:
			stagger = minf(stagger, 0.3)
		_stagger = maxf(_stagger, stagger)
		_swing_left = 0.0
		_swing = Swing.NONE
		_windup = 0.0 if kind != Kind.BRUTE else _windup
	if hp <= 0:
		_die(source)


func srv_shoved(dir: Vector3, from: Player) -> void:
	velocity.y = 2.5 if kind != Kind.BRUTE else 0.0
	if _latched != null:
		_unlatch(1.8)
	srv_hit(GameConfig.SHOVE_ENEMY_DAMAGE, dir * GameConfig.SHOVE_ENEMY_H, GameConfig.SHOVE_ENEMY_STAGGER, from)
	if not _dead and (kind == Kind.HUGGER or randf() < GameConfig.SHOVE_TRIP_CHANCE):
		srv_trip(dir * 3.0) # sent tumbling: the skeleton goes limp


func srv_explode(damage: int, impulse: Vector3, source: Player) -> void:
	if _latched != null:
		_unlatch(1.0)
	velocity.y = maxf(velocity.y, impulse.y)
	srv_hit(damage, impulse, 1.4, source)
	if not _dead:
		srv_trip(Vector3.ZERO)
		fx_kick.rpc(impulse * 0.8) # blown across the room, limbs everywhere


func _die(source: Player) -> void:
	_dead = true
	_release_latch()
	if source != null and is_instance_valid(source):
		source.kills += 1
		source.weapons.srv_notify_kill()
	if kind == Kind.BLOATER:
		_burst()
	var wm := get_tree().get_first_node_in_group("wave_manager") as WaveManager
	if wm != null:
		wm.srv_add_cash((GameConfig.CASH_KILL if kind == Kind.NORMAL else GameConfig.CASH_KILL_SPECIAL) + (GameConfig.CASH_HEADSHOT_BONUS if _last_hit_head else 0))
	Fx.srv_try_snack(global_position, kind)
	Fx.enemy_died.rpc(global_position, rotation.y, _knock * 1.4 + Vector3(0, 3.0, 0), kind, net_id)
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
	if delta > 0.0:
		_vis_vel = _vis_vel.lerp((global_position - _last_pos) / delta, 1.0 - exp(-12.0 * delta))
	_last_pos = global_position
	puppet.animate(delta, spd, state, state == State.LEAP)
	_groan_timer -= delta
	if _groan_timer <= 0.0:
		_groan_timer = randf_range(4.0, 9.0)
		var pitch := randf_range(0.85, 1.15) * (0.7 if kind == Kind.BRUTE else (1.5 if kind == Kind.HUGGER else 1.0))
		Sfx.play_at(&"zombie_groan" if randf() < 0.5 else &"zombie_groan2", global_position + Vector3.UP * 1.5, -6.0, pitch)


@rpc("authority", "call_local", "unreliable")
func fx_attack() -> void:
	puppet.play_attack()
	Sfx.play_at(&"zombie_attack", global_position + Vector3.UP * 1.4, -7.0, randf_range(0.9, 1.1) * (1.6 if kind == Kind.HUGGER else 1.0))


## A shove or blast that happens as the zombie goes limp: every peer's ragdoll gets it too.
@rpc("authority", "call_local", "unreliable")
func fx_kick(v: Vector3) -> void:
	puppet.kick(v)


## A colour wash on the body for a while: 0 bleeding (red), 1 frozen (blue).
@rpc("authority", "call_local", "unreliable")
func fx_status(what: int, seconds: float) -> void:
	puppet.set_tint(Color(1.0, 0.45, 0.45) if what == 0 else Color(0.55, 0.8, 1.35), seconds)


@rpc("authority", "call_local", "unreliable")
func fx_roar() -> void:
	Sfx.play_at(&"zombie_groan2", global_position + Vector3.UP * 1.5, 0.0, 0.55)


@rpc("authority", "call_local", "unreliable")
func fx_bonk() -> void:
	Sfx.play_at(&"hit_world", global_position + Vector3.UP, 2.0, 0.4)
	Fx.camera_shake.emit(0.4, global_position)
