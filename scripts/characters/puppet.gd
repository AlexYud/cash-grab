class_name Puppet
extends Node3D
## Procedural placeholder character (players and zombies). Origin is at the feet, facing -Z.
## Built from boxes so it needs no art; swap for a rigged model later by replacing this node.

enum Kind { PLAYER, ZOMBIE }

const SKIN := Color(0.93, 0.76, 0.62)
const ZOMBIE_SKIN := Color(0.46, 0.58, 0.38)
const ZOMBIE_SHIRT := Color(0.32, 0.27, 0.24)
const PANTS := Color(0.22, 0.25, 0.33)
const HAT := Color(0.24, 0.16, 0.1)
const ZOMBIE_ATTACK_TIME := 0.55
const SWING_TIME := 0.42

var kind: int = Kind.PLAYER
var downed := false
var dancing := false
var holding_gun := true
var body: Node3D
var _parts: Array[Dictionary] = []
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _head: Node3D
var _guns: Array[Node3D] = []
var _mats: Array[StandardMaterial3D] = []
var _phase := 0.0
var _t := 0.0
var _shove_t := 0.0
var _attack_t := 0.0
var _hurt_t := 0.0
var _swing_t := 0.0 ## a melee swing seen on this character (see play_swing)
var _swing_kind := 0
var _body_y := 0.82
var _body_pitch := 0.0
var _ragdoll: Ragdoll = null
var _ragdoll_left := 0.0


func build(p_kind: int, shirt: Color, skin_override: Color = Color(0, 0, 0, 0)) -> void:
	kind = p_kind
	body = Node3D.new()
	body.name = "Body"
	body.position = Vector3(0, 0.82, 0)
	add_child(body)
	var zombie := kind == Kind.ZOMBIE
	var skin_c := ZOMBIE_SKIN if zombie else SKIN
	if skin_override.a > 0.0:
		skin_c = skin_override
	var shirt_c := ZOMBIE_SHIRT if (zombie and shirt == Color.WHITE) else shirt

	var torso := _mesh_node(body, "Torso", BoxMesh.new(), Vector3(0.46, 0.6, 0.26), shirt_c)
	torso.position = Vector3(0, 0.3, 0)
	_parts.append({"name": &"torso", "center": torso, "size": Vector3(0.46, 0.6, 0.26), "shape": "box", "anchor": Vector3.ZERO})

	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, 0.76, 0)
	body.add_child(_head)
	var skull := SphereMesh.new()
	skull.radius = 0.14
	skull.height = 0.28
	_attach_mesh(_head, "Skull", skull, skin_c)
	if not zombie:
		var brim := CylinderMesh.new()
		brim.top_radius = 0.27
		brim.bottom_radius = 0.27
		brim.height = 0.025
		var brim_n := _attach_mesh(_head, "HatBrim", brim, HAT)
		brim_n.position = Vector3(0, 0.1, 0)
		var crown := CylinderMesh.new()
		crown.top_radius = 0.12
		crown.bottom_radius = 0.14
		crown.height = 0.15
		var crown_n := _attach_mesh(_head, "HatCrown", crown, HAT)
		crown_n.position = Vector3(0, 0.18, 0)
	_parts.append({"name": &"head", "center": _head, "size": Vector3(0.28, 0.28, 0.28), "shape": "sphere", "anchor": Vector3(0, -0.14, 0)})

	_arm_l = _limb("ArmL", Vector3(-0.30, 0.56, 0), Vector3(0.13, 0.58, 0.13), skin_c if zombie else shirt_c)
	_arm_r = _limb("ArmR", Vector3(0.30, 0.56, 0), Vector3(0.13, 0.58, 0.13), skin_c if zombie else shirt_c)
	_leg_l = _limb("LegL", Vector3(-0.12, 0.0, 0), Vector3(0.17, 0.8, 0.19), PANTS)
	_leg_r = _limb("LegR", Vector3(0.12, 0.0, 0), Vector3(0.17, 0.8, 0.19), PANTS)
	# hands (skin-coloured caps) so shirt-coloured sleeves read as arms
	if not zombie:
		for arm in [_arm_l, _arm_r]:
			var hand := _attach_mesh(arm.get_child(0), "Hand", BoxMesh.new(), SKIN)
			(hand.mesh as BoxMesh).size = Vector3(0.12, 0.12, 0.12)
			hand.position = Vector3(0, -0.28, 0)

	if not zombie:
		_guns.append(_make_gun(_arm_r, Vector3(0.05, 0.28, 0.07), -0.56, Color(0.15, 0.15, 0.17)))
		_guns.append(_make_gun(_arm_r, Vector3(0.06, 0.78, 0.08), -0.78, Color(0.35, 0.22, 0.12)))
		_guns.append(_make_gun(_arm_r, Vector3(0.1, 0.55, 0.1), -0.7, Color(0.1, 0.5, 0.55)))
		_guns.append(_make_gun(_arm_r, Vector3(0.12, 0.4, 0.12), -0.64, Color(0.55, 0.2, 0.75)))
		_guns.append(_make_gun(_arm_r, Vector3(0.12, 0.5, 0.12), -0.68, Color(0.75, 0.45, 0.2)))
		_guns.append(_make_gun(_arm_r, Vector3(0.14, 0.45, 0.14), -0.66, Color(0.95, 0.45, 0.7)))
		_guns.append(_make_gun(_arm_r, Vector3(0.08, 0.62, 0.1), -0.66, Color(0.2, 0.22, 0.2))) # assault rifle
		_guns.append(_make_gun(_arm_r, Vector3(0.06, 0.95, 0.07), -0.85, Color(0.1, 0.1, 0.12))) # sniper
		_guns.append(_make_gun(_arm_r, Vector3(0.08, 0.85, 0.08), -0.78, Color(0.78, 0.6, 0.35))) # bat
		_guns.append(_make_gun(_arm_r, Vector3(0.03, 0.9, 0.07), -0.8, Color(0.82, 0.84, 0.9))) # katana
		var axe := _make_gun(_arm_r, Vector3(0.05, 0.75, 0.05), -0.7, Color(0.36, 0.22, 0.12))
		var head := BoxMesh.new()
		head.size = Vector3(0.22, 0.18, 0.04)
		_attach_mesh(axe, "AxeHead", head, Color(0.7, 0.72, 0.78)).position = Vector3(0, -0.3, 0)
		_guns.append(axe)
		set_weapon(0)


func _mesh_node(parent: Node3D, nm: String, mesh: Mesh, size: Vector3, color: Color) -> MeshInstance3D:
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	var mi := _attach_mesh(parent, nm, mesh, color)
	return mi


func _attach_mesh(parent: Node, nm: String, mesh: Mesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mi.material_override = m
	_mats.append(m)
	parent.add_child(mi)
	return mi


## A limb is a pivot (rotates at the joint) holding a centre node that carries the mesh.
func _limb(nm: String, pivot_pos: Vector3, size: Vector3, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = nm
	pivot.position = pivot_pos
	body.add_child(pivot)
	var center := Node3D.new()
	center.name = nm + "Center"
	center.position = Vector3(0, -size.y * 0.5, 0)
	pivot.add_child(center)
	var bm := BoxMesh.new()
	bm.size = size
	_attach_mesh(center, nm + "Mesh", bm, color)
	_parts.append({"name": StringName(nm.to_lower()), "center": center, "size": size, "shape": "box", "anchor": Vector3(0, size.y * 0.5, 0)})
	return pivot


func _make_gun(arm: Node3D, size: Vector3, y: float, color: Color) -> Node3D:
	var g := Node3D.new()
	g.name = "Gun"
	g.position = Vector3(0, y, 0)
	arm.add_child(g)
	var bm := BoxMesh.new()
	bm.size = size
	_attach_mesh(g, "GunMesh", bm, color)
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, -size.y * 0.5, 0)
	g.add_child(muzzle)
	return g


# --- public API ------------------------------------------------------------------------------

func set_weapon(idx: int) -> void:
	for i in _guns.size():
		_guns[i].visible = i == idx


## World position of the active gun's muzzle (for tracers / flashes seen on remote players).
func muzzle_position(weapon_idx: int) -> Vector3:
	if _guns.is_empty():
		return global_position + Vector3(0, 1.4, 0)
	var g := _guns[clampi(weapon_idx, 0, _guns.size() - 1)]
	return (g.get_node("Muzzle") as Node3D).global_position


func set_dancing(v: bool) -> void:
	dancing = v
	if not v:
		body.rotation.z = 0.0


func set_downed(v: bool) -> void:
	downed = v


func play_shove() -> void:
	_shove_t = 0.3


func play_attack() -> void:
	_attack_t = ZOMBIE_ATTACK_TIME


## Melee swing for other players' characters: 0 overhead chop, 1 sweep right-to-left, 2 sweep back.
func play_swing(step: int, finisher: bool) -> void:
	_swing_kind = 0 if finisher else (1 if step % 2 == 0 else 2)
	_swing_t = SWING_TIME


func play_hurt() -> void:
	_hurt_t = 0.18


func animate(delta: float, speed: float, airborne: bool, sprinting: bool = false, aim_pitch: float = 0.0, staggered: bool = false) -> void:
	if _ragdoll_left > 0.0:
		return
	_t += delta
	_shove_t = maxf(_shove_t - delta, 0.0)
	_attack_t = maxf(_attack_t - delta, 0.0)
	_swing_t = maxf(_swing_t - delta, 0.0)
	_hurt_t = maxf(_hurt_t - delta, 0.0)
	var amp := clampf(speed / 5.0, 0.0, 1.3)
	if speed > 0.3 and not airborne:
		_phase += speed * delta * (1.5 if downed else 1.9)
	var swing := sin(_phase) * amp

	var target_y := 0.22 if downed else 0.82
	var target_pitch := -deg_to_rad(86.0) if downed else 0.0
	var lean := 0.0
	if kind == Kind.ZOMBIE:
		lean = deg_to_rad(10.0)
	elif sprinting:
		lean = deg_to_rad(12.0)
	if _shove_t > 0.0:
		lean += deg_to_rad(14.0) * sin(_shove_t / 0.3 * PI)
	if staggered and not downed:
		lean -= deg_to_rad(18.0) # knocked back: reeling, arms flailing
	var k := 1.0 - exp(-14.0 * delta)
	_body_y = lerpf(_body_y, target_y, k)
	_body_pitch = lerpf(_body_pitch, target_pitch + (0.0 if downed else lean), k)
	body.position.y = _body_y + (0.0 if downed else sin(_t * 2.0) * 0.004)
	body.rotation.x = _body_pitch
	if not dancing:
		body.rotation.z = lerpf(body.rotation.z, sin(_t * 16.0) * 0.2 if (staggered and not downed) else 0.0, k)

	var leg_amp := 0.65
	_leg_l.rotation.x = swing * leg_amp
	_leg_r.rotation.x = -swing * leg_amp
	if airborne:
		_leg_l.rotation.x = 0.35
		_leg_r.rotation.x = -0.25
	_head.rotation.x = 0.0 if downed else clampf(aim_pitch, -0.9, 0.9)
	var aim := clampf(aim_pitch, -0.9, 0.9)

	if dancing:
		_arm_l.rotation.x = deg_to_rad(165.0) + sin(_t * 13.0) * 0.5
		_arm_r.rotation.x = deg_to_rad(165.0) - sin(_t * 13.0) * 0.5
		_leg_l.rotation.x = sin(_t * 9.0) * 0.5
		_leg_r.rotation.x = -sin(_t * 9.0) * 0.5
		body.rotation.z = sin(_t * 9.0) * 0.28
		body.position.y = _body_y + absf(sin(_t * 9.0)) * 0.08
	elif downed:
		var crawl := sin(_phase * 0.9)
		_arm_l.rotation.x = deg_to_rad(160.0) + crawl * 0.35 * amp
		_arm_r.rotation.x = deg_to_rad(160.0) - crawl * 0.35 * amp
		_leg_l.rotation.x = swing * 0.25
		_leg_r.rotation.x = -swing * 0.25
		if holding_gun and kind == Kind.PLAYER:
			_arm_r.rotation.x = deg_to_rad(175.0)
	elif kind == Kind.ZOMBIE:
		var wob := sin(_t * 3.0) * 0.12
		var a := deg_to_rad(82.0) + wob
		if _attack_t > 0.0:
			var u := 1.0 - _attack_t / ZOMBIE_ATTACK_TIME # 0 -> 1 over the swing
			a = lerpf(deg_to_rad(120.0), deg_to_rad(15.0), sin(clampf(u * 1.3, 0.0, 1.0) * PI * 0.5))
		_arm_l.rotation.x = a
		_arm_r.rotation.x = a - 0.08
	else:
		if staggered:
			_arm_l.rotation.x = deg_to_rad(120.0) + sin(_t * 16.0) * 0.7
			_arm_r.rotation.x = deg_to_rad(120.0) - sin(_t * 16.0) * 0.7
		elif _shove_t > 0.0:
			var s := sin(_shove_t / 0.3 * PI)
			_arm_l.rotation.x = deg_to_rad(70.0 + 35.0 * s)
			_arm_r.rotation.x = deg_to_rad(85.0 + 25.0 * s)
		elif holding_gun and not sprinting:
			_arm_r.rotation.x = deg_to_rad(86.0) + aim
			_arm_l.rotation.x = deg_to_rad(72.0) + aim
		else:
			_arm_l.rotation.x = -swing * 0.8
			_arm_r.rotation.x = swing * 0.8

	if _swing_t > 0.0 and not downed and kind == Kind.PLAYER: # a melee swing: wind up, strike, follow through
		var u := 1.0 - _swing_t / SWING_TIME
		if _swing_kind == 0:
			var a := lerpf(86.0, 178.0, smoothstep(0.0, 0.4, u))
			a = lerpf(a, 12.0, smoothstep(0.4, 0.62, u))
			a = lerpf(a, 86.0, smoothstep(0.62, 1.0, u))
			_arm_r.rotation.x = deg_to_rad(a)
			body.rotation.x += 0.35 * sin(smoothstep(0.4, 0.7, u) * PI) # leans into the chop
		else:
			var sgn := 1.0 if _swing_kind == 1 else -1.0
			var sweep := lerpf(-sgn * 70.0, sgn * 60.0, smoothstep(0.2, 0.65, u))
			sweep = lerpf(sweep, 0.0, smoothstep(0.65, 1.0, u))
			_arm_r.rotation.x = deg_to_rad(86.0)
			_arm_r.rotation.z = deg_to_rad(sweep)
			body.rotation.y = deg_to_rad(-sweep * 0.5)
	elif not downed and kind == Kind.PLAYER:
		_arm_r.rotation.z = lerpf(_arm_r.rotation.z, 0.0, k)
		body.rotation.y = lerpf(body.rotation.y, 0.0, k)
	var f := _hurt_t / 0.18
	for m in _mats:
		m.emission_enabled = f > 0.0
		if f > 0.0:
			m.emission = Color(1.0, 0.25, 0.2) * f


func _process(delta: float) -> void:
	if _ragdoll_left > 0.0:
		_ragdoll_left -= delta
		if _ragdoll_left <= 0.0:
			end_ragdoll()


func get_ragdoll_parts() -> Array:
	return _parts


## Hard-hit reaction: swap the live model for a local ragdoll for a moment, then swap back.
func start_ragdoll(velocity: Vector3, duration: float) -> void:
	if _ragdoll_left > 0.0 or Fx.world == null:
		return
	_ragdoll = Fx.add_ragdoll(_parts, velocity)
	_ragdoll_left = duration
	body.visible = false


func end_ragdoll() -> void:
	_ragdoll_left = 0.0
	body.visible = true
	if is_instance_valid(_ragdoll):
		_ragdoll.retire()
	_ragdoll = null


func is_ragdolling() -> bool:
	return _ragdoll_left > 0.0
