extends Node
## Generates every .tscn in the project (player, zombie, barricade, barrel, saloon level, main) with the engine's
## own PackedScene serializer, so the files are valid and fully editable in the editor afterwards.
## Run once; re-running overwrites manual scene edits:
##   godot --headless --path . res://tools/build_scenes.tscn
## (run as a scene, not with --script: autoload names are not available to --script runs)

const L_WORLD := 1
const L_BARRICADES := 8
const L_PLAYER_WALL := 128
const WOOD := Color(0.5, 0.35, 0.2)
const DARK_WOOD := Color(0.3, 0.19, 0.11)
const WALL := Color(0.62, 0.5, 0.36)
const DIRT := Color(0.46, 0.38, 0.27)
const FLOOR := Color(0.42, 0.28, 0.16)

var _root: Node
var _mats := {}
var _rng := RandomNumberGenerator.new()
var _failures := 0


## Runs as a scene so the autoloads (Net, Fx, ...) exist: the game scripts cannot compile without them.
func _ready() -> void:
	_rng.seed = 7
	DirAccess.make_dir_recursive_absolute("res://scenes/world")
	DirAccess.make_dir_recursive_absolute("res://scenes/player")
	DirAccess.make_dir_recursive_absolute("res://scenes/enemy")
	_build_barricade()
	_build_barrel()
	_build_player()
	_build_zombie()
	_build_saloon()
	_build_main()
	print("build_scenes: done, %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- helpers ----------------------------------------------------------------------------------------------

func _script(path: String) -> Script:
	var s := load(path) as Script
	if s == null:
		push_error("build_scenes: cannot load script " + path)
		_failures += 1
	return s


func _add(parent: Node, child: Node, nm: String) -> Node:
	child.name = nm
	parent.add_child(child)
	child.owner = _root
	return child


func _save(root: Node, path: String) -> void:
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		err = ResourceSaver.save(ps, path)
	print("  %s -> %s" % [path, "OK" if err == OK else "ERROR %d" % err])
	root.free()


func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.92
		_mats[key] = m
	return _mats[key]


func _mesh_box(parent: Node, nm: String, pos: Vector3, size: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	_add(parent, mi, nm)
	mi.position = pos
	return mi


func _solid_box(parent: Node, nm: String, pos: Vector3, size: Vector3, c: Color) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = L_WORLD
	sb.collision_mask = 0
	_add(parent, sb, nm)
	sb.position = pos
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	_add(sb, cs, "Shape")
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	_add(sb, mi, "Mesh")
	return sb


func _solid_cyl(parent: Node, nm: String, pos: Vector3, radius: float, height: float, c: Color) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = L_WORLD
	sb.collision_mask = 0
	_add(parent, sb, nm)
	sb.position = pos
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	cs.shape = cyl
	_add(sb, cs, "Shape")
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = _mat(c)
	_add(sb, mi, "Mesh")
	return sb


func _marker(parent: Node, nm: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	_add(parent, m, nm)
	m.position = pos
	return m


## MultiplayerSynchronizer replicating plain script variables of its parent, owner -> everyone, unreliable.
func _sync(parent: Node, nm: String, props: Array, interval: float) -> MultiplayerSynchronizer:
	var cfg := SceneReplicationConfig.new()
	for p in props:
		var path := NodePath(".:" + p)
		cfg.add_property(path)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		cfg.property_set_spawn(path, true)
	var s := MultiplayerSynchronizer.new()
	s.replication_config = cfg
	s.replication_interval = interval
	_add(parent, s, nm)
	return s


# --- barricade -----------------------------------------------------------------------------------------------

func _build_barricade() -> void:
	var root := Node3D.new()
	root.set_script(_script("res://scripts/world/barricade.gd"))
	root.name = "Barricade"
	_root = root
	var planks := Node3D.new()
	_add(root, planks, "Planks")
	for i in 5:
		var tint := _rng.randf_range(-0.06, 0.06)
		var mi := _mesh_box(planks, "P%d" % i, Vector3(_rng.randf_range(-0.06, 0.06), 0.35 + i * 0.5, 0.0), Vector3(3.3, 0.22, 0.08), WOOD.lightened(tint) if tint > 0.0 else WOOD.darkened(-tint))
		mi.rotation.z = deg_to_rad(_rng.randf_range(-3.5, 3.5))
	var blocker := StaticBody3D.new()
	blocker.collision_layer = L_BARRICADES
	blocker.collision_mask = 0
	_add(root, blocker, "Blocker")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(3.1, 2.7, 0.3)
	cs.shape = bs
	_add(blocker, cs, "Shape")
	cs.position = Vector3(0, 1.35, 0)
	var slots := Node3D.new()
	_add(root, slots, "Slots")
	var xs := [-1.1, -0.37, 0.37, 1.1]
	for i in 4:
		_marker(slots, "S%d" % i, Vector3(xs[i], 0.0, 1.2))
	# invisible wall that only players collide with: stays up even when every board is gone, so nobody walks out
	var pw := StaticBody3D.new()
	pw.collision_layer = L_PLAYER_WALL
	pw.collision_mask = 0
	_add(root, pw, "PlayerWall")
	var pws := CollisionShape3D.new()
	var pwb := BoxShape3D.new()
	pwb.size = Vector3(3.4, 4.0, 0.5)
	pws.shape = pwb
	_add(pw, pws, "Shape")
	pws.position = Vector3(0, 2.0, 0)
	_sync(root, "Sync", ["boards", "repair_progress"], 0.1)
	_save(root, "res://scenes/world/barricade.tscn")


# --- explosive barrel -----------------------------------------------------------------------------------------

func _build_barrel() -> void:
	var root := StaticBody3D.new()
	root.set_script(_script("res://scripts/world/explosive_barrel.gd"))
	root.name = "Barrel"
	_root = root
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.42
	cyl.height = 1.0
	cs.shape = cyl
	_add(root, cs, "Shape")
	cs.position = Vector3(0, 0.5, 0)
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.4
	cm.bottom_radius = 0.4
	cm.height = 1.0
	body.mesh = cm
	body.material_override = _mat(Color(0.75, 0.14, 0.1))
	_add(root, body, "Mesh")
	body.position = Vector3(0, 0.5, 0)
	for y in [0.2, 0.8]:
		var band := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.415
		bm.bottom_radius = 0.415
		bm.height = 0.1
		band.mesh = bm
		band.material_override = _mat(Color(0.95, 0.8, 0.15))
		_add(root, band, "Band%d" % int(y * 10))
		band.position = Vector3(0, y, 0)
	_sync(root, "Sync", ["alive"], 0.2)
	_save(root, "res://scenes/world/explosive_barrel.tscn")


# --- player ---------------------------------------------------------------------------------------------------

func _build_player() -> void:
	var root := CharacterBody3D.new()
	root.set_script(_script("res://scripts/player/player.gd"))
	root.name = "Player"
	_root = root
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.76
	cs.shape = cap
	_add(root, cs, "Collision")
	cs.position = Vector3(0, 0.88, 0)
	var vis := Node3D.new()
	vis.set_script(_script("res://scripts/characters/puppet.gd"))
	_add(root, vis, "Visual")
	var head := Node3D.new()
	_add(root, head, "Head")
	var cam := Camera3D.new()
	cam.fov = 78.0
	cam.near = 0.05
	_add(head, cam, "Camera3D")
	var weapons := Node.new()
	weapons.set_script(_script("res://scripts/player/player_weapons.gd"))
	_add(root, weapons, "Weapons")
	var tag := Label3D.new()
	tag.text = "Player"
	tag.font_size = 40
	tag.pixel_size = 0.006
	tag.outline_size = 12
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	_add(root, tag, "NameTag")
	tag.position = Vector3(0, 2.15, 0)
	var voice := AudioStreamPlayer3D.new()
	voice.unit_size = 6.0
	voice.max_distance = 30.0
	voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_add(root, voice, "VoiceOut")
	voice.position = Vector3(0, 1.6, 0)
	var line := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.05, 0.05, 1.0)
	line.mesh = lm
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Color(1.0, 0.85, 0.3)
	line.material_override = line_mat
	line.top_level = true
	line.visible = false
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(root, line, "GrabLine")
	_sync(root, "TransformSync", ["sync_pos", "sync_yaw", "sync_pitch", "sync_vel", "sync_flags", "sync_weapon"], 0.033)
	_sync(root, "StateSync", ["hp", "status", "bleed_left", "revive_progress", "grabbed_by", "grabbing", "kills", "hugged", "armor", "boost_left", "second_wind"], 0.1)
	_save(root, "res://scenes/player/player.tscn")


# --- zombie ---------------------------------------------------------------------------------------------------

func _build_zombie() -> void:
	var root := CharacterBody3D.new()
	root.set_script(_script("res://scripts/enemy/zombie.gd"))
	root.name = "Zombie"
	_root = root
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.7
	cs.shape = cap
	_add(root, cs, "Collision")
	cs.position = Vector3(0, 0.85, 0)
	# while a zombie is lying on the floor its hit shape is a low box instead (toggled in zombie.gd)
	var fs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(0.6, 0.4, 1.7)
	fs.shape = fb
	fs.disabled = true
	_add(root, fs, "FallenShape")
	fs.position = Vector3(0, 0.2, 0)
	var vis := Node3D.new()
	vis.set_script(_script("res://scripts/characters/zombie_rig.gd"))
	_add(root, vis, "Visual")
	_add(root, NavigationAgent3D.new(), "Agent")
	_sync(root, "Sync", ["sync_pos", "sync_yaw", "sync_speed", "state", "hp"], 0.05)
	_save(root, "res://scenes/enemy/zombie.tscn")


# --- saloon level -----------------------------------------------------------------------------------------------

func _build_saloon() -> void:
	var root := Node3D.new()
	root.set_script(_script("res://scripts/world/saloon_level.gd"))
	root.name = "Level"
	_root = root

	# NavigationRegion3D: everything under it that has a static collider is baked into the navmesh at runtime.
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.geometry_collision_mask = L_WORLD
	# cell size matches the default navigation map (0.25); agent sizes are whole multiples of the cell
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_height = 2.0
	nm.agent_radius = 0.5
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 45.0
	var nav := NavigationRegion3D.new()
	nav.navigation_mesh = nm
	_add(root, nav, "Nav")

	# ground (street) + perimeter fence
	# the ground runs east far enough to wrap the annex too
	_solid_box(nav, "Ground", Vector3(20, -0.2, 2.0), Vector3(93, 0.4, 49), DIRT)
	_solid_box(nav, "FenceW", Vector3(-26.9, 1.5, 2.0), Vector3(0.8, 3.0, 50), DARK_WOOD)
	_solid_box(nav, "FenceE", Vector3(66.9, 1.5, 2.0), Vector3(0.8, 3.0, 50), DARK_WOOD)
	_solid_box(nav, "FenceN", Vector3(20, 1.5, -22.9), Vector3(94, 3.0, 0.8), DARK_WOOD)
	_solid_box(nav, "FenceS", Vector3(20, 1.5, 26.9), Vector3(94, 3.0, 0.8), DARK_WOOD)

	# walls: interior is x in [-11, 11], z in [-8, 8]; 0.4 thick, 4 high. Doorways are 3 wide.
	var h := 4.0
	_solid_box(nav, "WallN1", Vector3(-3.45, h / 2, -8.2), Vector3(15.9, h, 0.4), WALL)
	_solid_box(nav, "WallN2", Vector3(9.45, h / 2, -8.2), Vector3(3.9, h, 0.4), WALL)
	_solid_box(nav, "LintelN", Vector3(6.0, 3.35, -8.2), Vector3(3.0, 1.3, 0.4), WALL)
	# south wall: two windows (x=0 and x=-7)
	_solid_box(nav, "WallS1a", Vector3(-9.95, h / 2, 8.2), Vector3(2.9, h, 0.4), WALL)
	_solid_box(nav, "WallS1b", Vector3(-3.5, h / 2, 8.2), Vector3(4.0, h, 0.4), WALL)
	_solid_box(nav, "WallS2", Vector3(6.45, h / 2, 8.2), Vector3(9.9, h, 0.4), WALL)
	_solid_box(nav, "LintelS", Vector3(0.0, 3.35, 8.2), Vector3(3.0, 1.3, 0.4), WALL)
	_solid_box(nav, "LintelS2", Vector3(-7.0, 3.35, 8.2), Vector3(3.0, 1.3, 0.4), WALL)
	# west wall: two windows (z=0 and z=-5.5)
	_solid_box(nav, "WallW1a", Vector3(-11.2, h / 2, -7.6), Vector3(0.4, h, 1.2), WALL)
	_solid_box(nav, "WallW1b", Vector3(-11.2, h / 2, -2.75), Vector3(0.4, h, 2.5), WALL)
	_solid_box(nav, "WallW2", Vector3(-11.2, h / 2, 4.75), Vector3(0.4, h, 6.5), WALL)
	_solid_box(nav, "LintelW", Vector3(-11.2, 3.35, 0.0), Vector3(0.4, 1.3, 3.0), WALL)
	_solid_box(nav, "LintelW2", Vector3(-11.2, 3.35, -5.5), Vector3(0.4, 1.3, 3.0), WALL)
	# east wall: the gate doorway into the annex (z in [-1.5, 1.5]); the wall runs the full depth of the annex
	_solid_box(nav, "WallE1", Vector3(11.2, h / 2, -5.45), Vector3(0.4, h, 7.9), WALL)
	_solid_box(nav, "WallE2", Vector3(11.2, h / 2, 5.45), Vector3(0.4, h, 7.9), WALL)
	_solid_box(nav, "LintelE", Vector3(11.2, 3.35, 0.0), Vector3(0.4, 1.3, 3.0), WALL)

	# annex (interior x in [11.4, 35.8], z in [-9, 9]): two more windows, on the north and south walls at x=24
	_solid_box(nav, "AnxN1", Vector3(16.75, h / 2, -9.2), Vector3(11.5, h, 0.4), WALL)
	_solid_box(nav, "AnxN2", Vector3(30.85, h / 2, -9.2), Vector3(10.7, h, 0.4), WALL)
	_solid_box(nav, "AnxLintelN", Vector3(24.0, 3.35, -9.2), Vector3(3.0, 1.3, 0.4), WALL)
	_solid_box(nav, "AnxS1", Vector3(16.75, h / 2, 9.2), Vector3(11.5, h, 0.4), WALL)
	_solid_box(nav, "AnxS2", Vector3(30.85, h / 2, 9.2), Vector3(10.7, h, 0.4), WALL)
	_solid_box(nav, "AnxLintelS", Vector3(24.0, 3.35, 9.2), Vector3(3.0, 1.3, 0.4), WALL)
	# the annex's east wall has a gate doorway too (z in [-1.5, 1.5]) into the hall
	_solid_box(nav, "AnxE1", Vector3(36.0, h / 2, -5.55), Vector3(0.4, h, 8.1), WALL)
	_solid_box(nav, "AnxE2", Vector3(36.0, h / 2, 5.55), Vector3(0.4, h, 8.1), WALL)
	_solid_box(nav, "AnxLintelE", Vector3(36.0, 3.35, 0.0), Vector3(0.4, 1.3, 3.0), WALL)

	# the hall (interior x in [36.2, 60.4], z in [-9, 9]): two more windows on the north and south walls at x=48
	_solid_box(nav, "HallN1", Vector3(41.35, h / 2, -9.2), Vector3(10.3, h, 0.4), WALL)
	_solid_box(nav, "HallN2", Vector3(54.95, h / 2, -9.2), Vector3(10.9, h, 0.4), WALL)
	_solid_box(nav, "HallLintelN", Vector3(48.0, 3.35, -9.2), Vector3(3.0, 1.3, 0.4), WALL)
	_solid_box(nav, "HallS1", Vector3(41.35, h / 2, 9.2), Vector3(10.3, h, 0.4), WALL)
	_solid_box(nav, "HallS2", Vector3(54.95, h / 2, 9.2), Vector3(10.9, h, 0.4), WALL)
	_solid_box(nav, "HallLintelS", Vector3(48.0, 3.35, 9.2), Vector3(3.0, 1.3, 0.4), WALL)
	_solid_box(nav, "HallE", Vector3(60.6, h / 2, 0.0), Vector3(0.4, h, 19.2), WALL)

	# furniture (everything raised is >= 1.05 m so players cannot hop on top and break the navmesh/AI)
	_solid_box(nav, "BarCounter", Vector3(-5.5, 0.55, -4.6), Vector3(8.0, 1.1, 0.9), Color(0.45, 0.14, 0.1))
	_solid_box(nav, "BarShelves", Vector3(-5.5, 1.1, -7.7), Vector3(8.6, 2.2, 0.5), DARK_WOOD)
	_solid_box(nav, "PillarW", Vector3(-4.5, 2.0, 2.0), Vector3(0.6, 4.0, 0.6), DARK_WOOD)
	_solid_box(nav, "PillarE", Vector3(4.5, 2.0, 2.0), Vector3(0.6, 4.0, 0.6), DARK_WOOD)
	_solid_cyl(nav, "Table1", Vector3(-7.0, 0.525, 3.8), 0.8, 1.05, WOOD)
	_solid_cyl(nav, "Table2", Vector3(7.0, 0.525, 4.2), 0.8, 1.05, WOOD)
	_solid_cyl(nav, "Table3", Vector3(7.5, 0.525, -2.0), 0.8, 1.05, WOOD)
	_solid_cyl(nav, "Table4", Vector3(-1.0, 0.525, -1.5), 0.8, 1.05, WOOD)
	_solid_box(nav, "Piano", Vector3(9.8, 0.65, 5.6), Vector3(1.8, 1.3, 0.8), Color(0.12, 0.1, 0.1))
	_solid_box(nav, "Crate1", Vector3(9.9, 0.55, -6.5), Vector3(1.1, 1.1, 1.1), Color(0.55, 0.42, 0.25))
	_solid_box(nav, "Crate2", Vector3(8.7, 0.55, -6.8), Vector3(1.1, 1.1, 1.1), Color(0.5, 0.38, 0.22))
	# health shop cabinet (the Interactable in front of it is added below)
	_solid_box(nav, "BandageCabinet", Vector3(-10.7, 0.6, 6.4), Vector3(0.6, 1.2, 1.2), Color(0.85, 0.85, 0.8))

	# annex furniture: a bigger room with more to hide behind (all >= 1.05 m high, gaps >= 1.5 m for the navmesh)
	_solid_box(nav, "AnxCrateA", Vector3(15.5, 0.55, -5.5), Vector3(1.1, 1.1, 1.1), Color(0.55, 0.42, 0.25))
	_solid_box(nav, "AnxCrateB", Vector3(16.7, 0.55, -5.9), Vector3(1.1, 1.1, 1.1), Color(0.5, 0.38, 0.22))
	_solid_box(nav, "AnxCrateC", Vector3(15.5, 0.55, 5.5), Vector3(1.1, 1.1, 1.1), Color(0.5, 0.38, 0.22))
	_solid_box(nav, "AnxCrateD", Vector3(16.6, 0.55, 6.2), Vector3(1.1, 1.1, 1.1), Color(0.55, 0.42, 0.25))
	_solid_box(nav, "Wagon", Vector3(21.0, 0.65, 4.8), Vector3(4.0, 1.3, 1.5), Color(0.4, 0.28, 0.16))
	_solid_box(nav, "Counter2", Vector3(22.0, 0.55, -5.0), Vector3(5.0, 1.1, 0.9), Color(0.45, 0.14, 0.1))
	_solid_box(nav, "AnxPillarA", Vector3(24.0, 2.0, 0.0), Vector3(0.6, 4.0, 0.6), DARK_WOOD)
	_solid_box(nav, "AnxPillarB", Vector3(30.0, 2.0, -3.5), Vector3(0.6, 4.0, 0.6), DARK_WOOD)
	_solid_box(nav, "AnxPillarC", Vector3(30.0, 2.0, 3.5), Vector3(0.6, 4.0, 0.6), DARK_WOOD)
	_solid_cyl(nav, "AnxTable1", Vector3(28.0, 0.525, 6.0), 0.8, 1.05, WOOD)
	_solid_cyl(nav, "AnxTable2", Vector3(27.5, 0.525, -6.2), 0.8, 1.05, WOOD)
	_solid_cyl(nav, "AnxTable3", Vector3(19.0, 0.525, -0.5), 0.8, 1.05, WOOD)
	_solid_box(nav, "Safe", Vector3(33.0, 0.6, 0.0), Vector3(1.4, 1.2, 2.2), Color(0.2, 0.22, 0.25))
	# medkit cabinet against the annex's east wall (the hall's levers sit on the same wall)
	_solid_box(nav, "MedkitCabinet", Vector3(35.5, 0.7, 6.6), Vector3(0.6, 1.4, 1.2), Color(0.85, 0.85, 0.8))

	# hall furniture: crates, a wagon, counters and pillars to fight around (>= 1.05 m high, gaps >= 1.5 m)
	_solid_box(nav, "HallCrateA", Vector3(41.0, 0.55, -6.0), Vector3(1.1, 1.1, 1.1), Color(0.55, 0.42, 0.25))
	_solid_box(nav, "HallCrateB", Vector3(42.2, 0.55, -6.4), Vector3(1.1, 1.1, 1.1), Color(0.5, 0.38, 0.22))
	_solid_box(nav, "HallCrateC", Vector3(41.5, 0.55, 6.0), Vector3(1.1, 1.1, 1.1), Color(0.5, 0.38, 0.22))
	_solid_box(nav, "HallCrateD", Vector3(42.7, 0.55, 6.5), Vector3(1.1, 1.1, 1.1), Color(0.55, 0.42, 0.25))
	_solid_box(nav, "Wagon2", Vector3(46.0, 0.65, 4.6), Vector3(4.0, 1.3, 1.5), Color(0.4, 0.28, 0.16))
	_solid_box(nav, "Counter3", Vector3(51.0, 0.55, -5.2), Vector3(5.0, 1.1, 0.9), Color(0.45, 0.14, 0.1))
	_solid_box(nav, "HallPillarA", Vector3(48.0, 2.0, 0.0), Vector3(0.6, 4.0, 0.6), DARK_WOOD)
	_solid_box(nav, "HallPillarB", Vector3(54.0, 2.0, -3.5), Vector3(0.6, 4.0, 0.6), DARK_WOOD)
	_solid_box(nav, "HallPillarC", Vector3(54.0, 2.0, 3.5), Vector3(0.6, 4.0, 0.6), DARK_WOOD)
	_solid_cyl(nav, "HallTable1", Vector3(52.0, 0.525, 6.2), 0.8, 1.05, WOOD)
	_solid_cyl(nav, "HallTable2", Vector3(44.5, 0.525, -2.8), 0.8, 1.05, WOOD)
	_solid_cyl(nav, "HallTable3", Vector3(57.0, 0.525, 2.0), 0.8, 1.05, WOOD)
	_solid_box(nav, "Vault", Vector3(57.5, 0.6, 7.0), Vector3(2.2, 1.2, 1.4), Color(0.2, 0.22, 0.25))
	# the mystery box chest against the hall's east wall
	_solid_box(nav, "ChestSolid", Vector3(59.8, 0.5, -5.0), Vector3(0.8, 1.0, 1.5), Color(0.35, 0.22, 0.1))

	# junk on the ground that zombies trip over (not solid: players and bullets ignore it, zombie.gd checks the group)
	var trips := Node3D.new()
	_add(root, trips, "TripSpots")
	var trip_defs := [
		[Vector3(-3.0, 0, 3.5), 0], [Vector3(3.2, 0, -3.3), 1], [Vector3(0.5, 0, 5.5), 2], [Vector3(6.0, 0, 1.0), 0],
		[Vector3(-6.5, 0, -2.0), 1], [Vector3(1.5, 0, -2.5), 2], [Vector3(0.0, 0, 12.0), 0], [Vector3(-14.0, 0, 0.5), 1],
		[Vector3(6.0, 0, -12.5), 2], [Vector3(-6.0, 0, 14.0), 1], [Vector3(8.0, 0, 12.5), 0], [Vector3(-12.5, 0, -4.0), 2],
		[Vector3(17.5, 0, 0.5), 1], [Vector3(22.0, 0, -2.2), 0], [Vector3(26.0, 0, 2.2), 2], [Vector3(31.0, 0, -6.5), 1],
		[Vector3(20.0, 0, 7.5), 0], [Vector3(29.0, 0, 6.5), 2], [Vector3(24.0, 0, -12.0), 2], [Vector3(24.0, 0, 13.0), 0],
		[Vector3(40.0, 0, 0.5), 1], [Vector3(46.0, 0, -1.5), 0], [Vector3(52.0, 0, 0.5), 2], [Vector3(57.0, 0, -1.0), 1],
		[Vector3(48.0, 0, -12.0), 2], [Vector3(48.0, 0, 13.0), 0],
	]
	for i in trip_defs.size():
		var spot := Marker3D.new()
		_add(trips, spot, "T%d" % i)
		spot.position = trip_defs[i][0]
		spot.add_to_group("trip_spots", true)
		match int(trip_defs[i][1]):
			0: # crate
				var c := _mesh_box(spot, "Crate", Vector3(0, 0.15, 0), Vector3(0.55, 0.3, 0.5), Color(0.55, 0.42, 0.25))
				c.rotation.y = i * 0.7
			1: # plank
				var pl := _mesh_box(spot, "Plank", Vector3(0, 0.05, 0), Vector3(1.1, 0.08, 0.22), WOOD)
				pl.rotation.y = i * 1.3
			2: # bottle on its side
				var b := _mesh_box(spot, "Bottle", Vector3(0, 0.06, 0), Vector3(0.35, 0.12, 0.12), Color(0.2, 0.55, 0.3))
				b.rotation.y = i * 0.9

	# non-colliding dressing
	var decor := Node3D.new()
	_add(root, decor, "Decor")
	_mesh_box(decor, "InteriorFloor", Vector3(0, 0.015, 0), Vector3(22.4, 0.03, 16.4), FLOOR)
	_mesh_box(decor, "Roof", Vector3(0, 4.15, 0), Vector3(23.4, 0.3, 17.4), DARK_WOOD)
	_mesh_box(decor, "AnnexFloor", Vector3(23.6, 0.015, 0), Vector3(24.4, 0.03, 18.4), Color(0.36, 0.25, 0.15))
	_mesh_box(decor, "AnnexRoof", Vector3(23.6, 4.15, 0), Vector3(25.6, 0.3, 19.6), DARK_WOOD)
	_mesh_box(decor, "HallFloor", Vector3(48.4, 0.015, 0), Vector3(24.4, 0.03, 18.4), Color(0.3, 0.24, 0.2))
	_mesh_box(decor, "HallRoof", Vector3(48.6, 4.15, 0), Vector3(25.2, 0.3, 19.6), DARK_WOOD)
	var gate_sign := Label3D.new()
	gate_sign.text = "EAST ANNEX\nPULL BOTH LEVERS"
	gate_sign.font_size = 56
	gate_sign.pixel_size = 0.008
	gate_sign.outline_size = 12
	gate_sign.modulate = Color(0.96, 0.73, 0.26)
	_add(decor, gate_sign, "GateSign")
	gate_sign.position = Vector3(10.85, 3.35, 0)
	gate_sign.rotation_degrees = Vector3(0, -90, 0)
	var hall_sign := Label3D.new()
	hall_sign.text = "THE HALL
PULL BOTH LEVERS ($500 each)"
	hall_sign.font_size = 56
	hall_sign.pixel_size = 0.008
	hall_sign.outline_size = 12
	hall_sign.modulate = Color(0.96, 0.73, 0.26)
	_add(decor, hall_sign, "HallSign")
	hall_sign.position = Vector3(35.65, 3.35, 0)
	hall_sign.rotation_degrees = Vector3(0, -90, 0)
	var sign_label := Label3D.new()
	sign_label.text = "SALOON"
	sign_label.font_size = 96
	sign_label.pixel_size = 0.012
	sign_label.outline_size = 16
	sign_label.modulate = Color(0.96, 0.73, 0.26)
	_add(decor, sign_label, "Sign")
	sign_label.position = Vector3(0, 3.5, 8.45)
	for i in 6:
		_mesh_box(decor, "Bottle%d" % i, Vector3(-8.5 + i * 1.25, 1.75, -7.4), Vector3(0.12, 0.35, 0.12), Color(0.2, 0.5 + 0.08 * (i % 3), 0.3, 1.0))

	# lighting
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.45, 0.72)
	sky_mat.sky_horizon_color = Color(0.88, 0.7, 0.52)
	sky_mat.ground_horizon_color = Color(0.7, 0.58, 0.45)
	sky_mat.ground_bottom_color = Color(0.3, 0.25, 0.2)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_add(root, we, "Environment")
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	_add(root, sun, "Sun")
	sun.rotation_degrees = Vector3(-52, -35, 0)
	var lights := Node3D.new()
	_add(root, lights, "Lamps")
	var lamp_pos := [Vector3(-6, 3.4, -2), Vector3(6, 3.4, -2), Vector3(-6, 3.4, 5), Vector3(6, 3.4, 5), Vector3(0, 3.4, 1),
		Vector3(17, 3.4, -3.5), Vector3(17, 3.4, 3.5), Vector3(29, 3.4, -3.5), Vector3(29, 3.4, 3.5), Vector3(23.6, 3.4, 0),
		Vector3(42, 3.4, -3.5), Vector3(42, 3.4, 3.5), Vector3(54, 3.4, -3.5), Vector3(54, 3.4, 3.5), Vector3(48.4, 3.4, 0)]
	for i in lamp_pos.size():
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.5)
		l.light_energy = 1.6
		l.omni_range = 10.0
		_add(lights, l, "Lamp%d" % i)
		l.position = lamp_pos[i]

	# gameplay nodes
	var bars := Node3D.new()
	_add(root, bars, "Barricades")
	var bar_scene: PackedScene = load("res://scenes/world/barricade.tscn")
	# index order matters: it is the entrance number (EnemySpawns/E<i> sits outside window i)
	var bar_defs := [
		["Front", Vector3(0, 0, 8.2), 0.0, 0],
		["Side", Vector3(-11.2, 0, 0.0), -90.0, 0],
		["Back", Vector3(6.0, 0, -8.2), 180.0, 0],
		["West2", Vector3(-11.2, 0, -5.5), -90.0, 0],
		["South2", Vector3(-7.0, 0, 8.2), 0.0, 0],
		["AnnexN", Vector3(24.0, 0, -9.2), 180.0, 1],
		["AnnexS", Vector3(24.0, 0, 9.2), 0.0, 1],
		["HallN", Vector3(48.0, 0, -9.2), 180.0, 2],
		["HallS", Vector3(48.0, 0, 9.2), 0.0, 2],
	]
	for i in bar_defs.size():
		var b: Node3D = bar_scene.instantiate()
		b.name = bar_defs[i][0]
		bars.add_child(b)
		b.owner = root
		b.set("index", i)
		b.set("stage", bar_defs[i][3])
		b.position = bar_defs[i][1]
		b.rotation_degrees = Vector3(0, bar_defs[i][2], 0)
	var barrels := Node3D.new()
	_add(root, barrels, "Barrels")
	var barrel_scene: PackedScene = load("res://scenes/world/explosive_barrel.tscn")
	var barrel_pos := [Vector3(-8.0, 0, 3.2), Vector3(3.5, 0, 6.5), Vector3(14.8, 0, -7.0), Vector3(33.0, 0, 7.0), Vector3(50.5, 0, 7.0)]
	for i in barrel_pos.size():
		var b: Node3D = barrel_scene.instantiate()
		b.name = "Barrel%d" % i
		barrels.add_child(b)
		b.owner = root
		b.set("index", i)
		b.position = barrel_pos[i]
	var ps := Node3D.new()
	_add(root, ps, "PlayerSpawns")
	var spawn_pos := [Vector3(-2, 0.1, 2.0), Vector3(2, 0.1, 2.0), Vector3(-2, 0.1, 4.5), Vector3(2, 0.1, 4.5)]
	for i in spawn_pos.size():
		_marker(ps, "P%d" % i, spawn_pos[i])
	var es := Node3D.new()
	_add(root, es, "EnemySpawns")
	_marker(es, "E0", Vector3(0, 0, 18))
	_marker(es, "E1", Vector3(-21, 0, 0))
	_marker(es, "E2", Vector3(6, 0, -18))
	_marker(es, "E3", Vector3(-21, 0, -5.5))
	_marker(es, "E4", Vector3(-7, 0, 18))
	_marker(es, "E5", Vector3(24, 0, -19))
	_marker(es, "E6", Vector3(24, 0, 19))
	_marker(es, "E7", Vector3(48, 0, -19))
	_marker(es, "E8", Vector3(48, 0, 19))
	_build_annex(root)
	_save(root, "res://scenes/world/saloon.tscn")


## The gate + levers + shops. Not under Nav: the gate must not be baked into the navmesh as a wall.
func _build_annex(root: Node3D) -> void:
	# two gated rooms: the east annex (stage 1, gate in the saloon's east wall) and the hall behind it (stage 2)
	for def in [["Annex", 1, 11.2], ["Annex2", 2, 36.0]]:
		var annex := Node3D.new()
		annex.set_script(_script("res://scripts/world/annex.gd"))
		annex.set("stage", def[1])
		_add(root, annex, def[0])
		var gate := _solid_box(annex, "Gate", Vector3(def[2], 1.4, 0.0), Vector3(0.3, 2.8, 3.2), Color(0.25, 0.25, 0.3))
		for y in [-0.9, 0.0, 0.9]: # iron straps
			_mesh_box(gate, "Strap%d" % int(y * 10), Vector3(0, y, 0), Vector3(0.36, 0.14, 3.0), Color(0.12, 0.12, 0.14))
		_sync(annex, "Sync", ["lever1", "lever2", "latch_left", "door_t", "is_open"], 0.1)

	var its := Node3D.new()
	_add(root, its, "Interactables")
	# levers on the east walls (they face west: local +Z points into the room): the saloon's, then the annex's
	_interactable(its, "Lever1", 0, Vector3(10.93, 0, -4.8), -90.0, 0)
	_interactable(its, "Lever2", 1, Vector3(10.93, 0, 3.8), -90.0, 1)
	_interactable(its, "MysteryBox", 2, Vector3(59.15, 0, -5.0), -90.0, 0) # in the hall
	_interactable(its, "Bandages", 3, Vector3(-10.2, 0, 6.4), 90.0, 0)
	_interactable(its, "Medkit", 4, Vector3(34.9, 0, 6.6), -90.0, 0)
	_interactable(its, "HallLever1", 5, Vector3(35.73, 0, -6.8), -90.0, 0)
	_interactable(its, "HallLever2", 6, Vector3(35.73, 0, 3.4), -90.0, 1)

	# wall vents the crawlers climb out of: local +Z points into the room; meta "stage" says which room must be open
	var vents := Node3D.new()
	_add(root, vents, "Vents")
	var vent_defs := [
		[Vector3(-10.95, 1.2, 3.0), 90.0, 0], [Vector3(1.5, 1.2, -7.95), 0.0, 0], [Vector3(4.0, 1.2, 7.95), 180.0, 0],
		[Vector3(17.0, 1.2, 8.95), 180.0, 1], [Vector3(29.0, 1.2, -8.95), 0.0, 1],
		[Vector3(42.0, 1.2, -8.95), 0.0, 2], [Vector3(55.0, 1.2, 8.95), 180.0, 2], [Vector3(60.35, 1.2, 1.0), -90.0, 2],
	]
	for i in vent_defs.size():
		var m := Marker3D.new()
		_add(vents, m, "Vent%d" % i)
		m.position = vent_defs[i][0]
		m.rotation_degrees = Vector3(0, vent_defs[i][1], 0)
		m.set_meta("stage", vent_defs[i][2])
		_mesh_box(m, "Grate", Vector3(0, 0, -0.03), Vector3(1.0, 0.7, 0.08), Color(0.08, 0.08, 0.1))
		for j in 3:
			_mesh_box(m, "Slat%d" % j, Vector3(0, -0.2 + j * 0.2, 0.02), Vector3(0.9, 0.04, 0.05), Color(0.25, 0.25, 0.3))


## kind: 0 lever, 1 mystery box, 2/3 shops are numbered by `id` here: 0,1 levers, 2 box, 3 bandages, 4 medkit.
func _interactable(parent: Node, nm: String, id: int, pos: Vector3, yaw_deg: float, slot: int) -> void:
	var kind_for := [0, 0, 1, 2, 3, 0, 0]
	var n := Node3D.new()
	n.set_script(_script("res://scripts/world/interactable.gd"))
	_add(parent, n, nm)
	n.position = pos
	n.rotation_degrees = Vector3(0, yaw_deg, 0)
	n.set("kind", kind_for[id])
	n.set("index", id)
	n.set("slot", slot)
	n.set("stage", 2 if id >= 5 else 1)
	var title := ""
	match id:
		0, 1, 5, 6: # wall plate with a handle that swings down when pulled (animated in interactable.gd)
			_mesh_box(n, "Plate", Vector3(0, 1.2, -0.03), Vector3(0.55, 1.0, 0.1), Color(0.2, 0.2, 0.24))
			_mesh_box(n, "Slot", Vector3(0, 1.2, 0.03), Vector3(0.1, 0.8, 0.04), Color(0.05, 0.05, 0.06))
			var pivot := Node3D.new()
			_add(n, pivot, "Pivot")
			pivot.position = Vector3(0, 1.0, 0.1)
			_mesh_box(pivot, "Stick", Vector3(0, 0.32, 0), Vector3(0.07, 0.64, 0.07), Color(0.7, 0.7, 0.72))
			var ball := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.1
			sm.height = 0.2
			ball.mesh = sm
			ball.material_override = _mat(Color(0.85, 0.12, 0.1))
			_add(pivot, ball, "Knob")
			ball.position = Vector3(0, 0.68, 0)
			title = "LEVER $250" if id < 5 else "HALL LEVER $500"
		2: # chest: body + hinged lid + a label that shows what you got
			_mesh_box(n, "Body", Vector3(0, 0.3, -0.6), Vector3(1.4, 0.6, 0.7), Color(0.4, 0.26, 0.12))
			_mesh_box(n, "Band", Vector3(0, 0.3, -0.24), Vector3(1.42, 0.62, 0.04), Color(0.95, 0.8, 0.15))
			var lid := Node3D.new()
			_add(n, lid, "Lid")
			lid.position = Vector3(0, 0.6, -0.95)
			_mesh_box(lid, "LidMesh", Vector3(0, 0.09, 0.35), Vector3(1.4, 0.18, 0.7), Color(0.46, 0.3, 0.14))
			var rev := Label3D.new()
			rev.text = ""
			rev.visible = false
			rev.font_size = 72
			rev.pixel_size = 0.008
			rev.outline_size = 14
			rev.modulate = Color(0.5, 1.0, 0.6)
			rev.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_add(n, rev, "Reveal")
			rev.position = Vector3(0, 1.9, -0.6)
			title = "MYSTERY BOX $400"
		3, 4: # cabinet front with a cross
			var col := Color(0.2, 0.75, 0.3) if id == 3 else Color(0.85, 0.1, 0.1)
			var zf := -0.19 if id == 3 else -0.29
			_mesh_box(n, "CrossH", Vector3(0, 0.8, zf), Vector3(0.5, 0.14, 0.03), col)
			_mesh_box(n, "CrossV", Vector3(0, 0.8, zf), Vector3(0.14, 0.5, 0.03), col)
			title = "BANDAGES $75" if id == 3 else "MEDKIT $250"
	var tag := Label3D.new()
	tag.text = title
	tag.font_size = 48
	tag.pixel_size = 0.007
	tag.outline_size = 10
	tag.modulate = Color(0.96, 0.73, 0.26)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_add(n, tag, "Tag")
	var lever_like := id <= 1 or id >= 5
	tag.position = Vector3(0, 2.15 if lever_like else 1.7, 0.1 if lever_like else -0.2)


# --- main --------------------------------------------------------------------------------------------------------

func _build_main() -> void:
	var root := Node.new()
	root.set_script(_script("res://scripts/main.gd"))
	root.name = "Main"
	_root = root
	var world := Node3D.new()
	_add(root, world, "World")
	var level: Node3D = (load("res://scenes/world/saloon.tscn") as PackedScene).instantiate()
	level.name = "Level"
	world.add_child(level)
	level.owner = root
	_add(world, Node3D.new(), "Players")
	_add(world, Node3D.new(), "Enemies")
	_add(world, Node3D.new(), "Fx")
	var ps := MultiplayerSpawner.new()
	ps.spawn_path = NodePath("../Players")
	_add(world, ps, "PlayerSpawner")
	var es := MultiplayerSpawner.new()
	es.spawn_path = NodePath("../Enemies")
	_add(world, es, "EnemySpawner")
	var wm := Node.new()
	wm.set_script(_script("res://scripts/world/wave_manager.gd"))
	_add(world, wm, "WaveManager")
	_sync(wm, "Sync", ["state", "wave", "enemies_alive", "to_spawn", "break_left", "cash", "ready_ids"], 0.2)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 200.0
	_add(root, cam, "MenuCam")
	cam.position = Vector3(0, 9, 30)
	var ui := CanvasLayer.new()
	ui.layer = 10
	_add(root, ui, "UI")
	_save(root, "res://scenes/main.tscn")
