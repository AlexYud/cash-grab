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
var hit_marker := 0.0 ## HUD: seconds left on the hit marker
var kill_marker := 0.0

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


func setup(p: Player) -> void:
	player = p
	list = [load("res://resources/weapons/pistol.tres"), load("res://resources/weapons/shotgun.tres")]
	for w in list:
		ammo.append(w.mag_size)
	_build_viewmodel()


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
	_cooldown = maxf(_cooldown - delta, 0.0)
	_buffered = maxf(_buffered - delta, 0.0)
	_switch_left = maxf(_switch_left - delta, 0.0)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			ammo[current] = list[current].mag_size

	if player.status == Player.Status.ALIVE:
		var want := current
		if inp.weapon_slot >= 0 and inp.weapon_slot < list.size():
			want = inp.weapon_slot
		elif inp.weapon_cycle != 0:
			want = posmod(current + inp.weapon_cycle, list.size())
		if want != current:
			current = want
			_reload_left = 0.0
			_switch_left = list[current].switch_time
			_refresh_viewmodel()
	if inp.reload:
		_begin_reload()
	if inp.fire_pressed:
		_buffered = 0.18
	if _buffered > 0.0 and _cooldown <= 0.0 and _reload_left <= 0.0 and _switch_left <= 0.0:
		if ammo[current] > 0:
			_buffered = 0.0
			_fire()
		else:
			_buffered = 0.0
			Sfx.play(&"empty", -4.0)
			_begin_reload()


func _begin_reload() -> void:
	var w := list[current]
	if _reload_left > 0.0 or _switch_left > 0.0 or ammo[current] >= w.mag_size:
		return
	_reload_left = w.reload_time
	Sfx.play(&"reload", -4.0)


func _fire() -> void:
	var w := list[current]
	ammo[current] -= 1
	_cooldown = w.fire_interval
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
	for i in w.pellets:
		var dir := _spread_dir(basis, w.spread_deg)
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
		if col is Zombie:
			kind = Hit.ENEMY
			id = (col as Zombie).net_id
			enemy_hit = true
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
			else:
				agg[key] = [kind, id, 1, pos]
	_shot_visuals(current, _muzzle_pos(), ends, true)
	Sfx.play(w.id, -3.0)
	fx_shot.rpc(current, ends, kinds)
	if enemy_hit:
		hit_marker = 0.18
		Sfx.play(&"hit_marker", -8.0)
	if not agg.is_empty():
		if multiplayer.is_server():
			_srv_hits(current, origin, agg.values())
		else:
			srv_hits.rpc_id(1, current, origin, agg.values())


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
	if player.status == Player.Status.DOWNED and weapon_idx != 0:
		return
	var w := list[weapon_idx]
	var now := Time.get_ticks_msec() / 1000.0
	if now - _srv_last_shot < w.fire_interval * 0.6:
		return
	_srv_last_shot = now
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
				var dmg := int(round(w.damage_at(dist) * pellets))
				z.srv_hit(dmg, dir * w.enemy_knockback * pellets, w.enemy_stagger, player)
			Hit.PLAYER:
				var p := Net.get_player(id)
				if p == null or p == player or p.status == Player.Status.ELIMINATED:
					continue
				var flat := Vector3(dir.x, 0.0, dir.z)
				flat = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
				var push := minf(w.player_knockback * pellets, 11.0)
				p.srv_launch(flat * push + Vector3.UP * minf(pellets * 0.5, 3.5), w.player_stagger + clampf(push * 0.05, 0.0, 0.5), push >= 6.0)
			Hit.BARREL:
				var b := ExplosiveBarrel.find_by_index(get_tree(), id)
				if b != null and b.alive:
					b.srv_damage(int(round(w.damage_at(dist) * pellets)), player)


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
	var dark := Color(0.14, 0.14, 0.16)
	var wood := Color(0.36, 0.22, 0.12)
	var skin := Puppet.SKIN

	var pistol := Node3D.new()
	pistol.name = "Pistol"
	_viewmodel.add_child(pistol)
	_box(pistol, Vector3(0.05, 0.08, 0.22), Vector3(0, 0, -0.15), dark)
	_box(pistol, Vector3(0.045, 0.11, 0.06), Vector3(0, -0.085, -0.07), dark)
	_box(pistol, Vector3(0.08, 0.08, 0.1), Vector3(0, -0.1, -0.06), skin)
	_muzzles.append(_marker(pistol, Vector3(0, 0.02, -0.27)))
	_guns.append(pistol)

	var shotgun := Node3D.new()
	shotgun.name = "Shotgun"
	_viewmodel.add_child(shotgun)
	_box(shotgun, Vector3(0.045, 0.045, 0.62), Vector3(0, 0.02, -0.3), dark)
	_box(shotgun, Vector3(0.06, 0.09, 0.3), Vector3(0, -0.03, 0.06), wood)
	_box(shotgun, Vector3(0.07, 0.05, 0.17), Vector3(0, -0.03, -0.3), wood)
	_box(shotgun, Vector3(0.08, 0.08, 0.09), Vector3(0, -0.04, -0.28), skin)
	_muzzles.append(_marker(shotgun, Vector3(0, 0.02, -0.63)))
	_guns.append(shotgun)
	_refresh_viewmodel()


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _marker(parent: Node3D, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.position = pos
	parent.add_child(m)
	return m


func _refresh_viewmodel() -> void:
	for i in _guns.size():
		_guns[i].visible = i == current


func _process(delta: float) -> void:
	if _viewmodel == null or not _viewmodel.visible:
		return
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-13.0 * delta))
	_shove_anim = maxf(_shove_anim - delta, 0.0)
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
	_viewmodel.position = Vector3(0.2, -0.23 - dip - sw - down * 0.2, -0.36 + _kick * 0.07 - shove * 0.12) + bob
	_viewmodel.rotation = Vector3(_kick * 0.2 - dip * 1.1 + shove * 0.5, 0.0, -dip * 0.5)
