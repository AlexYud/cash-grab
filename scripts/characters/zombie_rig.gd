class_name ZombieRig
extends Node3D
## The zombie's body: the rigged humanoid in assets/, posed by code, with a physics ragdoll for when it loses control.
##
## Standing up it is an animated puppet: every frame the pose for the zombie's replicated state (walk, swing, windup,
## charge, leap, cling, dance, reel...) is worked out as bone directions and written into the skeleton. When the
## zombie trips, gets shoved over, blown up or killed, the same skeleton is handed to PhysicalBone3D bodies instead:
## nothing steers the limbs any more, they just flop. Getting up blends from wherever the ragdoll ended up back
## into the animated pose. Nothing here is replicated: every peer runs its own ragdoll (the host's zombie body
## keeps the gameplay truth and a soft tether keeps the visual ragdoll close to it).
##
## Model space, before the 180 degree turn that makes it face -Z like the rest of the game: forward +Z, character's
## left +X, up +Y. The rest pose has identity bone bases, so a bone's local rotation is its swing in its parent's frame.

const MODEL: PackedScene = preload("res://assets/basic_model_rigged.glb")
const MODEL_SCALE := 0.93 ## the model is 1.83 m tall; this makes the normal zombie about 1.7 m
const SOLE_Y := -0.975 ## model-space height of the soles in the rest pose
const SOLE := 0.085 ## from the ankle joint down to the sole
const GETUP_BLEND := 0.5
const CORPSE_LIFE := 6.0

## Gait by Zombie.Kind (0 normal, 1 brute, 2 hugger, 3 leaper, 4 bloater).
## stride: metres per full step cycle; amp: thigh swing (rad); knee: swing-phase knee bend (rad); lean: forward lean (rad);
## arms: 0 hanging .. 1 reaching straight ahead; spread: arms held away from the body; sway: hip roll; bob: head bounce;
## crouch: knees bent while moving; loll: head wobble.
const GAIT := {
	0: {"stride": 1.5, "amp": 0.55, "knee": 0.9, "lean": 0.2, "arms": 0.85, "spread": 0.15, "sway": 0.07, "bob": 0.03, "crouch": 0.0, "loll": 0.3},
	1: {"stride": 1.2, "amp": 0.45, "knee": 0.6, "lean": 0.3, "arms": 0.1, "spread": 0.55, "sway": 0.12, "bob": 0.05, "crouch": 0.1, "loll": 0.1},
	2: {"stride": 0.8, "amp": 0.85, "knee": 1.3, "lean": 0.6, "arms": 0.9, "spread": 0.1, "sway": 0.1, "bob": 0.05, "crouch": 0.5, "loll": 0.2},
	3: {"stride": 1.6, "amp": 0.7, "knee": 1.2, "lean": 0.45, "arms": 0.3, "spread": 0.25, "sway": 0.06, "bob": 0.04, "crouch": 0.3, "loll": 0.15},
	4: {"stride": 1.1, "amp": 0.4, "knee": 0.5, "lean": -0.06, "arms": 0.2, "spread": 0.75, "sway": 0.16, "bob": 0.03, "crouch": 0.05, "loll": 0.2},
	5: {"stride": 1.0, "amp": 0.75, "knee": 1.2, "lean": 0.5, "arms": 0.4, "spread": 0.4, "sway": 0.1, "bob": 0.05, "crouch": 0.4, "loll": 0.2},
}

## Physical bodies of the ragdoll: bone, the bone the body reaches towards, radius, extra length, mass, joint limits.
## The torso is two rigid blocks (hips + chest); bones in between (spine, neck, shoulders, hands, feet) ride along.
const PHYS := [
	{"bone": "mixamorig_Hips", "to": "mixamorig_Spine1", "r": 0.15, "ext": 0.0, "mass": 8.0},
	{"bone": "mixamorig_Spine1", "to": "mixamorig_Neck", "r": 0.17, "ext": 0.0, "mass": 9.0, "swing": 0.5, "twist": 0.4},
	{"bone": "mixamorig_Head", "to": "mixamorig_HeadTop_End", "r": 0.115, "ext": 0.0, "mass": 3.0, "swing": 0.8, "twist": 0.9},
	{"bone": "mixamorig_LeftArm", "to": "mixamorig_LeftForeArm", "r": 0.055, "ext": 1.0, "mass": 2.0, "swing": 1.9, "twist": 1.0},
	{"bone": "mixamorig_LeftForeArm", "to": "mixamorig_LeftHand", "r": 0.05, "ext": 1.35, "mass": 1.5, "swing": 1.7, "twist": 0.5},
	{"bone": "mixamorig_RightArm", "to": "mixamorig_RightForeArm", "r": 0.055, "ext": 1.0, "mass": 2.0, "swing": 1.9, "twist": 1.0},
	{"bone": "mixamorig_RightForeArm", "to": "mixamorig_RightHand", "r": 0.05, "ext": 1.35, "mass": 1.5, "swing": 1.7, "twist": 0.5},
	{"bone": "mixamorig_LeftUpLeg", "to": "mixamorig_LeftLeg", "r": 0.085, "ext": 1.0, "mass": 5.0, "swing": 1.4, "twist": 0.6},
	{"bone": "mixamorig_LeftLeg", "to": "mixamorig_LeftFoot", "r": 0.07, "ext": 1.25, "mass": 3.0, "swing": 1.9, "twist": 0.3},
	{"bone": "mixamorig_RightUpLeg", "to": "mixamorig_RightLeg", "r": 0.085, "ext": 1.0, "mass": 5.0, "swing": 1.4, "twist": 0.6},
	{"bone": "mixamorig_RightLeg", "to": "mixamorig_RightFoot", "r": 0.07, "ext": 1.25, "mass": 3.0, "swing": 1.9, "twist": 0.3},
]

const BONE_NAMES := {
	"hips": "mixamorig_Hips", "spine": "mixamorig_Spine", "spine1": "mixamorig_Spine1", "spine2": "mixamorig_Spine2",
	"neck": "mixamorig_Neck", "head": "mixamorig_Head",
	"arm_l": "mixamorig_LeftArm", "fore_l": "mixamorig_LeftForeArm", "hand_l": "mixamorig_LeftHand",
	"arm_r": "mixamorig_RightArm", "fore_r": "mixamorig_RightForeArm", "hand_r": "mixamorig_RightHand",
	"thigh_l": "mixamorig_LeftUpLeg", "shin_l": "mixamorig_LeftLeg", "foot_l": "mixamorig_LeftFoot",
	"thigh_r": "mixamorig_RightUpLeg", "shin_r": "mixamorig_RightLeg", "foot_r": "mixamorig_RightFoot",
}

static var _meshes := {} ## style key -> tinted ArrayMesh, shared by every zombie of that look

var skeleton: Skeleton3D
var model: Node3D
var corpse := false
var kind := 0

var _mesh_inst: MeshInstance3D
var _mat: StandardMaterial3D
var _b := {} ## key -> bone index
var _hips_rest := Vector3.ZERO
var _ax_arm_l := Vector3.RIGHT
var _ax_fore_l := Vector3.RIGHT
var _ax_arm_r := Vector3.LEFT
var _ax_fore_r := Vector3.LEFT
var _ax_thigh_l := Vector3.DOWN
var _ax_shin_l := Vector3.DOWN
var _ax_thigh_r := Vector3.DOWN
var _ax_shin_r := Vector3.DOWN
var _pose := Pose.new()
var _t := randf() * 20.0
var _state_t := 0.0
var _phase := randf() * TAU
var _seed := randf() * TAU
var _limp := randf_range(0.0, 0.35)
var _state := -1
var _rising := 0.0 ## time left of the zombie's get-up (its STAGGER state then is not a reel)
var _attack_t := 0.0
var _hurt_t := 0.0
var _tint := Color.WHITE
var _tint_t := 0.0
var _life := CORPSE_LIFE
var _retiring := false

# ragdoll
var _sim: PhysicalBoneSimulator3D
var _pbs: Array[PhysicalBone3D] = []
var _ragdolling := false
var _tether: Node3D = null
var _kick := Vector3.ZERO
var _kick_t := 0.0
var _snap: Array[Quaternion] = []
var _snap_hips := Vector3.ZERO
var _blend := 1.0


class Pose:
	var hips := Vector3.ZERO ## sway sideways/forward (x, z) and an extra lift (y)
	var hips_rot := Quaternion.IDENTITY
	var spine := Vector3.ZERO ## whole-torso pitch (forward), yaw, roll
	var neck := Vector3.ZERO
	var head := Vector3.ZERO
	var arm_l := Vector3(0.15, -1.0, 0.1)
	var fore_l := Vector3(0.15, -1.0, 0.1)
	var arm_r := Vector3(-0.15, -1.0, 0.1)
	var fore_r := Vector3(-0.15, -1.0, 0.1)
	var thigh_l := Vector3.DOWN
	var shin_l := Vector3.DOWN
	var thigh_r := Vector3.DOWN
	var shin_r := Vector3.DOWN
	var plant := true ## keep the lowest foot on the ground (false in the air)
	var lift := 0.0 ## height of the hips above their rest height when not planted


func build(style: Dictionary) -> void:
	kind = style.get("kind", 0)
	model = Node3D.new()
	model.name = "Model"
	model.rotation.y = PI
	model.scale = Vector3.ONE * MODEL_SCALE # uniform only: Jolt cannot scale a body sideways
	model.position.y = -SOLE_Y * MODEL_SCALE
	add_child(model)
	var inst := MODEL.instantiate()
	model.add_child(inst)
	skeleton = inst.find_child("Skeleton3D", true, false) as Skeleton3D
	_mesh_inst = skeleton.find_child("Body", true, false) as MeshInstance3D
	_mesh_inst.mesh = _tinted_mesh(_mesh_inst.mesh, style)
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.9
	_mesh_inst.material_override = _mat
	_mesh_inst.extra_cull_margin = 2.0 # a flung ragdoll leaves the bind-pose bounds
	for k in BONE_NAMES:
		_b[k] = skeleton.find_bone(BONE_NAMES[k])
	_hips_rest = skeleton.get_bone_rest(_b["hips"]).origin
	_snap.resize(skeleton.get_bone_count())
	# the rest pose is not a perfect T: the arms slope down a little. Aim from where each bone really points.
	_ax_arm_l = _rest_axis("arm_l", "fore_l")
	_ax_fore_l = _rest_axis("fore_l", "hand_l")
	_ax_arm_r = _rest_axis("arm_r", "fore_r")
	_ax_fore_r = _rest_axis("fore_r", "hand_r")
	_ax_thigh_l = _rest_axis("thigh_l", "shin_l")
	_ax_shin_l = _rest_axis("shin_l", "foot_l")
	_ax_thigh_r = _rest_axis("thigh_r", "shin_r")
	_ax_shin_r = _rest_axis("shin_r", "foot_r")


func _rest_axis(from_key: String, to_key: String) -> Vector3:
	return (skeleton.get_bone_global_rest(_b[to_key]).origin - skeleton.get_bone_global_rest(_b[from_key]).origin).normalized()


# --- look --------------------------------------------------------------------------------------------

## One grey material in the file: colour the vertices by body region instead (skin, shirt, trousers, shoes).
static func _tinted_mesh(src: Mesh, style: Dictionary) -> Mesh:
	var shirt: Color = style["shirt"]
	var skin: Color = style["skin"]
	if skin.a <= 0.0:
		skin = Puppet.ZOMBIE_SKIN
	if shirt == Color.WHITE:
		shirt = Puppet.ZOMBIE_SHIRT
	var key := "%s|%s" % [shirt, skin]
	if _meshes.has(key):
		return _meshes[key]
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for i in verts.size():
		var v := verts[i]
		var ax := absf(v.x)
		var c: Color
		if v.y < -0.9:
			c = Color(0.16, 0.14, 0.13)
		elif v.y < 0.06 and ax < 0.32:
			c = Puppet.PANTS
		elif v.y > 0.57 or ax > 0.43:
			c = skin
		else:
			c = shirt
		var shade := 0.86 + 0.14 * fposmod(sin(v.x * 91.7 + v.y * 57.3 + v.z * 31.1) * 43758.5, 1.0) # a worn, patchy look
		colors[i] = Color(c.r * shade, c.g * shade, c.b * shade)
	arrays[Mesh.ARRAY_COLOR] = colors
	var bones = arrays[Mesh.ARRAY_BONES]
	var flags := 0
	if bones != null and bones.size() == verts.size() * 8:
		flags = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	_meshes[key] = m
	return m


func play_attack() -> void:
	_attack_t = 0.55


func play_hurt() -> void:
	_hurt_t = 0.18


func is_ragdolling() -> bool:
	return _ragdolling


## Middle of the head as animated right now (what a headshot is measured from).
func head_position() -> Vector3:
	var sk := skeleton
	var a := sk.get_bone_global_pose(_b["head"]).origin
	var b := sk.get_bone_global_pose(sk.find_bone("mixamorig_HeadTop_End")).origin
	return sk.global_transform * ((a + b) * 0.5)


## World position of the pelvis: the physics body while limp (the skeleton's own bone transforms do not report the
## simulated pose), the animated bone otherwise.
func hips_position() -> Vector3:
	if _ragdolling and not _pbs.is_empty():
		return _pbs[0].global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(_b["hips"]).origin


# --- animation ---------------------------------------------------------------------------------------

## speed: metres per second the zombie is actually walking. state: Zombie.State.
func animate(delta: float, speed: float, state: int, airborne: bool = false) -> void:
	_t += delta
	_attack_t = maxf(_attack_t - delta, 0.0)
	_hurt_t = maxf(_hurt_t - delta, 0.0)
	if state != _state:
		_state = state
		_state_t = 0.0
	_state_t += delta
	# crawlers: the whole body is rolled upside down on the ceiling and pitched up the wall (see Zombie._tick_crawl)
	var want_pitch := PI / 2.0 if state == Zombie.State.CLIMB else 0.0
	var want_roll := PI if state == Zombie.State.CEILING else 0.0
	var turn := 1.0 - exp(-(7.0 if state == Zombie.State.DROP else 10.0) * delta)
	rotation.x = lerp_angle(rotation.x, want_pitch, turn)
	rotation.z = lerp_angle(rotation.z, want_roll, turn)
	if _tint_t > 0.0: # a bleeding / frozen colour wash
		_tint_t -= delta
		_mat.albedo_color = Color.WHITE.lerp(_tint, minf(_tint_t / 0.5, 1.0)) # fades out over the last half second
	elif _mat.albedo_color != Color.WHITE:
		_mat.albedo_color = Color.WHITE
	if _hurt_t > 0.0 or _mat.emission_enabled:
		var f := _hurt_t / 0.18
		_mat.emission_enabled = f > 0.0
		_mat.emission = Color(1.0, 0.25, 0.2) * f
	if _ragdolling or skeleton == null:
		return
	_rising = maxf(_rising - delta, 0.0)
	if _rising > 0.0 and state == Zombie.State.STAGGER:
		state = Zombie.State.IDLE # getting up looks like standing up, not like reeling from a hit
	var g: Dictionary = GAIT[kind]
	if speed > 0.2 and not airborne:
		_phase += TAU * speed / float(g["stride"]) * delta
	_compose(state, speed, airborne, g)
	var w := 1.0
	if _blend < 1.0:
		_blend = minf(_blend + delta / GETUP_BLEND, 1.0)
		w = _blend * _blend * (3.0 - 2.0 * _blend)
	_write(_pose, w)


func _compose(state: int, speed: float, _airborne: bool, g: Dictionary) -> void:
	var p := _pose
	p.hips = Vector3.ZERO
	p.hips_rot = Quaternion.IDENTITY
	p.spine = Vector3.ZERO
	p.neck = Vector3.ZERO
	p.head = Vector3.ZERO
	p.plant = true
	p.lift = 0.0
	var moving := clampf(speed / 2.0, 0.0, 1.0)
	var amp: float = g["amp"] * clampf(speed / 2.4, 0.0, 1.4)
	var lean: float = g["lean"] * (0.4 + 0.6 * moving)
	var crouch: float = g["crouch"]
	var sway: float = g["sway"] * moving
	var spread: float = g["spread"]
	var reach: float = g["arms"]
	var ph := _phase
	var knee: float = g["knee"]
	var kdrag := 0.0
	var head_roll: float = sin(_t * 0.9 + _seed) * g["loll"]
	var head_pitch: float = 0.25 + 0.15 * sin(_t * 0.6 + _seed * 2.0)

	match state:
		Zombie.State.CHARGE: # brute: head down, steaming ahead, arms flung back
			lean = 0.7
			amp = 0.8
			knee = 1.0
			ph = _t * 17.0
			reach = -0.5
			spread = 0.35
			head_pitch = 0.5
			sway = 0.1
		Zombie.State.LEAP, Zombie.State.DROP:
			p.plant = false
			p.lift = 0.55
			lean = 0.45
			reach = 1.0
			spread = 0.05
			amp = 0.0
			head_pitch = -0.15
		Zombie.State.LATCHED: # hugger clinging to a player's front
			lean = -0.05
			reach = 1.0
			spread = 0.0
			amp = 0.0
			crouch = 0.0
			head_pitch = 0.1
		Zombie.State.DANCE:
			ph = _t * 9.0
			amp = 0.35
			knee = 0.9
			sway = 0.3
			lean = 0.0
		Zombie.State.STAGGER:
			lean = -0.3
			amp = 0.0
			sway = 0.3
			head_pitch = -0.2
		Zombie.State.ATTACK:
			if kind == 1: # brute winding up: hunched, stamping, chest forward
				crouch = 0.35
				lean = 0.25 + 0.1 * sin(_t * 18.0)
				ph = _t * 11.0
				amp = 0.35
				reach = -0.3
				spread = 0.6
				head_pitch = 0.5
			elif kind == 3: # leaper coiling up
				crouch = 1.0
				lean = 0.7
				reach = -0.4
				spread = 0.3
				head_pitch = 0.1
			else:
				amp = 0.0
		Zombie.State.IDLE, Zombie.State.BARRICADE:
			amp = 0.0
			lean = g["lean"] * 0.6
			sway = 0.04
	# --- hips, torso and head ---
	var step := sin(ph)
	var hips_yaw := 0.12 * step * moving
	var hips_roll: float = sway * cos(ph)
	if state == Zombie.State.DANCE:
		hips_roll = sway * sin(ph)
		hips_yaw = 0.4 * sin(ph * 0.5)
	p.hips_rot = Quaternion.from_euler(Vector3(0.0, hips_yaw, hips_roll))
	p.hips.x = 0.03 * sin(ph) * moving
	p.hips.y = g["bob"] * absf(cos(ph)) * moving
	p.spine = Vector3(lean, -hips_yaw * 1.5, -hips_roll * 1.2)
	if state == Zombie.State.DANCE:
		p.spine = Vector3(0.1 * sin(ph * 2.0), -hips_yaw, -hips_roll)
	p.neck = Vector3(head_pitch * 0.4 - lean * 0.4, 0.0, head_roll * 0.4)
	p.head = Vector3(head_pitch * 0.6 - lean * 0.3, 0.2 * sin(_t * 0.5 + _seed), head_roll)
	if state == Zombie.State.STAGGER:
		p.head = Vector3(-0.3, sin(_t * 15.0) * 0.3, sin(_t * 13.0) * 0.4)
	# --- legs ---
	var amp_l := amp
	var amp_r := amp * (1.0 - _limp)
	if state == Zombie.State.LEAP or state == Zombie.State.DROP:
		_leg(p, 1, 0.9, 1.3, 0.35, 0.5)
		_leg(p, -1, -0.5, 0.2, 0.35, 0.4)
	elif state == Zombie.State.LATCHED:
		_leg(p, 1, 0.9, 1.0, 0.25, 0.4)
		_leg(p, -1, 0.9, 1.0, 0.25, 0.4)
	elif state == Zombie.State.STAGGER:
		_leg(p, 1, -0.15 + 0.2 * sin(_t * 9.0), 0.4, 0.15, 0.3)
		_leg(p, -1, 0.2 - 0.2 * sin(_t * 9.0), 0.5, 0.15, 0.3)
	elif crouch > 0.01 and amp < 0.05: # standing crouch (windups)
		_leg(p, 1, 0.6 * crouch, 1.5 * crouch, 0.17, 0.0)
		_leg(p, -1, 0.5 * crouch, 1.4 * crouch, 0.17, 0.0)
	else:
		_leg_cycle(p, 1, ph, amp_l, knee, crouch, kdrag)
		_leg_cycle(p, -1, ph + PI, amp_r, knee, crouch, _limp * 0.6)
	# --- arms ---
	_arms(p, state, reach, spread)


## One leg from a swing angle (forward positive) and a knee bend, both in the hips' frame.
func _leg(p: Pose, side: int, swing: float, bend: float, splay: float, _unused: float) -> void:
	var dt := Vector3(side * splay, -cos(swing), sin(swing)).normalized()
	var ds := Vector3(side * splay * 0.5, -cos(swing - bend), sin(swing - bend)).normalized()
	if side > 0:
		p.thigh_l = dt
		p.shin_l = ds
	else:
		p.thigh_r = dt
		p.shin_r = ds


func _leg_cycle(p: Pose, side: int, ph: float, amp: float, knee: float, crouch: float, drag: float) -> void:
	var swing := amp * sin(ph) + crouch * 0.35
	var bend := crouch * 0.9 + knee * maxf(0.0, cos(ph)) * clampf(amp / 0.35, 0.0, 1.0) + 0.06
	bend += drag * maxf(0.0, 1.0 - absf(sin(ph)) * 2.0)
	_leg(p, side, swing, bend, 0.07, 0.0)


func _arms(p: Pose, state: int, reach: float, spread: float) -> void:
	var wob := sin(_t * 2.3 + _seed)
	var wob2 := sin(_t * 1.7 + _seed * 3.0)
	var forward_l := Vector3(0.18, -0.12 + 0.08 * wob, 0.97)
	var forward_r := Vector3(-0.18, -0.12 + 0.08 * wob2, 0.97)
	var hang_l := Vector3(spread, -1.0, 0.15 + 0.15 * sin(_phase))
	var hang_r := Vector3(-spread, -1.0, 0.15 - 0.15 * sin(_phase))
	var a_l := hang_l
	var a_r := hang_r
	var f_up := 0.3
	var r := clampf(reach, 0.0, 1.0)
	if reach < 0.0: # flung back
		a_l = Vector3(spread, -0.7, -0.7 * -reach * 2.0).normalized()
		a_r = Vector3(-spread, -0.7, -0.7 * -reach * 2.0).normalized()
		f_up = -0.1
	else:
		a_l = hang_l.lerp(forward_l, r).normalized()
		a_r = hang_r.lerp(forward_r, r).normalized()
	match state:
		Zombie.State.LEAP, Zombie.State.DROP:
			a_l = Vector3(0.12, 0.05, 1.0).normalized()
			a_r = Vector3(-0.12, 0.05, 1.0).normalized()
			f_up = 0.0
		Zombie.State.LATCHED:
			a_l = Vector3(0.45, 0.15, 0.9).normalized()
			a_r = Vector3(-0.45, 0.15, 0.9).normalized()
			f_up = 0.5
		Zombie.State.DANCE:
			var s := sin(_t * 9.0)
			a_l = Vector3(0.5, 0.8 + 0.2 * s, 0.1).normalized()
			a_r = Vector3(-0.5, 0.8 - 0.2 * s, 0.1).normalized()
			f_up = 0.6 * s
		Zombie.State.STAGGER:
			var s := sin(_t * 14.0)
			a_l = Vector3(0.7, 0.4 + 0.5 * s, 0.35).normalized()
			a_r = Vector3(-0.7, 0.4 - 0.5 * s, 0.35).normalized()
			f_up = 0.2
		Zombie.State.IDLE, Zombie.State.BARRICADE, Zombie.State.ATTACK:
			pass
	if _attack_t > 0.0: # overhead haul, then a smash down
		var u := 1.0 - _attack_t / 0.55
		var raise := Vector3(0.2, 0.95, 0.15).normalized()
		var smash := Vector3(0.1, -0.6, 0.8).normalized()
		var k := smoothstep(0.35, 0.7, u)
		var cur_l := raise.lerp(smash, k).normalized()
		var windup := smoothstep(0.0, 0.35, u)
		a_l = a_l.lerp(cur_l, windup).normalized()
		a_r = a_r.lerp(Vector3(-cur_l.x, cur_l.y, cur_l.z), windup).normalized()
		f_up = 0.2 * (1.0 - k)
	p.arm_l = a_l
	p.arm_r = a_r
	p.fore_l = (a_l + Vector3(-0.05, f_up, 0.15 * r)).normalized()
	p.fore_r = (a_r + Vector3(0.05, f_up, 0.15 * r)).normalized()


# --- writing the pose into the skeleton ---------------------------------------------------------------

func _set_rot(key: String, q: Quaternion, w: float) -> void:
	var i: int = _b[key]
	skeleton.set_bone_pose_rotation(i, _snap[i].slerp(q, w) if w < 1.0 else q)


func _write(p: Pose, w: float) -> void:
	var hq := p.hips_rot
	_set_rot("hips", hq, w)
	var sq := Quaternion.from_euler(p.spine / 3.0)
	_set_rot("spine", sq, w)
	_set_rot("spine1", sq, w)
	_set_rot("spine2", sq, w)
	_set_rot("neck", Quaternion.from_euler(p.neck), w)
	_set_rot("head", Quaternion.from_euler(p.head), w)
	var qa_l := _aim(_ax_arm_l, p.arm_l)
	var qa_r := _aim(_ax_arm_r, p.arm_r)
	_set_rot("arm_l", qa_l, w)
	_set_rot("fore_l", _aim(_ax_fore_l, qa_l.inverse() * p.fore_l), w)
	_set_rot("arm_r", qa_r, w)
	_set_rot("fore_r", _aim(_ax_fore_r, qa_r.inverse() * p.fore_r), w)
	var qt_l := _aim(_ax_thigh_l, p.thigh_l)
	var qt_r := _aim(_ax_thigh_r, p.thigh_r)
	var qs_l := _aim(_ax_shin_l, qt_l.inverse() * p.shin_l)
	var qs_r := _aim(_ax_shin_r, qt_r.inverse() * p.shin_r)
	_set_rot("thigh_l", qt_l, w)
	_set_rot("shin_l", qs_l, w)
	_set_rot("thigh_r", qt_r, w)
	_set_rot("shin_r", qs_r, w)
	# feet stay roughly flat whatever the legs do
	var flat := Quaternion.from_euler(Vector3(0.1, 0.0, 0.0))
	_set_rot("foot_l", (hq * qt_l * qs_l).inverse() * flat, w)
	_set_rot("foot_r", (hq * qt_r * qs_r).inverse() * flat, w)
	# hips height: plant the lower foot on the ground (or hang in the air for a leap)
	var hy: float
	if p.plant:
		var fl: float = (hq * (Vector3(0.095, -0.03, 0.01) + p.thigh_l * 0.42 + p.shin_l * 0.42)).y
		var fr: float = (hq * (Vector3(-0.095, -0.03, 0.01) + p.thigh_r * 0.42 + p.shin_r * 0.42)).y
		hy = SOLE_Y + SOLE - minf(fl, fr) + p.hips.y
	else:
		hy = _hips_rest.y + p.lift + p.hips.y
	var target := Vector3(_hips_rest.x + p.hips.x, hy, _hips_rest.z + p.hips.z)
	var hi: int = _b["hips"]
	skeleton.set_bone_pose_position(hi, _snap_hips.lerp(target, w) if w < 1.0 else target)


static func _aim(axis: Vector3, dir: Vector3) -> Quaternion:
	var d := dir.normalized()
	if axis.dot(d) < -0.9995: # exactly backwards: any half turn will do
		return Quaternion(Vector3.UP, PI)
	return Quaternion(axis, d)


# --- ragdoll -----------------------------------------------------------------------------------------

func _ensure_bodies() -> void:
	if _sim != null:
		return
	_sim = PhysicalBoneSimulator3D.new()
	skeleton.add_child(_sim)
	for def in PHYS:
		var bi := skeleton.find_bone(def["bone"])
		var ti := skeleton.find_bone(def["to"])
		var reach := skeleton.get_bone_global_rest(ti).origin - skeleton.get_bone_global_rest(bi).origin
		var length := reach.length() * float(def["ext"] if def["ext"] > 0.0 else 1.0)
		var u := reach.normalized()
		var pb := PhysicalBone3D.new()
		_sim.add_child(pb)
		pb.bone_name = def["bone"]
		pb.mass = def["mass"]
		pb.gravity_scale = GameConfig.GRAVITY / 9.8
		pb.linear_damp = 0.08
		pb.angular_damp = 1.6
		pb.friction = 0.9
		pb.collision_layer = 0
		pb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = def["r"]
		shape.height = maxf(length + def["r"], 2.0 * def["r"] + 0.001)
		cs.shape = shape
		pb.add_child(cs)
		var body_xf := Transform3D(Basis(Quaternion(Vector3.UP, u)), u * length * 0.5)
		pb.body_offset = body_xf
		if def.has("swing"):
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			# the joint sits at the bone's own origin and its twist axis (X) runs along the limb
			pb.joint_offset = body_xf.affine_inverse() * Transform3D(Basis(Quaternion(Vector3.RIGHT, u)), Vector3.ZERO)
			pb.set("joint_constraints/swing_span", rad_to_deg(float(def["swing"]))) # these two properties are in degrees
			pb.set("joint_constraints/twist_span", rad_to_deg(float(def["twist"])))
		_pbs.append(pb)
	for a in _pbs: # a body never fights its own limbs
		for c in _pbs:
			if a != c:
				a.add_collision_exception_with(c)


## Lose control: from now on only physics moves the limbs. tether: the zombie's gameplay body, which the ragdoll
## is gently pulled back towards so the visible body and the hit shape stay together.
func start_ragdoll(velocity: Vector3, tether: Node3D = null, inherit: ZombieRig = null) -> void:
	if _ragdolling:
		return
	_ensure_bodies()
	_tether = tether
	_ragdolling = true
	_blend = 1.0
	skeleton.force_update_all_bone_transforms()
	for pb in _pbs:
		pb.collision_layer = GameConfig.L_RAGDOLLS
		pb.collision_mask = GameConfig.MASK_ZOMBIE_RAGDOLL
	_sim.physical_bones_start_simulation()
	var extra := _kick if _kick_t > 0.0 else Vector3.ZERO
	_kick_t = 0.0
	# Whatever tripped it caught the feet: the legs keep little of the momentum and the upper body pitches over them.
	# Without this, straight legs under a hip are an upright pole that can stay balanced for seconds.
	var flat := Vector3(velocity.x + extra.x, 0.0, velocity.z + extra.z)
	var lean_dir := flat.normalized() if flat.length() > 0.5 else Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
	var tip := Vector3.UP.cross(lean_dir) * clampf(flat.length() * 0.8 + 1.5, 1.5, 5.0)
	for i in _pbs.size():
		var leg: bool = String(PHYS[i]["bone"]).contains("Leg")
		var v := velocity * (0.35 if leg else 1.0) + extra
		var av := Vector3(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0), randf_range(-3.0, 3.0)) * clampf(v.length() / 6.0, 0.4, 2.0)
		if i < 3:
			av += tip # hips, chest, head
		elif leg:
			av += Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
		if inherit != null and inherit._ragdolling and i < inherit._pbs.size():
			v += inherit._pbs[i].linear_velocity
			av = inherit._pbs[i].angular_velocity
		_pbs[i].linear_velocity = v + Vector3(randf_range(-0.5, 0.5), randf_range(0.0, 0.6), randf_range(-0.5, 0.5))
		_pbs[i].angular_velocity = av


## Get up: remember how the ragdoll ended and blend from that into the animated pose.
func end_ragdoll() -> void:
	if not _ragdolling:
		return
	var rp := _read_ragdoll_pose()
	_snap = rp["rots"]
	_snap_hips = rp["hips"]
	_ragdolling = false
	_rising = GameConfig.GETUP_TIME
	_tether = null
	_sim.physical_bones_stop_simulation()
	for pb in _pbs:
		pb.collision_layer = 0
		pb.collision_mask = 0
	_blend = 0.0


## A shove or blast that arrives around the moment the zombie goes limp (or just after): add it to the ragdoll.
func kick(v: Vector3) -> void:
	if _ragdolling:
		for pb in _pbs:
			pb.apply_central_impulse(v * pb.mass)
	else:
		_kick = v
		_kick_t = 0.4


func _physics_process(delta: float) -> void:
	_kick_t = maxf(_kick_t - delta, 0.0)
	if not _ragdolling or _tether == null or not is_instance_valid(_tether):
		return
	var hips := _pbs[0]
	var d := _tether.global_position + Vector3(0.0, 0.3, 0.0) - hips.global_position
	d.y = 0.0
	var over := d.length() - 0.35
	if over > 0.0:
		hips.apply_central_impulse(d.normalized() * minf(over * 20.0, 16.0) * hips.mass * delta)


## Local rotation of every bone plus the hips' position, as the ragdoll has them right now. The skeleton's own pose
## getters keep reporting the animated pose while physics drives the bones, so this works it out from the bodies:
## each body's transform gives its bone's transform, and bones without a body (spine, neck, hands...) keep their
## own local pose and ride along with their parent.
func _read_ragdoll_pose() -> Dictionary:
	var n := skeleton.get_bone_count()
	var inv := skeleton.global_transform.affine_inverse()
	var body_of := {}
	for pb in _pbs:
		body_of[skeleton.find_bone(pb.bone_name)] = pb
	var globals: Array[Transform3D] = []
	globals.resize(n)
	var rots: Array[Quaternion] = []
	rots.resize(n)
	var hips := Vector3.ZERO
	for i in n:
		var parent := skeleton.get_bone_parent(i)
		var parent_g := globals[parent] if parent >= 0 else Transform3D.IDENTITY
		if body_of.has(i):
			var pb: PhysicalBone3D = body_of[i]
			var g := inv * pb.global_transform * pb.body_offset.affine_inverse()
			g.basis = g.basis.orthonormalized()
			globals[i] = g
			rots[i] = (parent_g.basis.inverse() * g.basis).get_rotation_quaternion()
			if parent < 0:
				hips = g.origin
		else:
			rots[i] = skeleton.get_bone_pose_rotation(i)
			globals[i] = parent_g * Transform3D(Basis(rots[i]), skeleton.get_bone_pose_position(i))
			if parent < 0:
				hips = skeleton.get_bone_pose_position(i)
	return {"rots": rots, "hips": hips}


## The skeleton as it is right now, e.g. to carry on as a free-standing corpse once the zombie node is gone.
func copy_pose_from(other: ZombieRig) -> void:
	var rots: Array[Quaternion] = []
	var hips: Vector3
	if other._ragdolling:
		var rp := other._read_ragdoll_pose()
		rots = rp["rots"]
		hips = rp["hips"]
	else:
		for i in other.skeleton.get_bone_count():
			rots.append(other.skeleton.get_bone_pose_rotation(i))
		hips = other.skeleton.get_bone_pose_position(other._b["hips"])
	for i in skeleton.get_bone_count():
		skeleton.set_bone_pose_rotation(i, rots[i])
	skeleton.set_bone_pose_position(_b["hips"], hips)
	skeleton.force_update_all_bone_transforms()


# --- corpses -----------------------------------------------------------------------------------------

## A dead zombie: a free-standing ragdoll that flops for a few seconds and sinks away. If the zombie's own rig
## is still around it carries on from that pose and momentum.
static func spawn_corpse(parent: Node3D, zombie_kind: int, pos: Vector3, yaw: float, velocity: Vector3, from: ZombieRig) -> ZombieRig:
	var r := ZombieRig.new()
	r.name = "Corpse"
	r.corpse = true
	parent.add_child(r)
	var st := Zombie.style(zombie_kind)
	r.build(st)
	r.scale = Vector3.ONE * float(st["scale"])
	r.global_position = pos
	r.rotation.y = yaw
	if from != null and is_instance_valid(from) and from.skeleton != null:
		r.copy_pose_from(from)
	else:
		r._compose(Zombie.State.IDLE, 0.0, false, GAIT[zombie_kind])
		r._write(r._pose, 1.0)
		r.skeleton.force_update_all_bone_transforms()
	r.start_ragdoll(velocity, null, from)
	return r


func _process(delta: float) -> void:
	if not corpse:
		return
	_life -= delta
	if _life <= 0.0 and not _retiring:
		retire()


## Corpse clean-up: stop colliding, drop through the floor and go. Called on timeout or when too many bodies exist.
func retire() -> void:
	if _retiring:
		return
	_retiring = true
	for pb in _pbs:
		pb.collision_layer = 0
		pb.collision_mask = 0
	get_tree().create_timer(0.9).timeout.connect(queue_free)


## A colour wash over the whole body for a while (bleeding red, frozen blue).
func set_tint(c: Color, seconds: float) -> void:
	_tint = c
	_tint_t = seconds
