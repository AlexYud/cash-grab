class_name Ragdoll
extends Node3D
## A short-lived, purely visual ragdoll: a handful of primitive rigid bodies joined with pin joints.
## It is never replicated; each peer spawns its own from a small event (see Fx / Puppet).

var life := 6.0
var _retiring := false


## parts: Array of {name, center: Node3D, size: Vector3, shape: "box"|"sphere", anchor: Vector3 (local to center)}
static func spawn(parent: Node, parts: Array, velocity: Vector3, lifetime: float = 6.0) -> Ragdoll:
	var root := Ragdoll.new()
	root.name = "Ragdoll"
	root.life = lifetime
	parent.add_child(root)
	var bodies := {}
	var anchors := {}
	for p in parts:
		var center: Node3D = p["center"]
		var rb := RigidBody3D.new()
		rb.collision_layer = GameConfig.L_RAGDOLLS
		rb.collision_mask = GameConfig.MASK_RAGDOLL
		rb.mass = 6.0 if p["name"] == &"torso" else 2.0
		rb.gravity_scale = GameConfig.GRAVITY / 9.8
		rb.linear_damp = 0.15
		rb.angular_damp = 1.2
		root.add_child(rb)
		rb.global_transform = center.global_transform
		var cs := CollisionShape3D.new()
		var size: Vector3 = p["size"]
		if p["shape"] == "sphere":
			var ss := SphereShape3D.new()
			ss.radius = size.x * 0.5
			cs.shape = ss
		else:
			var bs := BoxShape3D.new()
			bs.size = size
			cs.shape = bs
		rb.add_child(cs)
		for child in center.get_children():
			if child is MeshInstance3D:
				var mi := MeshInstance3D.new()
				mi.mesh = child.mesh
				mi.material_override = child.material_override
				mi.transform = child.transform
				rb.add_child(mi)
		rb.linear_velocity = velocity + Vector3(randf_range(-1.0, 1.0), randf_range(0.0, 1.5), randf_range(-1.0, 1.0))
		rb.angular_velocity = Vector3(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
		bodies[p["name"]] = rb
		anchors[p["name"]] = center.global_transform * (p["anchor"] as Vector3)
	var torso: RigidBody3D = bodies.get(&"torso")
	if torso != null:
		for key in bodies.keys():
			if key == &"torso":
				continue
			var j := PinJoint3D.new()
			root.add_child(j)
			j.global_position = anchors[key]
			j.node_a = j.get_path_to(torso)
			j.node_b = j.get_path_to(bodies[key])
	return root


func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0 and not _retiring:
		retire()


## Sink into the floor and disappear. Called on timeout or when the global ragdoll cap is exceeded.
func retire() -> void:
	if _retiring:
		return
	_retiring = true
	for c in get_children():
		if c is RigidBody3D:
			c.freeze = true
			c.collision_layer = 0
			c.collision_mask = 0
	var tw := create_tween()
	tw.tween_property(self, "position:y", position.y - 1.2, 0.7)
	tw.tween_callback(queue_free)
