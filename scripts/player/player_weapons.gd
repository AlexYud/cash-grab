class_name PlayerWeapons
extends Node
## Gunplay for one player: ammo, reload, switching, hitscan, first-person view model.
##
## Shots are resolved on the shooter's machine against what the shooter sees (so hits feel right), then
## reported to the host, which validates rate/range/plausibility and applies damage and knockback.

enum Hit { NONE, WORLD, ENEMY, PLAYER, BARREL }

var player: Player
var list: Array[WeaponData] = []
var ammo: Array[int] = []
var current := 0
var locked := false ## both hands busy (carrying a teammate): no firing, reloading or switching
var hit_marker := 0.0 ## HUD: seconds left on the hit marker
var kill_marker := 0.0
var head_marker := 0.0 ## HUD: gold marker after a headshot
var owned: Array[bool] = [] ## weapons this player has (everyone starts with just the pistol)
var mods: Array[Dictionary] = [] ## per weapon: buff key -> level (see WeaponCards.MODS)

var _cooldown := 0.0
var _reload_left := 0.0
var _switch_left := 0.0
var _buffered := 0.0
var _srv_last_shot := -99.0

var _viewmodel: Node3D
var _guns: Array[Node3D] = []
var _muzzles: Array[Marker3D] = []
var _kick := 0.0
var _shove_anim := 0.0
var _vm_bob := 0.0
var _ads := 0.0


func setup(p: Player) -> void:
	player = p
	list = [load("res://resources/weapons/pistol.tres"), load("res://resources/weapons/shotgun.tres"), load("res://resources/weapons/yank.tres"), load("res://resources/weapons/disco.tres"), load("res://resources/weapons/tesla.tres"), load("res://resources/weapons/boing.tres"),
		load("res://resources/weapons/assault_rifle.tres"), load("res://resources/weapons/sniper.tres"), load("res://resources/weapons/bat.tres"), load("res://resources/weapons/katana.tres"), load("res://resources/weapons/axe.tres")]
	for w in list:
		ammo.append(w.mag_size)
		owned.append(Net.debug_all_weapons or owned.is_empty())
		mods.append({})
	_build_viewmodel()


# --- upgrades (the between-rounds cards) -----------------------------------------------------------

func mod_level(idx: int, key: StringName) -> int:
	return int(mods[idx].get(key, 0))


func damage_mult(idx: int) -> float:
	return 1.0 + 0.2 * mod_level(idx, &"dmg")


func mag_size_of(idx: int) -> int:
	var base := list[idx].mag_size
	return int(round(base * (1.0 + 0.3 * mod_level(idx, &"mag")))) if base > 0 else 0


func interval_of(idx: int) -> float:
	return list[idx].fire_interval * maxf(pow(0.88, mod_level(idx, &"rate")), 0.3)


func knock_mult(idx: int) -> float:
	return 1.0 + 0.35 * mod_level(idx, &"knock")


## Short "Dmg 2, Bleeding 1" style summary for the HUD.
func mod_summary(idx: int) -> String:
	var parts := PackedStringArray()
	for k in WeaponCards.MODS:
		var l := mod_level(idx, k)
		if l > 0:
			parts.append("%s %d" % [WeaponCards.MODS[k]["name"], l])
	return ", ".join(parts)


func is_reloading() -> bool:
	return _reload_left > 0.0


func reload_fraction() -> float:
	if _reload_left <= 0.0:
		return 0.0
	return 1.0 - _reload_left / list[current].reload_time


func on_status_changed(status: int) -> void:
	if status != Player.Status.ALIVE:
		_reload_left = 0.0
		if current != 0:
			current = 0
			_switch_left = list[0].switch_time
			_refresh_viewmodel()


func show_viewmodel(v: bool) -> void:
	_viewmodel.visible = v


func play_shove() -> void:
	_shove_anim = 0.25


# --- per-tick (owner only) ------------------------------------------------------------------

func tick(delta: float, inp: PlayerInputState) -> void:
	hit_marker = maxf(hit_marker - delta, 0.0)
	kill_marker = maxf(kill_marker - delta, 0.0)
	head_marker = maxf(head_marker - delta, 0.0)
	_cooldown = maxf(_cooldown - delta, 0.0)
	_buffered = maxf(_buffered - delta, 0.0)
	_switch_left = maxf(_switch_left - delta, 0.0)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			ammo[current] = mag_size_of(current)

	if locked:
		_buffered = 0.0
		return
	if player.status == Player.Status.ALIVE:
		var want := current
		if inp.weapon_slot >= 0 and inp.weapon_slot < list.size() and owned[inp.weapon_slot]:
			want = inp.weapon_slot
		elif inp.weapon_cycle != 0:
			for step in list.size(): # next weapon we actually own
				var cand := posmod(current + inp.weapon_cycle * (step + 1), list.size())
				if owned[cand]:
					want = cand
					break
		if want != current:
			current = want
			_reload_left = 0.0
			_switch_left = list[current].switch_time
			_refresh_viewmodel()
	if inp.reload:
		_begin_reload()
	if not owned[current]: # the weapon is in an upgrader machine: empty hands
		_buffered = 0.0
		return
	if inp.fire_pressed or (inp.fire_held and list[current].auto):
		_buffered = 0.18
	if _buffered > 0.0 and _cooldown <= 0.0 and _reload_left <= 0.0 and _switch_left <= 0.0:
		if list[current].melee:
			_buffered = 0.0
			_melee_swing()
		elif ammo[current] > 0:
			_buffered = 0.0
			_fire()
		else:
			_buffered = 0.0
			Sfx.play(&"empty", -4.0)
			_begin_reload()


func _begin_reload() -> void:
	var w := list[current]
	if w.melee or _reload_left > 0.0 or _switch_left > 0.0 or ammo[current] >= mag_size_of(current):
		return
	_reload_left = w.reload_time
	Sfx.play(&"reload", -4.0)


func _fire() -> void:
	var w := list[current]
	ammo[current] -= 1
	_cooldown = interval_of(current)
	_kick = 1.0
	var cam := player.camera
	var origin := cam.global_position
	# aim comes from the player's current yaw/pitch (the camera node only updates at render time), and is read
	# before this shot's recoil kick so the first bullet goes exactly where the crosshair points
	var basis := Basis.from_euler(Vector3(player.pitch + player.recoil, player.yaw, 0.0))
	player.recoil = minf(player.recoil + deg_to_rad(w.recoil_deg), deg_to_rad(9.0))
	var space := player.get_world_3d().direct_space_state
	var exclude: Array[RID] = [player.get_rid()]
	var ends := PackedVector3Array()
	var kinds := PackedByteArray()
	var agg := {}
	var enemy_hit := false
	var any_head := false
	for i in w.pellets:
		var dir := _spread_dir(basis, w.spread_deg * (GameConfig.ADS_SPREAD_MULT if player.ads else 1.0))
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * w.max_range, GameConfig.MASK_HITSCAN, exclude)
		var r := space.intersect_ray(q)
		if r.is_empty():
			ends.append(origin + dir * w.max_range)
			kinds.append(Hit.NONE)
			continue
		var pos: Vector3 = r["position"]
		var col: Object = r["collider"]
		var kind: int = Hit.WORLD
		var id := 0
		var head := false
		if col is Zombie:
			var zc := col as Zombie
			kind = Hit.ENEMY
			id = zc.net_id
			enemy_hit = true
			# a hit level with or above the animated head is a headshot, so a crouching or lunging zombie's lower head
			# counts too (limp ones are a flat body: no headshots)
			if zc.state == Zombie.State.CLIMB or zc.state == Zombie.State.CEILING: # upside down / sideways: judge by distance
				head = pos.distance_to(zc.puppet.head_position()) < 0.45 * zc.puppet.scale.x
			else:
				head = not zc.is_fallen() and pos.y > zc.puppet.head_position().y - GameConfig.HEAD_BAND * zc.puppet.scale.x
		elif col is Player:
			kind = Hit.PLAYER
			id = (col as Player).peer_id
		elif col is ExplosiveBarrel:
			kind = Hit.BARREL
			id = (col as ExplosiveBarrel).index
		ends.append(pos)
		kinds.append(kind)
		Fx.impact(pos, r["normal"], Fx.Impact.FLESH if kind == Hit.ENEMY or kind == Hit.PLAYER else Fx.Impact.WORLD)
		if kind != Hit.WORLD:
			var key := kind * 100000 + id
			if agg.has(key):
				agg[key][2] += 1
				agg[key][4] += 1 if head else 0
			else:
				agg[key] = [kind, id, 1, pos, 1 if head else 0]
			if head:
				any_head = true
	_shot_visuals(current, _muzzle_pos(), ends, true)
	Sfx.play(w.id, -3.0)
	fx_shot.rpc(current, ends, kinds)
	if enemy_hit:
		hit_marker = 0.18
		Sfx.play(&"hit_marker", -8.0, 1.5 if any_head else 1.0)
	if any_head:
		head_marker = 0.25
	if not agg.is_empty():
		if multiplayer.is_server():
			_srv_hits(current, origin, agg.values())
		else:
			srv_hits.rpc_id(1, current, origin, agg.values())


# --- melee: wind-up, strike, follow-through ------------------------------------------------------------------
# Each weapon has a chain of swings (a combo). A swing is a list of keyframes [time 0..1, position offset, rotation
# offset in radians] applied on top of the resting view model, and `hit` says when in the swing the blow lands.
# rotation.x > 0 lifts the tip, rotation.y > 0 swings it to the left, rotation.z rolls the blade.

const SWINGS := {
	&"bat": [
		{"dur": 0.55, "hit": 0.5, "keys": [
			[0.0, Vector3(0, 0, 0), Vector3(0, 0, 0)],
			[0.34, Vector3(0.16, 0.06, 0.04), Vector3(0.4, -1.0, -0.5)],
			[0.5, Vector3(-0.02, 0.0, -0.06), Vector3(0.0, 0.1, 0.1)],
			[0.64, Vector3(-0.3, -0.06, -0.2), Vector3(-0.25, 1.3, 0.55)],
			[1.0, Vector3(0, 0, 0), Vector3(0, 0, 0)]]},
	],
	&"katana": [
		{"dur": 0.38, "hit": 0.45, "keys": [ # right to left, slightly downward
			[0.0, Vector3(0, 0, 0), Vector3(0, 0, 0)],
			[0.26, Vector3(0.2, 0.12, 0.08), Vector3(0.5, -0.9, -0.7)],
			[0.55, Vector3(-0.26, -0.1, -0.16), Vector3(-0.4, 1.15, 0.7)],
			[1.0, Vector3(0, 0, 0), Vector3(0, 0, 0)]]},
		{"dur": 0.38, "hit": 0.45, "keys": [ # back across, rising
			[0.0, Vector3(0, 0, 0), Vector3(0, 0, 0)],
			[0.26, Vector3(-0.22, -0.12, 0.05), Vector3(-0.5, 1.0, 0.9)],
			[0.55, Vector3(0.24, 0.14, -0.16), Vector3(0.55, -1.0, -0.6)],
			[1.0, Vector3(0, 0, 0), Vector3(0, 0, 0)]]},
		{"dur": 0.5, "hit": 0.5, "finisher": true, "keys": [ # overhead chop
			[0.0, Vector3(0, 0, 0), Vector3(0, 0, 0)],
			[0.36, Vector3(0.02, 0.16, 0.0), Vector3(1.0, -0.1, 0.12)],
			[0.58, Vector3(0.0, -0.16, -0.28), Vector3(-1.05, 0.0, 0.0)],
			[1.0, Vector3(0, 0, 0), Vector3(0, 0, 0)]]},
	],
	&"axe": [
		{"dur": 0.95, "hit": 0.55, "finisher": true, "keys": [
			[0.0, Vector3(0, 0, 0), Vector3(0, 0, 0)],
			[0.4, Vector3(0.03, 0.16, 0.0), Vector3(1.05, 0.0, 0.15)],
			[0.5, Vector3(0.02, 0.15, 0.0), Vector3(1.02, 0.0, 0.14)],
			[0.64, Vector3(0.0, -0.18, -0.3), Vector3(-1.15, 0.0, 0.0)],
			[0.76, Vector3(0.0, -0.2, -0.26), Vector3(-1.0, 0.0, 0.0)],
			[1.0, Vector3(0, 0, 0), Vector3(0, 0, 0)]]},
	],
}
const TRAIL_COLORS := {&"bat": Color(1.0, 0.9, 0.7), &"katana": Color(0.7, 0.9, 1.0), &"axe": Color(1.0, 0.55, 0.3)}
const COMBO_WINDOW := 0.55 ## a new swing this soon after the last one continues the combo

var _swing_style: Dictionary = {}
var _swing_t := -1.0 ## seconds into the current swing, -1 when idle
var _swing_dur := 0.5
var _swing_step := 0
var _combo_left := 0.0
var _resolve_pending := false
var _hitstop := 0.0
var _trail: Array = [] ## recent [base, tip, age] world positions of the blade while it cuts
var _trail_node: MeshInstance3D
var _trail_mesh: ImmediateMesh


## Starts the next swing of the weapon's combo. The blow itself lands a moment later, at the strike (_melee_resolve).
func _melee_swing() -> void:
	var w := list[current]
	var chain: Array = SWINGS.get(w.id, [])
	_cooldown = interval_of(current)
	if chain.is_empty():
		_melee_resolve()
		return
	_swing_step = _swing_step + 1 if _combo_left > 0.0 and _swing_step + 1 < chain.size() else 0
	_swing_style = chain[_swing_step]
	_swing_dur = float(_swing_style["dur"]) * interval_of(current) / maxf(w.fire_interval, 0.05)
	_combo_left = COMBO_WINDOW + _swing_dur
	_swing_t = 0.0
	_cooldown = maxf(interval_of(current), _swing_dur * 0.9)
	_resolve_pending = true
	_trail.clear()
	Sfx.play(w.id, -4.0, randf_range(0.85, 1.1) + 0.08 * _swing_step)
	var info := PackedByteArray([_swing_step, 1 if _swing_style.get("finisher", false) else 0])
	fx_shot.rpc(current, PackedVector3Array(), info) # observers get the same swing


func _melee_advance(delta: float) -> void:
	_combo_left = maxf(_combo_left - delta, 0.0)
	if _hitstop > 0.0:
		_hitstop -= delta
		return
	if _swing_t < 0.0:
		return
	_swing_t += delta
	var p := _swing_t / _swing_dur
	var hit := float(_swing_style["hit"])
	if _resolve_pending and p >= hit:
		_resolve_pending = false
		_melee_resolve()
	if p >= hit - 0.16 and p <= hit + 0.18: # the blade leaves a glowing arc while it cuts
		_trail_sample()
	if _swing_t >= _swing_dur:
		_swing_t = -1.0


## The view model's offset for the current swing: smooth interpolation through the keyframes.
func _swing_pose() -> Array:
	if _swing_t < 0.0:
		return [Vector3.ZERO, Vector3.ZERO]
	var keys: Array = _swing_style["keys"]
	var p := clampf(_swing_t / _swing_dur, 0.0, 1.0)
	for i in range(1, keys.size()):
		if p <= float(keys[i][0]):
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			var u := (p - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
			u = u * u * (3.0 - 2.0 * u)
			return [(a[1] as Vector3).lerp(b[1], u), (a[2] as Vector3).lerp(b[2], u)]
	return [Vector3.ZERO, Vector3.ZERO]


## The blow lands: find the zombies in the cone, send the hits, and make it feel heavy.
func _melee_resolve() -> void:
	var w := list[current]
	var origin := player.camera.global_position
	var fwd := -Basis.from_euler(Vector3(player.pitch + player.recoil, player.yaw, 0.0)).z
	var cos_arc := cos(deg_to_rad(w.melee_half_arc_deg))
	var space := player.get_world_3d().direct_space_state
	var cands: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		var z := n as Zombie
		if z == null or z.is_dead():
			continue
		var sc := z.puppet.scale.x
		var chest := z.global_position + Vector3(0, 1.0 * sc, 0)
		var to := chest - origin
		var d := to.length()
		if d < 0.01 or d > w.melee_range + 0.45 * sc or to.normalized().dot(fwd) < cos_arc:
			continue
		var q := PhysicsRayQueryParameters3D.create(origin, chest, GameConfig.L_WORLD | GameConfig.L_BARRICADES, [player.get_rid()])
		if space.intersect_ray(q).is_empty():
			cands.append([d, z, chest])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var hits: Array = []
	for i in mini(cands.size(), w.melee_targets):
		var z: Zombie = cands[i][1]
		hits.append([Hit.ENEMY, z.net_id, 1, cands[i][2], 0])
		Fx.impact(cands[i][2], -fwd, Fx.Impact.FLESH)
		Fx.impact(cands[i][2] + Vector3(0, 0.15, 0), Vector3.UP, Fx.Impact.FLESH)
	var big: bool = _swing_style.get("finisher", false)
	# a little lunge into the swing, a kick of camera and field of view
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	if player.is_on_floor() and not player.ads:
		player.velocity += flat * (3.6 if big else 2.4)
	player.shake = maxf(player.shake, (0.55 if big else 0.3) if not hits.is_empty() else 0.12)
	player.recoil = minf(player.recoil + deg_to_rad(2.2 if big else 1.2), deg_to_rad(9.0))
	player.fov_kick = 6.0 if big else 3.5
	if not hits.is_empty():
		_hitstop = 0.09 if big else 0.055 # the blade bites: the swing freezes for a few frames
		hit_marker = 0.18
		Sfx.play(&"hit_marker", -8.0)
		Sfx.play(&"hit_flesh", -2.0, 0.75 if big else 0.9)
		Sfx.play(&"hit_world", -6.0, 0.5)
		Fx.camera_shake.emit(0.5 if big else 0.28, origin + fwd * 2.0)
		if multiplayer.is_server():
			_srv_hits(current, origin, hits)
		else:
			srv_hits.rpc_id(1, current, origin, hits)


# --- the slash trail ---------------------------------------------------------------------------------------------

func _trail_sample() -> void:
	var g := _guns[current]
	var tip := _muzzles[current].global_position
	var inv := player.camera.global_transform.affine_inverse() # the arc lives in the camera's space, like the weapon
	_trail.append([inv * g.global_position.lerp(tip, 0.45), inv * tip, 0.0])


func _trail_update(delta: float) -> void:
	for e in _trail:
		e[2] += delta
	while not _trail.is_empty() and float(_trail[0][2]) > 0.22:
		_trail.pop_front()
	if _trail.size() < 2:
		if _trail_mesh != null:
			_trail_mesh.clear_surfaces()
		return
	if _trail_node == null or not is_instance_valid(_trail_node):
		if Fx.world == null:
			return
		_trail_mesh = ImmediateMesh.new()
		_trail_node = MeshInstance3D.new()
		_trail_node.mesh = _trail_mesh
		_trail_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = true # the arc is drawn over everything: it is a glow, not an object
		m.render_priority = 5
		_trail_node.material_override = m
		player.camera.add_child(_trail_node)
	var col: Color = TRAIL_COLORS.get(list[current].id, Color.WHITE)
	_trail_mesh.clear_surfaces()
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for e in _trail:
		var a := clampf(1.0 - float(e[2]) / 0.22, 0.0, 1.0)
		_trail_mesh.surface_set_color(Color(col.r, col.g, col.b, 0.0))
		_trail_mesh.surface_add_vertex(e[0])
		_trail_mesh.surface_set_color(Color(col.r, col.g, col.b, 0.9 * a * a))
		_trail_mesh.surface_add_vertex(e[1])
	_trail_mesh.surface_end()


func _spread_dir(basis: Basis, spread_deg: float) -> Vector3:
	var fwd := -basis.z
	if spread_deg <= 0.0:
		return fwd
	var a := randf() * TAU
	var r := tan(deg_to_rad(spread_deg)) * sqrt(randf())
	return (fwd + basis.x * cos(a) * r + basis.y * sin(a) * r).normalized()


func _muzzle_pos() -> Vector3:
	return _muzzles[current].global_position


# --- visuals shared by the shooter and observers -----------------------------------------------

func _shot_visuals(weapon_idx: int, muzzle: Vector3, ends: PackedVector3Array, local: bool) -> void:
	var w := list[weapon_idx]
	Fx.muzzle_flash(muzzle, w.pellets > 1)
	for i in mini(ends.size(), 3):
		Fx.tracer(muzzle, ends[i])
	if not local:
		Sfx.play_at(w.id, muzzle, -2.0)


@rpc("any_peer", "call_remote", "unreliable")
func fx_shot(weapon_idx: int, ends: PackedVector3Array, kinds: PackedByteArray) -> void:
	if multiplayer.get_remote_sender_id() != player.peer_id or weapon_idx < 0 or weapon_idx >= list.size():
		return
	if list[weapon_idx].melee: # observers just see (and hear) the swing
		player.puppet.play_swing(int(kinds[0]) if kinds.size() > 0 else 0, kinds.size() > 1 and kinds[1] == 1)
		Sfx.play_at(list[weapon_idx].id, player.global_position + Vector3.UP, -3.0)
		return
	var muzzle := player.puppet.muzzle_position(weapon_idx)
	_shot_visuals(weapon_idx, muzzle, ends, false)
	for i in ends.size():
		if kinds[i] == Hit.ENEMY or kinds[i] == Hit.PLAYER:
			Fx.impact(ends[i], Vector3.UP, Fx.Impact.FLESH)
		elif kinds[i] != Hit.NONE:
			Fx.impact(ends[i], Vector3.UP, Fx.Impact.WORLD)


# --- host validation ------------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func srv_hits(weapon_idx: int, origin: Vector3, hits: Array) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == player.peer_id:
		_srv_hits(weapon_idx, origin, hits)


func _srv_hits(weapon_idx: int, origin: Vector3, hits: Array) -> void:
	if weapon_idx < 0 or weapon_idx >= list.size() or player.status == Player.Status.ELIMINATED:
		return
	if not owned[weapon_idx]:
		return # not a weapon this player has (host copy is kept in sync by give_weapon)
	if player.status == Player.Status.DOWNED and weapon_idx != 0:
		return
	var w := list[weapon_idx]
	var now := Time.get_ticks_msec() / 1000.0
	if now - _srv_last_shot < interval_of(weapon_idx) * (0.3 if w.auto else 0.6):
		return
	_srv_last_shot = now
	var dm := damage_mult(weapon_idx) * player.rage_mult()
	var km := knock_mult(weapon_idx)
	var eye := player.global_position + Vector3(0, GameConfig.EYE_HEIGHT, 0)
	if origin.distance_to(eye) > 4.0:
		origin = eye
	for h in hits:
		var kind: int = h[0]
		var id: int = h[1]
		var pellets: int = clampi(h[2], 1, w.pellets)
		var point: Vector3 = h[3]
		var dist := origin.distance_to(point)
		if dist > w.max_range + 2.0:
			continue
		var dir := (point - origin).normalized()
		match kind:
			Hit.ENEMY:
				var z := Zombie.find_by_id(get_tree(), id)
				if z == null or z.is_dead() or z.global_position.distance_to(point) > 3.5:
					continue
				var heads: int = clampi(int(h[4]) if h.size() > 4 else 0, 0, pellets)
				var dmg := int(round(w.damage_at(dist) * dm * (pellets + heads * (GameConfig.HEADSHOT_MULT + 0.5 * mod_level(weapon_idx, &"headhunter") - 1.0))))
				z.srv_hit(dmg, dir * w.enemy_knockback * km * pellets, w.enemy_stagger * km, player, heads > 0)
				_srv_effects(z, w, weapon_idx, dmg, dir, origin)
				if not z.is_dead():
					if w.special == &"bonk" and randf() < 0.35:
						z.srv_trip(dir * 5.0)
					elif w.special == &"yank":
						z.srv_yank(origin)
					elif w.special == &"boing":
						z.srv_boing()
					elif w.special == &"tesla":
						_srv_tesla(z, w, origin)
					elif w.special == &"disco":
						z.srv_dance(3.0)
			Hit.PLAYER:
				var p := Net.get_player(id)
				if p == null or p == player or p.status == Player.Status.ELIMINATED:
					continue
				if w.special == &"yank": # reel the teammate in to the shooter
					var to := player.global_position - p.global_position
					to.y = 0.0
					p.srv_launch(to.normalized() * minf(to.length() * 2.2 + 3.0, 13.0) + Vector3.UP * 3.0, 0.6)
					continue
				if w.special == &"boing": # a big bounce
					p.srv_launch(Vector3.UP * 11.0 + Vector3(dir.x, 0.0, dir.z) * 2.0, 0.7)
					continue
				if w.special == &"tesla": # a tingle
					p.srv_launch(Vector3.UP * 3.0, 0.4)
					continue
				if w.special == &"disco": # a little hop
					p.srv_launch(Vector3.UP * 6.0, 0.4)
					continue
				var flat := Vector3(dir.x, 0.0, dir.z)
				flat = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
				var push := minf(w.player_knockback * km * pellets, 11.0)
								# friendly fire: a shove-back and a stumble, never the body-ragdoll (that reads as death)
				p.srv_launch(flat * push + Vector3.UP * minf(pellets * 0.5, 3.5), w.player_stagger + clampf(push * 0.05, 0.0, 0.5), false)
			Hit.BARREL:
				var b := ExplosiveBarrel.find_by_index(get_tree(), id)
				if b != null and b.alive:
					b.srv_damage(int(round(w.damage_at(dist) * pellets)), player)


## The upgrade effects that do something extra on a hit (host only). `dmg` is what the hit did. Levels never run out,
## so every chance is capped instead.
func _srv_effects(z: Zombie, w: WeaponData, idx: int, dmg: int, dir: Vector3, origin: Vector3) -> void:
	var m := mods[idx]
	if m.is_empty():
		return
	var life := mod_level(idx, &"life")
	if life > 0:
		player.srv_heal(maxi(int(round(dmg * minf(0.06 * life, 0.6))), 1))
	if z.is_dead():
		return
	var bleed := mod_level(idx, &"bleed")
	if bleed > 0:
		z.srv_bleed(6.0 * bleed, 4.0, player)
	var ignite := mod_level(idx, &"ignite")
	if ignite > 0:
		z.srv_ignite(5.0 * ignite, 5.0, player)
	var freeze := mod_level(idx, &"freeze")
	if freeze > 0:
		z.srv_freeze(maxf(1.0 - 0.2 * freeze, 0.25), 2.5)
	var sparks := mod_level(idx, &"spark")
	if randf() < minf(0.2 * sparks, 0.9):
		_srv_tesla(z, w, origin, 2 + sparks / 3, 0.5)
	if z.is_dead():
		return
	if randf() < minf(0.12 * mod_level(idx, &"vortex"), 0.8):
		_srv_vortex(z)
	if randf() < minf(0.15 * mod_level(idx, &"blast"), 0.8):
		_srv_blast(z, dmg, dir)
	if z.is_dead():
		return
	if randf() < minf(0.15 * mod_level(idx, &"boing"), 0.8):
		z.srv_boing()
	elif randf() < minf(0.15 * mod_level(idx, &"disco"), 0.8):
		z.srv_dance(3.0)


## "Black Hole": every zombie around the one that was hit is pulled towards it.
func _srv_vortex(centre: Zombie) -> void:
	Fx.explosion.rpc(centre.global_position, 2.0)
	for n in get_tree().get_nodes_in_group("enemies"):
		var o := n as Zombie
		if o == null or o.is_dead() or o == centre:
			continue
		var d := centre.global_position - o.global_position
		d.y = 0.0
		if d.length() < 5.5 and d.length() > 0.2:
			o.add_knock(d.normalized() * minf(d.length() * 2.0 + 3.0, 10.0))
			if randf() < 0.3:
				o.srv_trip(d.normalized() * 2.0)


## "Boom Rounds": a small burst around the zombie that was hit.
func _srv_blast(centre: Zombie, dmg: int, dir: Vector3) -> void:
	Fx.explosion.rpc(centre.global_position, 3.0)
	for n in get_tree().get_nodes_in_group("enemies"):
		var o := n as Zombie
		if o == null or o.is_dead() or o == centre:
			continue
		var d := o.global_position - centre.global_position
		d.y = 0.0
		if d.length() < 2.4:
			o.srv_hit(int(dmg * 0.5), d.normalized() * 6.0 + dir * 2.0, 0.6, player)
			if not o.is_dead():
				o.srv_trip(d.normalized() * 3.0)


## Tesla Gun: the bolt arcs from the zombie it hit to up to three more nearby, weaker each jump.
func _srv_tesla(first: Zombie, w: WeaponData, origin: Vector3, jumps: int = -1, frac: float = 1.0) -> void:
	var chain := PackedVector3Array([origin, first.global_position + Vector3(0, 1.1, 0)])
	var visited: Array = [first]
	var cur := first
	for jump in (jumps if jumps > 0 else GameConfig.TESLA_FALLOFF.size()):
		var best: Zombie = null
		var best_d := GameConfig.TESLA_RANGE
		for n in get_tree().get_nodes_in_group("enemies"):
			var o := n as Zombie
			if o == null or o.is_dead() or visited.has(o):
				continue
			var d := o.global_position.distance_to(cur.global_position)
			if d < best_d:
				best_d = d
				best = o
		if best == null:
			break
		visited.append(best)
		chain.append(best.global_position + Vector3(0, 1.1, 0))
		best.srv_hit(int(round(w.damage * frac * GameConfig.TESLA_FALLOFF[jump])), Vector3.ZERO, 0.35, player)
		cur = best
	Fx.lightning.rpc(chain)


## Called on every peer when the mystery box (or a debug flag) hands this player a weapon.
@rpc("any_peer", "call_local", "reliable")
func give_weapon(idx: int) -> void:
	var s := multiplayer.get_remote_sender_id()
	if (s != 0 and s != 1) or idx < 0 or idx >= list.size():
		return
	owned[idx] = true
	ammo[idx] = mag_size_of(idx) # a weapon you already had just gets refilled
	if player.is_local():
		current = idx
		_reload_left = 0.0
		_switch_left = list[idx].switch_time
		_refresh_viewmodel()
		Sfx.play(&"revive", -3.0, 1.3)


## An upgrader machine takes the weapon out of your hands (it comes back through give_weapon). Upgrades stay on it.
@rpc("any_peer", "call_local", "reliable")
func take_weapon(idx: int) -> void:
	var s := multiplayer.get_remote_sender_id()
	if (s != 0 and s != 1) or idx < 0 or idx >= list.size():
		return
	owned[idx] = false
	_reload_left = 0.0
	if current == idx:
		for i in list.size(): # something else to hold, the pistol first
			if owned[i]:
				current = i
				break
		_switch_left = list[current].switch_time
	_refresh_viewmodel()


func has_any_weapon() -> bool:
	return owned.has(true)


## New run: back to just the pistol.
@rpc("any_peer", "call_local", "reliable")
func reset_weapons() -> void:
	var s := multiplayer.get_remote_sender_id()
	if s != 0 and s != 1:
		return
	for i in owned.size():
		owned[i] = i == 0 or Net.debug_all_weapons
		mods[i] = {}
		ammo[i] = list[i].mag_size
	current = 0
	_refresh_viewmodel()


## A card buff (all peers keep the same levels: the owner needs them for magazine and fire rate, the host for effects).
@rpc("any_peer", "call_local", "reliable")
func apply_mod(idx: int, key: StringName) -> void:
	var s := multiplayer.get_remote_sender_id()
	if (s != 0 and s != 1) or idx < 0 or idx >= list.size() or not WeaponCards.MODS.has(key):
		return
	mods[idx][key] = mod_level(idx, key) + 1
	if key == &"mag":
		ammo[idx] = mag_size_of(idx)
	if player.is_local():
		Sfx.play(&"revive", -3.0, 1.2)


@rpc("any_peer", "call_remote", "reliable")
func cl_kill_confirm() -> void:
	if multiplayer.get_remote_sender_id() == 1:
		kill_marker = 0.35
		Sfx.play(&"hit_marker", -3.0, 0.7)


func srv_notify_kill() -> void:
	if player.peer_id == 1:
		kill_marker = 0.35
		Sfx.play(&"hit_marker", -3.0, 0.7)
	else:
		cl_kill_confirm.rpc_id(player.peer_id)


# --- first-person view model ---------------------------------------------------------------------

func _build_viewmodel() -> void:
	_viewmodel = Node3D.new()
	_viewmodel.name = "ViewModel"
	player.camera.add_child(_viewmodel)
	player.camera.near = 0.04
	for i in list.size():
		var g := GunModels.build(i, true)
		_viewmodel.add_child(g)
		var m := Marker3D.new()
		m.position = g.get_meta("muzzle")
		g.add_child(m)
		_muzzles.append(m)
		_guns.append(g)
	_refresh_viewmodel()


func _refresh_viewmodel() -> void:
	for i in _guns.size():
		_guns[i].visible = i == current and owned[i]


func _process(delta: float) -> void:
	if _viewmodel == null or not _viewmodel.visible:
		return
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-13.0 * delta))
	_shove_anim = maxf(_shove_anim - delta, 0.0)
	_melee_advance(delta)
	_trail_update(delta)
	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	_vm_bob += delta * hspeed * 1.7
	var dip := 0.0
	if _reload_left > 0.0:
		dip = sin(reload_fraction() * PI) * 0.2
	var sw := 0.0
	if _switch_left > 0.0:
		sw = _switch_left / maxf(list[current].switch_time, 0.01) * 0.22
	var shove := sin(_shove_anim / 0.25 * PI)
	var down := 0.3 if player.status == Player.Status.DOWNED else 0.0
	var bob := Vector3(cos(_vm_bob * 0.5) * 0.008, sin(_vm_bob) * 0.008, 0.0) * clampf(hspeed / 5.0, 0.0, 1.0)
	_ads = lerpf(_ads, 1.0 if player.ads else 0.0, 1.0 - exp(-14.0 * delta))
	_viewmodel.position = Vector3(lerpf(0.2, 0.0, _ads), lerpf(-0.23, -0.17, _ads) - dip - sw - down * 0.2, -0.36 + _kick * 0.07 - shove * 0.12) + bob * (1.0 - _ads)
	var pose := _swing_pose()
	_viewmodel.rotation = Vector3(_kick * 0.2 - dip * 1.1 + shove * 0.5, 0.0, -dip * 0.5) + (pose[1] as Vector3)
	_viewmodel.position += (pose[0] as Vector3)
