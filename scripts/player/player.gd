class_name Player
extends CharacterBody3D
## One player. Node name == peer id.
##
## Authority split (see README "Network model"):
##   - the owning peer simulates movement/aiming and replicates it (TransformSync: sync_* vars);
##   - the host owns everything with consequences: HP, downed/revive, grabs, shoves, launches (StateSync).
## Clients ask the host to do things through srv_* RPCs; the host answers with cl_* RPCs / replicated state.

enum Status { ALIVE, DOWNED, ELIMINATED }
enum Interact { NONE, REPAIR, REVIVE }

const FLAG_SPRINT := 1
const FLAG_AIR := 2
const FLAG_RELOAD := 4
const FLAG_SPEAK := 8
const FLAG_STAGGER := 16

signal status_changed(player: Player, old_status: int, new_status: int)

# --- identity ---
var peer_id := 1
var player_name := "Player"
var color_idx := 0

# --- replicated: owner -> everyone (TransformSync) ---
var sync_pos := Vector3.ZERO
var sync_yaw := 0.0
var sync_pitch := 0.0
var sync_vel := Vector3.ZERO
var sync_flags := 0
var sync_weapon := 0

# --- replicated: host -> everyone (StateSync) ---
var hp: int = GameConfig.PLAYER_MAX_HP
var status: int = Status.ALIVE:
	set = _set_status
var bleed_left := 0.0
var revive_progress := 0.0
var grabbed_by := 0 ## peer id of whoever is holding me (0 = nobody)
var grabbing := 0 ## peer id I am holding
var kills := 0
var hugged := 0 ## how many Huggers are clinging to me (slows me down)

# --- host-only bookkeeping ---
var interact_kind: int = Interact.NONE
var interact_target := 0
var _invuln := 0.0
var _since_hit := 99.0
var _regen_accum := 0.0
var _last_shove := -99.0

# --- local (owner) state ---
var input := PlayerInputState.new()
var bot_controlled := false
var yaw := 0.0
var pitch := 0.0
var stagger_time := 0.0
var shove_cd := 0.0
var recoil := 0.0 ## radians of camera kick, decays
var cam_roll := 0.0
var shake := 0.0
var damage_flash := 0.0
var prompt_text := ""
var prompt_progress := -1.0
var spectate_index := 0
var _prev_pos := Vector3.ZERO
var _curr_pos := Vector3.ZERO
var _eye := GameConfig.EYE_HEIGHT
var _bob := 0.0
var _grab_sent := false
var _sent_kind := 0
var _sent_target := 0

# --- remote smoothing ---
var _remote_pitch := 0.0
var _tag_timer := 0.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapons: PlayerWeapons = $Weapons
@onready var puppet: Puppet = $Visual
@onready var nametag: Label3D = $NameTag
@onready var voice_out: AudioStreamPlayer3D = $VoiceOut
@onready var grab_line: MeshInstance3D = $GrabLine


## Called by the spawner's spawn function on every peer, before the node enters the tree.
func setup(data: Dictionary) -> void:
	peer_id = data["peer"]
	player_name = data["name"]
	color_idx = data["color"]
	name = str(peer_id)
	position = data["pos"]
	rotation.y = data.get("yaw", 0.0)
	yaw = rotation.y
	sync_pos = position
	sync_yaw = yaw
	_prev_pos = position
	_curr_pos = position
	set_multiplayer_authority(peer_id)
	$StateSync.set_multiplayer_authority(1) # host owns HP/downed/grab state


func _ready() -> void:
	add_to_group("players")
	collision_layer = GameConfig.L_PLAYERS
	collision_mask = GameConfig.MASK_PLAYER_BODY
	floor_snap_length = 0.35
	puppet.build(Puppet.Kind.PLAYER, Net.PLAYER_COLORS[color_idx % Net.PLAYER_COLORS.size()])
	nametag.text = player_name
	nametag.modulate = Net.PLAYER_COLORS[color_idx % Net.PLAYER_COLORS.size()].lightened(0.35)
	weapons.setup(self)
	head.top_level = true
	if is_multiplayer_authority():
		_become_local()
	else:
		_become_remote()
	_apply_status_visuals()


func _become_local() -> void:
	Net.local_player = self
	camera.current = true
	puppet.visible = false
	nametag.visible = false
	weapons.show_viewmodel(true)
	Fx.camera_shake.connect(_on_camera_shake)


func _become_remote() -> void:
	camera.current = false
	weapons.show_viewmodel(false)
	voice_out.stream = AudioStreamGenerator.new()
	(voice_out.stream as AudioStreamGenerator).mix_rate = Voice.RATE
	(voice_out.stream as AudioStreamGenerator).buffer_length = 0.4
	voice_out.play()


func _exit_tree() -> void:
	if Net.local_player == self:
		Net.local_player = null
	if multiplayer.is_server() and is_instance_valid(Net.players_root):
		# a player that disconnects (or is removed) must never leave anyone held by a ghost
		_srv_ungrab()
		for p in Net.all_players():
			if p != self and p.grabbed_by == peer_id:
				p.grabbed_by = 0
			if p != self and p.grabbing == peer_id:
				p.grabbing = 0


func is_local() -> bool:
	return is_multiplayer_authority()


func is_alive() -> bool:
	return status == Status.ALIVE


func color() -> Color:
	return Net.PLAYER_COLORS[color_idx % Net.PLAYER_COLORS.size()]


# =================================================================================================
# Input
# =================================================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or bot_controlled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not Net.ui_blocking:
		var s: float = GameConfig.MOUSE_SENS * Net.sens_scale
		yaw -= event.relative.x * s
		pitch = clampf(pitch - event.relative.y * s, -1.5, 1.5)


func _gather_input() -> void:
	if bot_controlled:
		return
	var i := input
	if Net.ui_blocking:
		i.clear_all()
		return
	i.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	i.sprint = Input.is_action_pressed("sprint")
	i.jump = Input.is_action_just_pressed("jump")
	i.fire_held = Input.is_action_pressed("fire")
	i.fire_pressed = Input.is_action_just_pressed("fire")
	i.reload = Input.is_action_just_pressed("reload")
	i.shove = Input.is_action_just_pressed("shove")
	i.interact_held = Input.is_action_pressed("interact")
	i.grab_held = Input.is_action_pressed("grab")
	i.weapon_slot = 0 if Input.is_action_just_pressed("weapon_1") else (1 if Input.is_action_just_pressed("weapon_2") else -1)
	i.weapon_cycle = 1 if Input.is_action_just_pressed("weapon_next") else (-1 if Input.is_action_just_pressed("weapon_prev") else 0)


# =================================================================================================
# Per-frame
# =================================================================================================

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_srv_tick(delta)
	if is_multiplayer_authority():
		_local_tick(delta)


func _local_tick(delta: float) -> void:
	_gather_input()
	if not is_nan(input.aim_yaw):
		yaw = input.aim_yaw
	if not is_nan(input.aim_pitch):
		pitch = input.aim_pitch
	stagger_time = maxf(stagger_time - delta, 0.0)
	shove_cd = maxf(shove_cd - delta, 0.0)
	_prev_pos = _curr_pos
	match status:
		Status.ALIVE:
			_tick_alive(delta)
		Status.DOWNED:
			_tick_downed(delta)
		_:
			velocity = Vector3.ZERO
	rotation.y = yaw
	if status != Status.ELIMINATED:
		move_and_slide()
	_curr_pos = global_position
	_update_interactions()
	_publish()
	input.clear_edges()


func _speed_multiplier() -> float:
	var m := GameConfig.HUGGER_SLOW if hugged > 0 else 1.0
	if grabbing != 0:
		var t := Net.get_player(grabbing)
		if t != null and t.status == Status.DOWNED:
			return m * GameConfig.DRAG_SLOW
		return m * GameConfig.GRAB_SLOW
	return m


func _tick_alive(delta: float) -> void:
	var on_floor := is_on_floor()
	weapons.tick(delta, input)
	if input.shove and shove_cd <= 0.0 and grabbing == 0:
		_do_shove()
	_update_grab_input()

	var wish := Basis(Vector3.UP, yaw) * Vector3(input.move.x, 0.0, input.move.y)
	var sprinting := input.sprint and input.move.y < -0.1 and not input.fire_held and grabbing == 0 and hugged == 0 and not weapons.is_reloading()
	var speed := GameConfig.SPRINT_SPEED if sprinting else GameConfig.WALK_SPEED
	speed *= _speed_multiplier()
	var target := Vector2(wish.x, wish.z) * speed
	var staggered := stagger_time > 0.0
	var accel := GameConfig.GROUND_ACCEL if on_floor else GameConfig.AIR_ACCEL
	if staggered:
		target *= GameConfig.STAGGER_CONTROL
		accel = GameConfig.STAGGER_GROUND_ACCEL if on_floor else GameConfig.STAGGER_AIR_ACCEL
	if grabbed_by != 0:
		var pull := _grab_pull_velocity()
		target = pull + target * GameConfig.GRAB_TARGET_INPUT
		accel = GameConfig.GROUND_ACCEL
	var h := Vector2(velocity.x, velocity.z).move_toward(target, accel * delta)
	velocity.x = h.x
	velocity.z = h.y
	if on_floor:
		velocity.y = maxf(velocity.y, 0.0)
		if input.jump and not staggered and grabbed_by == 0 and hugged == 0:
			velocity.y = GameConfig.JUMP_VELOCITY
	else:
		velocity.y -= GameConfig.GRAVITY * delta


func _tick_downed(delta: float) -> void:
	weapons.tick(delta, input)
	var wish := Basis(Vector3.UP, yaw) * Vector3(input.move.x, 0.0, input.move.y)
	var target := Vector2(wish.x, wish.z) * GameConfig.CRAWL_SPEED
	var accel := GameConfig.GROUND_ACCEL
	if grabbed_by != 0:
		target = _grab_pull_velocity() + target * 0.2
	elif stagger_time > 0.0:
		accel = GameConfig.STAGGER_GROUND_ACCEL
	var h := Vector2(velocity.x, velocity.z).move_toward(target, accel * delta)
	velocity.x = h.x
	velocity.z = h.y
	if is_on_floor():
		velocity.y = maxf(velocity.y, 0.0)
	else:
		velocity.y -= GameConfig.GRAVITY * delta


## Horizontal velocity that carries me toward the hold point of whoever is grabbing me.
func _grab_pull_velocity() -> Vector2:
	var g := Net.get_player(grabbed_by)
	if g == null:
		return Vector2.ZERO
	var fwd := Basis(Vector3.UP, g.rotation.y) * Vector3(0, 0, -1)
	var hold := g.global_position + fwd * GameConfig.GRAB_HOLD_DISTANCE
	if status == Status.DOWNED:
		hold = g.global_position - fwd * (GameConfig.GRAB_HOLD_DISTANCE - 0.2) # dragged behind
	var to := hold - global_position
	to.y = 0.0
	var d := to.length()
	if d < 0.05:
		return Vector2.ZERO
	var s := minf(GameConfig.GRAB_PULL_SPEED, d * GameConfig.GRAB_PULL_GAIN)
	to = to / d * s
	return Vector2(to.x, to.z)


func _publish() -> void:
	sync_pos = global_position
	sync_yaw = yaw
	sync_pitch = pitch
	sync_vel = velocity
	var f := 0
	if velocity.length() > 6.5 and is_on_floor() and input.sprint:
		f |= FLAG_SPRINT
	if not is_on_floor():
		f |= FLAG_AIR
	if weapons.is_reloading():
		f |= FLAG_RELOAD
	if Voice.speaking:
		f |= FLAG_SPEAK
	if stagger_time > 0.0:
		f |= FLAG_STAGGER
	sync_flags = f
	sync_weapon = weapons.current


func _process(delta: float) -> void:
	if is_multiplayer_authority():
		_update_local_camera(delta)
	else:
		_update_remote(delta)
	_animate_puppet(delta)
	_update_nametag(delta)
	_update_grab_line()


func _update_local_camera(delta: float) -> void:
	damage_flash = maxf(damage_flash - delta * 2.2, 0.0)
	shake = maxf(shake - delta * 3.0, 0.0)
	cam_roll = lerpf(cam_roll, 0.0, 1.0 - exp(-7.0 * delta))
	recoil *= exp(-9.0 * delta)
	if status == Status.ELIMINATED:
		_update_spectator(delta)
		return
	var frac := Engine.get_physics_interpolation_fraction()
	var pos := _prev_pos.lerp(_curr_pos, frac)
	var target_eye := GameConfig.EYE_HEIGHT_DOWNED if status == Status.DOWNED else GameConfig.EYE_HEIGHT
	_eye = lerpf(_eye, target_eye, 1.0 - exp(-8.0 * delta))
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hspeed > 0.5:
		_bob += delta * hspeed * 1.7
	var bob_y := sin(_bob) * 0.025 * clampf(hspeed / 5.0, 0.0, 1.2)
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.04
	head.global_position = pos + Vector3(0, _eye + bob_y, 0) + jitter
	head.global_basis = Basis.from_euler(Vector3(pitch + recoil, yaw, cam_roll))
	var fov := 78.0 + (4.0 if sync_flags & FLAG_SPRINT else 0.0)
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-6.0 * delta))


func _update_spectator(delta: float) -> void:
	var targets: Array[Player] = []
	for p in Net.all_players():
		if p != self and p.status != Status.ELIMINATED:
			targets.append(p)
	if targets.is_empty():
		return
	if input.fire_pressed:
		spectate_index += 1
	var t := targets[spectate_index % targets.size()]
	var back := Basis(Vector3.UP, yaw) * Vector3(0, 0, 3.2)
	var want := t.global_position + Vector3(0, 2.0, 0) + back
	head.global_position = head.global_position.lerp(want, 1.0 - exp(-8.0 * delta))
	head.global_basis = Basis.from_euler(Vector3(pitch - 0.2, yaw, 0))


func _update_remote(delta: float) -> void:
	var k := 1.0 - exp(-GameConfig.REMOTE_SMOOTHING * delta)
	if global_position.distance_to(sync_pos) > GameConfig.REMOTE_SNAP_DISTANCE:
		global_position = sync_pos
	else:
		global_position = global_position.lerp(sync_pos, k)
	rotation.y = lerp_angle(rotation.y, sync_yaw, k)
	_remote_pitch = lerpf(_remote_pitch, sync_pitch, k)
	head.global_position = global_position + Vector3(0, GameConfig.EYE_HEIGHT, 0)


func _animate_puppet(delta: float) -> void:
	var spd := 0.0
	var air := false
	var sprint := false
	var pit := _remote_pitch
	if is_multiplayer_authority():
		spd = Vector2(velocity.x, velocity.z).length()
		air = not is_on_floor()
		sprint = (sync_flags & FLAG_SPRINT) != 0
		pit = pitch
	else:
		spd = Vector2(sync_vel.x, sync_vel.z).length()
		air = (sync_flags & FLAG_AIR) != 0
		sprint = (sync_flags & FLAG_SPRINT) != 0
		puppet.set_weapon(sync_weapon)
	puppet.animate(delta, spd, air, sprint, pit)


func _update_nametag(delta: float) -> void:
	if is_multiplayer_authority():
		return
	# keep the tag a roughly constant size on screen: tiny when far, never screen-filling up close
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		nametag.pixel_size = clampf(0.0009 * cam.global_position.distance_to(nametag.global_position), 0.0025, 0.02)
	_tag_timer -= delta
	if _tag_timer > 0.0:
		return
	_tag_timer = 0.25
	var t := player_name
	match status:
		Status.DOWNED:
			t += "  [DOWN %ds]" % ceili(bleed_left)
		Status.ELIMINATED:
			t += "  [OUT]"
	if (sync_flags & FLAG_SPEAK) != 0:
		t += "  ))"
	nametag.text = t


func _update_grab_line() -> void:
	var target := Net.get_player(grabbing) if grabbing != 0 else null
	if target == null or not is_instance_valid(target):
		grab_line.visible = false
		return
	var a := global_position + Vector3(0, 1.1, 0)
	var b := target.global_position + Vector3(0, 0.9 if target.status != Status.DOWNED else 0.3, 0)
	var d := a.distance_to(b)
	if d < 0.1:
		grab_line.visible = false
		return
	grab_line.visible = true
	var dir := (b - a) / d
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	grab_line.global_transform = Transform3D(Basis.looking_at(dir, up), (a + b) * 0.5)
	grab_line.scale = Vector3(1, 1, d)


func _on_camera_shake(strength: float, origin: Vector3) -> void:
	var d := origin.distance_to(global_position)
	shake = maxf(shake, strength * clampf(1.0 - d / 25.0, 0.0, 1.0))


# =================================================================================================
# Status
# =================================================================================================

func _set_status(v: int) -> void:
	if v == status:
		return
	var old := status
	status = v
	if is_node_ready():
		_apply_status_visuals()
		_on_status_changed(old, v)
		status_changed.emit(self, old, v)


func _apply_status_visuals() -> void:
	puppet.set_downed(status == Status.DOWNED)
	if not is_multiplayer_authority():
		puppet.visible = status != Status.ELIMINATED
	collision_layer = 0 if status == Status.ELIMINATED else GameConfig.L_PLAYERS


func _on_status_changed(old: int, v: int) -> void:
	weapons.on_status_changed(v)
	if not is_multiplayer_authority():
		return
	stagger_time = 0.0
	if v == Status.DOWNED:
		Sfx.play(&"downed", -2.0)
		grab_line.visible = false
	elif v == Status.ALIVE and old != Status.ALIVE:
		Sfx.play(&"revive", -3.0)
		velocity = Vector3.ZERO


# =================================================================================================
# Local actions -> host requests
# =================================================================================================

func _do_shove() -> void:
	shove_cd = GameConfig.SHOVE_COOLDOWN
	weapons.play_shove()
	var origin := camera.global_position
	var dir := -Basis.from_euler(Vector3(pitch, yaw, 0.0)).z # current aim, not last frame's camera node
	if multiplayer.is_server():
		_srv_shove(origin, dir)
	else:
		srv_shove.rpc_id(1, origin, dir)


func _update_grab_input() -> void:
	var want := input.grab_held and stagger_time <= 0.0
	if want and not _grab_sent and grabbing == 0:
		var t := _find_grab_target()
		if t != null:
			_grab_sent = true
			if multiplayer.is_server():
				_srv_grab(t.peer_id)
			else:
				srv_grab.rpc_id(1, t.peer_id)
	elif not input.grab_held and _grab_sent:
		_grab_sent = false
		if multiplayer.is_server():
			_srv_ungrab()
		else:
			srv_ungrab.rpc_id(1)


func _find_grab_target() -> Player:
	var fwd := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
	var best: Player = null
	var best_score := INF
	for p in Net.all_players():
		if p == self or p.status == Status.ELIMINATED or p.grabbed_by != 0:
			continue
		var to := p.global_position - global_position
		to.y = 0.0
		var d := to.length()
		var reach := GameConfig.GRAB_REACH + (0.5 if p.status == Status.DOWNED else 0.0)
		if d > reach:
			continue
		var ang := 0.0 if d < 0.4 else acos(clampf(fwd.dot(to / d), -1.0, 1.0))
		if ang > deg_to_rad(80.0):
			continue
		var score := ang * 2.0 + d
		if score < best_score:
			best_score = score
			best = p
	return best


## Decides what the E key would do right now (prompt for the HUD) and tells the host while it is held.
func _update_interactions() -> void:
	prompt_text = ""
	prompt_progress = -1.0
	var kind := Interact.NONE
	var target := 0
	if status == Status.ALIVE and stagger_time <= 0.0:
		for p in Net.all_players():
			if p != self and p.status == Status.DOWNED and p.global_position.distance_to(global_position) <= GameConfig.REVIVE_REACH:
				kind = Interact.REVIVE
				target = p.peer_id
				prompt_text = "Hold [E] to revive %s" % p.player_name
				prompt_progress = p.revive_progress
				break
		if kind == Interact.NONE:
			for b in get_tree().get_nodes_in_group("barricades"):
				var bar := b as Barricade
				if bar != null and bar.can_repair_from(global_position):
					kind = Interact.REPAIR
					target = bar.index
					prompt_text = "Hold [E] to repair barricade (%d/%d)" % [bar.boards, Barricade.MAX_BOARDS]
					prompt_progress = bar.repair_progress
					break
	if kind == Interact.NONE and status == Status.ALIVE:
		if hugged > 0:
			prompt_text = "A Hugger has you! Shove it off [F] or shoot it"
		elif grabbing == 0:
			var gt := _find_grab_target()
			if gt != null:
				prompt_text = "Hold [G] to grab %s" % gt.player_name
	var want_kind := kind if input.interact_held else Interact.NONE
	var want_target := target if input.interact_held else 0
	if want_kind != _sent_kind or want_target != _sent_target:
		_sent_kind = want_kind
		_sent_target = want_target
		if multiplayer.is_server():
			_srv_set_interact(want_kind, want_target)
		else:
			srv_set_interact.rpc_id(1, want_kind, want_target)


# =================================================================================================
# RPC endpoints: client -> host
# =================================================================================================

@rpc("any_peer", "call_remote", "reliable")
func srv_set_interact(kind: int, target: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == peer_id:
		_srv_set_interact(kind, target)


@rpc("any_peer", "call_remote", "reliable")
func srv_grab(target_peer: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == peer_id:
		_srv_grab(target_peer)


@rpc("any_peer", "call_remote", "reliable")
func srv_ungrab() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == peer_id:
		_srv_ungrab()


@rpc("any_peer", "call_remote", "reliable")
func srv_shove(origin: Vector3, dir: Vector3) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == peer_id:
		_srv_shove(origin, dir)


# =================================================================================================
# Host-side logic
# =================================================================================================

func _srv_set_interact(kind: int, target: int) -> void:
	interact_kind = kind
	interact_target = target


func _srv_grab(target_peer: int) -> void:
	if status != Status.ALIVE or grabbing != 0:
		return
	var t := Net.get_player(target_peer)
	if t == null or t == self or t.status == Status.ELIMINATED or t.grabbed_by != 0:
		return
	var flat := t.global_position - global_position
	flat.y = 0.0
	if flat.length() > GameConfig.GRAB_REACH + 1.2:
		return
	grabbing = target_peer
	t.grabbed_by = peer_id


func _srv_ungrab() -> void:
	if grabbing == 0:
		return
	var t := Net.get_player(grabbing)
	if t != null:
		t.grabbed_by = 0
	grabbing = 0


func _srv_shove(origin: Vector3, dir: Vector3) -> void:
	if status != Status.ALIVE:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_shove < GameConfig.SHOVE_COOLDOWN * 0.8:
		return
	_last_shove = now
	var fwd := dir.normalized() if dir.length() > 0.01 else -global_basis.z
	var eye := global_position + Vector3(0, GameConfig.EYE_HEIGHT, 0)
	if origin.distance_to(eye) > 2.5:
		origin = eye
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	flat = flat.normalized() if flat.length() > 0.01 else -global_basis.z
	var cos_limit := cos(deg_to_rad(GameConfig.SHOVE_HALF_ANGLE_DEG))
	fx_shove.rpc()
	for n in get_tree().get_nodes_in_group("enemies"):
		var z := n as Zombie
		if z == null or z.is_dead():
			continue
		var to := (z.global_position + Vector3(0, 0.9, 0)) - origin
		var dist := to.length()
		if dist > GameConfig.SHOVE_RANGE + 0.4 or dist < 0.01 or to.normalized().dot(fwd) < cos_limit:
			continue
		z.srv_shoved(flat, self)
	for p in Net.all_players():
		if p == self or p.status == Status.ELIMINATED:
			continue
		var to := (p.global_position + Vector3(0, 0.9, 0)) - origin
		var dist := to.length()
		if dist > GameConfig.SHOVE_RANGE + 0.3 or dist < 0.01 or to.normalized().dot(fwd) < cos_limit:
			continue
		p.srv_launch(flat * GameConfig.SHOVE_PLAYER_H + Vector3.UP * GameConfig.SHOVE_PLAYER_V, 0.7, true)


func _srv_tick(delta: float) -> void:
	_invuln = maxf(_invuln - delta, 0.0)
	match status:
		Status.ALIVE:
			_since_hit += delta
			if hp < GameConfig.PLAYER_MAX_HP and _since_hit > GameConfig.HP_REGEN_DELAY:
				_regen_accum += GameConfig.HP_REGEN_RATE * delta
				var whole := int(_regen_accum)
				if whole > 0:
					_regen_accum -= whole
					hp = mini(hp + whole, GameConfig.PLAYER_MAX_HP)
		Status.DOWNED:
			_srv_tick_downed(delta)
	if grabbing != 0:
		var t := Net.get_player(grabbing)
		var broken := t == null or status != Status.ALIVE or t.status == Status.ELIMINATED
		if not broken:
			var flat := t.global_position - global_position
			flat.y = 0.0
			broken = flat.length() > GameConfig.GRAB_BREAK_DISTANCE
		if broken:
			_srv_ungrab()


func _srv_tick_downed(delta: float) -> void:
	var reviving := false
	for p in Net.all_players():
		if p != self and p.status == Status.ALIVE and p.interact_kind == Interact.REVIVE and p.interact_target == peer_id \
				and p.global_position.distance_to(global_position) <= GameConfig.REVIVE_REACH + 0.7:
			reviving = true
			break
	if reviving:
		revive_progress = minf(revive_progress + delta / GameConfig.REVIVE_TIME, 1.0)
	else:
		revive_progress = maxf(revive_progress - delta * 0.5, 0.0)
		bleed_left -= delta
	if revive_progress >= 1.0:
		srv_revive()
	elif bleed_left <= 0.0:
		_srv_eliminate()


func srv_take_damage(amount: int, _from: Vector3 = Vector3.ZERO) -> void:
	if Net.debug_god:
		return
	if status != Status.ALIVE or _invuln > 0.0 or amount <= 0:
		return
	hp = maxi(hp - amount, 0)
	_since_hit = 0.0
	if peer_id == 1:
		_apply_hurt(amount)
	else:
		cl_hurt.rpc_id(peer_id, amount)
	if hp == 0:
		_srv_down()


func _srv_down() -> void:
	status = Status.DOWNED
	bleed_left = Net.debug_bleed_time if Net.debug_bleed_time > 0.0 else GameConfig.BLEED_OUT_TIME
	revive_progress = 0.0
	_srv_ungrab()
	_notify_status()


func _srv_eliminate() -> void:
	status = Status.ELIMINATED
	bleed_left = 0.0
	revive_progress = 0.0
	_srv_ungrab()
	if grabbed_by != 0:
		var g := Net.get_player(grabbed_by)
		if g != null:
			g._srv_ungrab()
	_notify_status()


func srv_revive() -> void:
	status = Status.ALIVE
	hp = GameConfig.REVIVE_HP
	bleed_left = 0.0
	revive_progress = 0.0
	_invuln = GameConfig.INVULN_AFTER_REVIVE
	_since_hit = 0.0
	_notify_status()


## Back on their feet at the end of a wave (or when the run restarts).
func srv_heal(amount: int) -> bool:
	if status != Status.ALIVE or hp >= GameConfig.PLAYER_MAX_HP:
		return false
	hp = mini(hp + amount, GameConfig.PLAYER_MAX_HP)
	return true


func srv_restore(pos: Vector3, teleport: bool) -> void:
	hugged = 0
	status = Status.ALIVE
	hp = GameConfig.PLAYER_MAX_HP
	bleed_left = 0.0
	revive_progress = 0.0
	_invuln = GameConfig.INVULN_AFTER_REVIVE
	_srv_ungrab()
	if grabbed_by != 0:
		var g := Net.get_player(grabbed_by)
		if g != null:
			g._srv_ungrab()
	_notify_status()
	if teleport:
		if peer_id == 1:
			_apply_teleport(pos)
		else:
			cl_teleport.rpc_id(peer_id, pos)


func _notify_status() -> void:
	if peer_id != 1:
		cl_set_status.rpc_id(peer_id, status, hp)


func srv_launch(vel: Vector3, stagger: float, hard: bool) -> void:
	if peer_id == 1:
		_apply_launch(vel, stagger)
	else:
		cl_launch.rpc_id(peer_id, vel, stagger)
	if hard:
		fx_ragdoll.rpc(vel)


# =================================================================================================
# RPC endpoints: host -> owner / everyone
# =================================================================================================

@rpc("any_peer", "call_remote", "reliable")
func cl_launch(vel: Vector3, stagger: float) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_apply_launch(vel, stagger)


@rpc("any_peer", "call_remote", "reliable")
func cl_hurt(amount: int) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_apply_hurt(amount)


@rpc("any_peer", "call_remote", "reliable")
func cl_teleport(pos: Vector3) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_apply_teleport(pos)


@rpc("any_peer", "call_remote", "reliable")
func cl_set_status(new_status: int, new_hp: int) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		hp = new_hp # so the HUD never shows "alive with 0 HP" while the periodic sync catches up
		status = new_status


## Brief ragdoll of the *body* for observers. The owner (first person) gets camera effects instead.
@rpc("any_peer", "call_local", "reliable")
func fx_ragdoll(vel: Vector3) -> void:
	var s := multiplayer.get_remote_sender_id()
	if s != 0 and s != 1:
		return
	Sfx.play_at(&"launch", global_position + Vector3.UP, -4.0)
	if is_multiplayer_authority():
		return
	puppet.start_ragdoll(vel, 0.9)


@rpc("any_peer", "call_local", "unreliable")
func fx_shove() -> void:
	var s := multiplayer.get_remote_sender_id()
	if s != 0 and s != 1:
		return
	puppet.play_shove()
	Sfx.play_at(&"shove", global_position + Vector3.UP, -3.0)


func _apply_launch(vel: Vector3, stagger: float) -> void:
	velocity += vel
	var h := Vector2(velocity.x, velocity.z)
	if h.length() > GameConfig.MAX_LAUNCH_SPEED:
		h = h.normalized() * GameConfig.MAX_LAUNCH_SPEED
		velocity.x = h.x
		velocity.z = h.y
	stagger_time = maxf(stagger_time, stagger)
	cam_roll = randf_range(-0.16, 0.16) * clampf(vel.length() / 8.0, 0.3, 1.5)
	shake = maxf(shake, 0.4)


func _apply_hurt(_amount: int) -> void:
	damage_flash = 1.0
	shake = maxf(shake, 0.5)
	Sfx.play(&"hurt", -4.0)


func _apply_teleport(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	_prev_pos = pos
	_curr_pos = pos
	sync_pos = pos
