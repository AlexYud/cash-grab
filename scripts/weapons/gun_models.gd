class_name GunModels
extends RefCounted
## Box-built weapon models, one per weapon index (the order of PlayerWeapons.list). Used for the first-person view
## and for the preview on the reward cards. Every model points down -Z with the grip near the origin and carries a
## "muzzle" meta (the tip, where flashes and tracers start).

const DARK := Color(0.14, 0.14, 0.16)
const WOOD := Color(0.36, 0.22, 0.12)
const STEEL := Color(0.72, 0.74, 0.78)
const SKIN := Color(0.93, 0.76, 0.62)


static func build(idx: int, with_hand: bool = true) -> Node3D:
	var g := Node3D.new()
	var muzzle := Vector3(0, 0, -0.3)
	match idx:
		0:
			g.name = "Pistol"
			_box(g, Vector3(0.05, 0.08, 0.22), Vector3(0, 0, -0.15), DARK)
			_box(g, Vector3(0.045, 0.11, 0.06), Vector3(0, -0.085, -0.07), DARK)
			_hand(g, Vector3(0.08, 0.08, 0.1), Vector3(0, -0.1, -0.06), with_hand)
			muzzle = Vector3(0, 0.02, -0.27)
		1:
			g.name = "Shotgun"
			_box(g, Vector3(0.045, 0.045, 0.62), Vector3(0, 0.02, -0.3), DARK)
			_box(g, Vector3(0.06, 0.09, 0.3), Vector3(0, -0.03, 0.06), WOOD)
			_box(g, Vector3(0.07, 0.05, 0.17), Vector3(0, -0.03, -0.3), WOOD)
			_hand(g, Vector3(0.08, 0.08, 0.09), Vector3(0, -0.04, -0.28), with_hand)
			muzzle = Vector3(0, 0.02, -0.63)
		2:
			g.name = "YankGun" # a tube with a big rubber plunger on the end
			_box(g, Vector3(0.07, 0.07, 0.42), Vector3(0, 0.0, -0.2), Color(0.1, 0.5, 0.55))
			_box(g, Vector3(0.05, 0.1, 0.1), Vector3(0, -0.08, -0.06), DARK)
			_box(g, Vector3(0.16, 0.16, 0.06), Vector3(0, 0.0, -0.44), Color(0.85, 0.15, 0.12))
			_hand(g, Vector3(0.08, 0.08, 0.09), Vector3(0, -0.06, -0.08), with_hand)
			muzzle = Vector3(0, 0.0, -0.5)
		3:
			g.name = "DiscoBlaster" # chunky purple blaster with a mirror ball on top
			_box(g, Vector3(0.13, 0.11, 0.34), Vector3(0, 0.0, -0.18), Color(0.55, 0.2, 0.75))
			_box(g, Vector3(0.1, 0.1, 0.1), Vector3(0, 0.1, -0.2), Color(0.85, 0.88, 0.95))
			_box(g, Vector3(0.05, 0.1, 0.07), Vector3(0, -0.09, -0.06), DARK)
			_hand(g, Vector3(0.08, 0.08, 0.09), Vector3(0, -0.06, -0.08), with_hand)
			muzzle = Vector3(0, 0.0, -0.37)
		4:
			g.name = "TeslaGun" # copper coil on a handle, glowing tip
			_box(g, Vector3(0.09, 0.09, 0.32), Vector3(0, 0.0, -0.16), Color(0.75, 0.45, 0.2))
			_box(g, Vector3(0.14, 0.14, 0.05), Vector3(0, 0.0, -0.3), Color(0.7, 0.4, 0.15))
			_box(g, Vector3(0.14, 0.14, 0.05), Vector3(0, 0.0, -0.22), Color(0.7, 0.4, 0.15))
			_box(g, Vector3(0.06, 0.06, 0.08), Vector3(0, 0.0, -0.4), Color(0.5, 0.85, 1.0))
			_box(g, Vector3(0.05, 0.1, 0.07), Vector3(0, -0.09, -0.06), DARK)
			_hand(g, Vector3(0.08, 0.08, 0.09), Vector3(0, -0.06, -0.08), with_hand)
			muzzle = Vector3(0, 0.0, -0.45)
		5:
			g.name = "BoingGun" # a stubby pink cannon with a spring on the front
			_box(g, Vector3(0.14, 0.14, 0.28), Vector3(0, 0.0, -0.14), Color(0.95, 0.45, 0.7))
			_box(g, Vector3(0.07, 0.07, 0.16), Vector3(0, 0.0, -0.35), Color(0.8, 0.8, 0.85))
			_box(g, Vector3(0.12, 0.12, 0.04), Vector3(0, 0.0, -0.45), Color(0.95, 0.85, 0.2))
			_box(g, Vector3(0.05, 0.1, 0.07), Vector3(0, -0.1, -0.05), DARK)
			_hand(g, Vector3(0.08, 0.08, 0.09), Vector3(0, -0.07, -0.07), with_hand)
			muzzle = Vector3(0, 0.0, -0.48)
		6:
			g.name = "AssaultRifle"
			_box(g, Vector3(0.06, 0.09, 0.5), Vector3(0, 0.0, -0.26), Color(0.2, 0.22, 0.2))
			_box(g, Vector3(0.05, 0.11, 0.2), Vector3(0, -0.02, 0.1), Color(0.16, 0.16, 0.14))
			_box(g, Vector3(0.04, 0.17, 0.07), Vector3(0, -0.13, -0.2), DARK)
			_box(g, Vector3(0.035, 0.035, 0.22), Vector3(0, 0.01, -0.64), DARK)
			_box(g, Vector3(0.025, 0.05, 0.07), Vector3(0, 0.07, -0.3), DARK)
			_box(g, Vector3(0.045, 0.1, 0.06), Vector3(0, -0.09, -0.04), DARK)
			_hand(g, Vector3(0.08, 0.08, 0.09), Vector3(0, -0.06, -0.38), with_hand)
			muzzle = Vector3(0, 0.01, -0.76)
		7:
			g.name = "SniperRifle"
			_box(g, Vector3(0.035, 0.035, 0.95), Vector3(0, 0.02, -0.5), DARK)
			_box(g, Vector3(0.06, 0.1, 0.4), Vector3(0, -0.02, -0.02), WOOD)
			_box(g, Vector3(0.045, 0.12, 0.18), Vector3(0, -0.03, 0.2), WOOD)
			_box(g, Vector3(0.05, 0.05, 0.3), Vector3(0, 0.1, -0.2), Color(0.06, 0.06, 0.07))
			_box(g, Vector3(0.056, 0.056, 0.03), Vector3(0, 0.1, -0.36), Color(0.45, 0.8, 1.0))
			_box(g, Vector3(0.04, 0.1, 0.07), Vector3(0, -0.1, -0.05), DARK)
			_hand(g, Vector3(0.08, 0.08, 0.09), Vector3(0, -0.05, -0.32), with_hand)
			muzzle = Vector3(0, 0.02, -1.0)
		8:
			g.name = "BaseballBat"
			_box(g, Vector3(0.036, 0.036, 0.3), Vector3(0, 0, -0.08), Color(0.1, 0.1, 0.12))
			_box(g, Vector3(0.05, 0.05, 0.3), Vector3(0, 0, -0.4), Color(0.78, 0.6, 0.35))
			_box(g, Vector3(0.075, 0.075, 0.34), Vector3(0, 0, -0.7), Color(0.78, 0.6, 0.35))
			_box(g, Vector3(0.078, 0.078, 0.02), Vector3(0, 0, -0.88), Color(0.6, 0.45, 0.25))
			_hand(g, Vector3(0.08, 0.08, 0.1), Vector3(0, 0, -0.02), with_hand)
			muzzle = Vector3(0, 0, -0.85)
			g.rotation_degrees = Vector3(28.0, 0.0, 0.0)
		9:
			g.name = "Katana"
			_box(g, Vector3(0.03, 0.03, 0.22), Vector3(0, 0, -0.06), Color(0.1, 0.1, 0.14))
			_box(g, Vector3(0.1, 0.012, 0.04), Vector3(0, 0, -0.18), Color(0.85, 0.7, 0.25))
			_box(g, Vector3(0.012, 0.05, 0.72), Vector3(0, 0.0, -0.56), STEEL)
			_box(g, Vector3(0.014, 0.012, 0.72), Vector3(0, 0.025, -0.56), Color(0.95, 0.96, 1.0))
			_hand(g, Vector3(0.08, 0.08, 0.1), Vector3(0, 0, -0.04), with_hand)
			muzzle = Vector3(0, 0, -0.92)
			g.rotation_degrees = Vector3(24.0, 0.0, 0.0)
		10:
			g.name = "Axe"
			_box(g, Vector3(0.04, 0.04, 0.78), Vector3(0, 0, -0.32), WOOD)
			_box(g, Vector3(0.035, 0.2, 0.15), Vector3(0, 0.0, -0.66), Color(0.5, 0.52, 0.56))
			_box(g, Vector3(0.02, 0.26, 0.04), Vector3(0, 0.0, -0.76), Color(0.88, 0.9, 0.95))
			_hand(g, Vector3(0.08, 0.08, 0.1), Vector3(0, 0, -0.02), with_hand)
			muzzle = Vector3(0, 0.0, -0.78)
			g.rotation_degrees = Vector3(30.0, 0.0, 0.0)
	g.set_meta("muzzle", muzzle)
	return g


static func _hand(parent: Node3D, size: Vector3, pos: Vector3, with_hand: bool) -> void:
	if with_hand:
		_box(parent, size, pos, SKIN)


static func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
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
