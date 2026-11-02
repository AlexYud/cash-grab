extends Node
## Cosmetic effects. Everything here is local-only visuals/audio; the few RPCs below are tiny events
## ("an enemy died here", "an explosion happened here") so each peer renders its own copy.

signal camera_shake(strength: float, origin: Vector3)

enum Impact { WORLD, FLESH }

var world: Node3D = null ## set by Main; parent for all spawned effects

var _ragdolls: Array = [] ## of Ragdoll
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


## Dead enemies are freed on the host immediately; every peer builds its own ragdoll from this event.
@rpc("authority", "call_local", "reliable")
func enemy_died(pos: Vector3, yaw: float, impulse: Vector3) -> void:
	if world == null:
		return
	var pup := Puppet.new()
	world.add_child(pup)
	pup.build(Puppet.Kind.ZOMBIE, Color.WHITE)
	pup.global_position = pos
	pup.rotation.y = yaw
	add_ragdoll(pup.get_ragdoll_parts(), impulse)
	pup.queue_free()
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
