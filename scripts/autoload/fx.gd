extends Node
## Cosmetic effects. Everything here is local-only visuals/audio; the few RPCs below are tiny events
## ("an enemy died here", "an explosion happened here") so each peer renders its own copy.

signal camera_shake(strength: float, origin: Vector3)

enum Impact { WORLD, FLESH }

var world: Node3D = null ## set by Main; parent for all spawned effects

var _ragdolls: Array = [] ## of Ragdoll / ZombieRig corpses (anything with retire())
var _debris: Array = [] ## of RigidBody3D
var _spark_mesh: SphereMesh
var _spark_mat: StandardMaterial3D
var _tracer_mat: StandardMaterial3D
var _flash_mat: StandardMaterial3D
var _boom_mat: StandardMaterial3D


func _ready() -> void:
	_spark_mat = StandardMaterial3D.new()
	_spark_mat.vertex_color_use_as_albedo = true
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mesh = SphereMesh.new()
	_spark_mesh.radius = 0.03
	_spark_mesh.height = 0.06
	_spark_mesh.radial_segments = 6
	_spark_mesh.rings = 3
	_spark_mesh.material = _spark_mat
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1.0, 0.9, 0.55)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1.0, 0.85, 0.4)
	_boom_mat = StandardMaterial3D.new()
	_boom_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_boom_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_boom_mat.albedo_color = Color(1.0, 0.55, 0.15, 0.85)


# --- ragdolls (capped) -----------------------------------------------------------------------

func add_ragdoll(parts: Array, velocity: Vector3) -> Ragdoll:
	if world == null:
		return null
	_ragdolls = _prune(_ragdolls)
	while _ragdolls.size() >= GameConfig.MAX_RAGDOLLS:
		(_ragdolls.pop_front() as Ragdoll).retire()
	var r := Ragdoll.spawn(world, parts, velocity)
	_ragdolls.append(r)
	return r


## Drops entries whose node has been freed. Untyped on purpose: a typed array/lambda parameter cannot hold
## (or even be handed) a freed object.
func _prune(list: Array) -> Array:
	var out: Array = []
	for x in list:
		if is_instance_valid(x):
			out.append(x)
	return out


## Dead enemies are freed on the host immediately; every peer builds its own corpse from this event, carrying on from
## the zombie's pose and momentum if its node still exists here.
@rpc("authority", "call_local", "reliable")
func enemy_died(pos: Vector3, yaw: float, impulse: Vector3, kind: int = 0, id: int = 0) -> void:
	if world == null:
		return
	var src := Zombie.find_by_id(get_tree(), id) if id != 0 else null
	_ragdolls = _prune(_ragdolls)
	while _ragdolls.size() >= GameConfig.MAX_RAGDOLLS:
		_ragdolls.pop_front().retire()
	_ragdolls.append(ZombieRig.spawn_corpse(world, kind, pos, yaw, impulse, src.puppet if src != null else null))
	Sfx.play_at(&"zombie_die", pos + Vector3.UP, -2.0, randf_range(0.9, 1.1))


@rpc("authority", "call_local", "reliable")
func explosion(pos: Vector3, radius: float) -> void:
	if world == null:
		return
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	ball.mesh = sm
	ball.material_override = _boom_mat.duplicate()
	world.add_child(ball)
	ball.global_position = pos + Vector3(0, 0.6, 0)
	ball.scale = Vector3.ONE * 0.3
	var tw := ball.create_tween().set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * radius * 0.55, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(ball.material_override, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(ball.queue_free)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 6.0
	light.omni_range = radius * 2.0
	world.add_child(light)
	light.global_position = pos + Vector3(0, 1.0, 0)
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.4)
	lt.tween_callback(light.queue_free)
	_burst(pos + Vector3(0, 0.5, 0), Vector3.UP, 36, Color(1.0, 0.7, 0.3), 3.0, 9.0, 180.0, 0.8)
	Sfx.play_at(&"explosion", pos, 2.0)
	camera_shake.emit(1.0, pos)


# --- local one-shots -------------------------------------------------------------------------

func impact(pos: Vector3, normal: Vector3, kind: int) -> void:
	if world == null:
		return
	if kind == Impact.FLESH:
		_burst(pos, normal, 7, Color(0.75, 0.08, 0.06), 1.5, 4.0, 55.0, 0.45)
		Sfx.play_at(&"hit_flesh", pos, -6.0, randf_range(0.9, 1.15))
	else:
		_burst(pos, normal, 6, Color(1.0, 0.85, 0.5), 2.0, 5.0, 45.0, 0.3)
		Sfx.play_at(&"hit_world", pos, -8.0, randf_range(0.9, 1.2))


func tracer(from: Vector3, to: Vector3) -> void:
	if world == null:
		return
	var d := from.distance_to(to)
	if d < 0.3:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.018, 0.018, 1.0)
	mi.mesh = bm
	mi.material_override = _tracer_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	var dir := (to - from) / d
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(dir, up), (from + to) * 0.5)
	mi.scale = Vector3(1, 1, d)
	get_tree().create_timer(0.06).timeout.connect(mi.queue_free)


func muzzle_flash(pos: Vector3, big: bool) -> void:
	if world == null:
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12 if big else 0.07
	sm.height = sm.radius * 2.0
	mi.mesh = sm
	mi.material_override = _flash_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_position = pos
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.45)
	l.light_energy = 2.5
	l.omni_range = 7.0
	mi.add_child(l)
	get_tree().create_timer(0.05).timeout.connect(mi.queue_free)


func plank_debris(pos: Vector3, outward: Vector3) -> void:
	if world == null:
		return
	_debris = _prune(_debris)
	while _debris.size() >= GameConfig.MAX_DEBRIS:
		(_debris.pop_front() as Node).queue_free()
	var rb := RigidBody3D.new()
	rb.collision_layer = GameConfig.L_RAGDOLLS
	rb.collision_mask = GameConfig.MASK_RAGDOLL
	rb.gravity_scale = GameConfig.GRAVITY / 9.8
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.9, 0.18, 0.05)
	cs.shape = bs
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.36, 0.2)
	mi.material_override = m
	rb.add_child(mi)
	world.add_child(rb)
	rb.global_position = pos
	rb.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	rb.linear_velocity = outward * randf_range(2.0, 4.5) + Vector3(randf_range(-1, 1), randf_range(1.5, 3.5), randf_range(-1, 1))
	rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	_debris.append(rb)
	var life := rb.create_tween() # tied to rb, so it dies with it if the cap evicts it first
	life.tween_interval(3.5)
	life.tween_callback(rb.queue_free)


func _burst(pos: Vector3, normal: Vector3, count: int, color: Color, vmin: float, vmax: float, spread: float, life: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = count
	p.lifetime = life
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = spread
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = Vector3(0, -10, 0)
	p.mesh = _spark_mesh
	p.color = color
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


# --- snacks: rare healing drops ----------------------------------------------------------------------------
# The host decides drops and pickups; every peer just draws the snack while it exists.

var _snack_nodes: Dictionary = {} ## id -> Node3D (every peer)
var _snack_info: Dictionary = {} ## id -> {"pos": Vector3, "left": float} (host only)
var _next_snack := 1


## Host: called when a zombie dies. Chance depends on the kind (Brutes drop one almost always).
func srv_try_snack(pos: Vector3, zombie_kind: int) -> void:
	if not multiplayer.is_server():
		return
	var chance := GameConfig.SNACK_CHANCE
	if zombie_kind == Zombie.Kind.BRUTE:
		chance = GameConfig.SNACK_CHANCE_BRUTE
	elif zombie_kind == Zombie.Kind.HUGGER:
		chance = GameConfig.SNACK_CHANCE_HUGGER
	elif zombie_kind == Zombie.Kind.LEAPER:
		chance = GameConfig.SNACK_CHANCE_LEAPER
	elif zombie_kind == Zombie.Kind.BLOATER:
		chance = GameConfig.SNACK_CHANCE_BLOATER
	elif zombie_kind == Zombie.Kind.CRAWLER:
		chance = GameConfig.SNACK_CHANCE_CRAWLER
	if Net.debug_snack_chance >= 0.0:
		chance = Net.debug_snack_chance
	if randf() >= chance:
		return
	var id := _next_snack
	_next_snack += 1
	var p := pos
	p.y = 0.0
	_snack_info[id] = {"pos": p, "left": GameConfig.SNACK_LIFETIME}
	snack_spawned.rpc(id, p)


func srv_clear_snacks() -> void:
	for id in _snack_info.keys():
		snack_gone.rpc(id, 0)
	_snack_info.clear()


@rpc("authority", "call_local", "reliable")
func snack_spawned(id: int, pos: Vector3) -> void:
	if world == null:
		return
	var n := Node3D.new()
	var donut := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.07
	tm.outer_radius = 0.17
	donut.mesh = tm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.55, 0.75)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.4, 0.6)
	m.emission_energy_multiplier = 0.6
	donut.material_override = m
	n.add_child(donut)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.75)
	l.light_energy = 0.8
	l.omni_range = 2.5
	n.add_child(l)
	world.add_child(n)
	n.global_position = pos + Vector3(0, 0.5, 0)
	_snack_nodes[id] = n
	Sfx.play_at(&"hit_marker", pos + Vector3.UP, -6.0, 1.6)


## `by` is the peer who ate it (0 = it rotted away).
@rpc("authority", "call_local", "reliable")
func snack_gone(id: int, by: int) -> void:
	var n: Node3D = _snack_nodes.get(id)
	_snack_nodes.erase(id)
	if is_instance_valid(n):
		if by != 0:
			Sfx.play_at(&"revive", n.global_position, -4.0, 1.4)
		n.queue_free()


func _process(delta: float) -> void:
	for n in _snack_nodes.values():
		if is_instance_valid(n):
			n.rotate_y(delta * 2.5)
			n.position.y += sin(Time.get_ticks_msec() / 250.0) * delta * 0.15


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _snack_info.is_empty():
		return
	for id in _snack_info.keys():
		var info: Dictionary = _snack_info[id]
		info["left"] = float(info["left"]) - delta
		var eaten := 0
		for p in Net.all_players():
			if p.status == Player.Status.ALIVE and p.hp < GameConfig.PLAYER_MAX_HP and p.global_position.distance_to(info["pos"]) < 1.3:
				if p.srv_heal(GameConfig.SNACK_HEAL):
					eaten = p.peer_id
					break
		if eaten != 0 or float(info["left"]) <= 0.0:
			_snack_info.erase(id)
			snack_gone.rpc(id, eaten)


## Bloater popping: a green splat. The push/damage is applied on the host (zombie.gd), this is only the show.
@rpc("authority", "call_local", "reliable")
func goo_burst(pos: Vector3) -> void:
	if world == null:
		return
	_burst(pos + Vector3(0, 0.8, 0), Vector3.UP, 40, Color(0.5, 0.85, 0.2), 2.0, 7.0, 180.0, 0.9)
	Sfx.play_at(&"explosion", pos, -8.0, 1.8)
	camera_shake.emit(0.5, pos)


# --- lightning (Tesla Gun) ------------------------------------------------------------------------------

var lightning_count := 0 ## how many chains were drawn (tests read this)


## A jagged electric arc through the given points (shooter -> first zombie -> chained zombies).
@rpc("authority", "call_local", "unreliable")
func lightning(points: PackedVector3Array) -> void:
	if world == null or points.size() < 2:
		return
	lightning_count += 1
	for i in points.size() - 1:
		_arc(points[i], points[i + 1])
	for i in range(1, points.size()):
		var l := OmniLight3D.new()
		l.light_color = Color(0.5, 0.8, 1.0)
		l.light_energy = 3.0
		l.omni_range = 5.0
		world.add_child(l)
		l.global_position = points[i]
		get_tree().create_timer(0.12).timeout.connect(l.queue_free)
		_burst(points[i], Vector3.UP, 10, Color(0.6, 0.9, 1.0), 2.0, 5.0, 180.0, 0.3)
	Sfx.play_at(&"hit_marker", points[1], -2.0, 0.6)
	Sfx.play_at(&"launch", points[1], -6.0, 1.8)


func _arc(from: Vector3, to: Vector3) -> void:
	var d := from.distance_to(to)
	if d < 0.2:
		return
	var dir := (to - from) / d
	var side := dir.cross(Vector3.UP).normalized() if absf(dir.y) < 0.95 else Vector3.RIGHT
	var up := side.cross(dir).normalized()
	var segs := clampi(int(d / 0.6), 3, 10)
	var prev := from
	for s in range(1, segs + 1):
		var p := from.lerp(to, float(s) / segs)
		if s < segs:
			p += side * randf_range(-0.28, 0.28) + up * randf_range(-0.28, 0.28)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.05, 1.0)
		mi.mesh = bm
		mi.material_override = _flash_mat_blue()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mi)
		var seg := p - prev
		var sl := seg.length()
		if sl > 0.01:
			var sd := seg / sl
			var u := Vector3.UP if absf(sd.y) < 0.95 else Vector3.RIGHT
			mi.global_transform = Transform3D(Basis.looking_at(sd, u), (prev + p) * 0.5)
			mi.scale = Vector3(1, 1, sl)
		get_tree().create_timer(0.11).timeout.connect(mi.queue_free)
		prev = p


var _blue_mat: StandardMaterial3D = null


func _flash_mat_blue() -> StandardMaterial3D:
	if _blue_mat == null:
		_blue_mat = StandardMaterial3D.new()
		_blue_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blue_mat.albedo_color = Color(0.65, 0.92, 1.0)
	return _blue_mat
