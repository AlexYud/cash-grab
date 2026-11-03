extends BotScenario
## Single-player check: the runtime-baked navmesh lets zombies path from every entrance spawn to the players,
## going through the doorway (the barricade blocker is deliberately not part of the bake).


func run() -> void:
	await wait(1.0)
	var level := get_tree().get_first_node_in_group("level") as SaloonLevel
	var map := level.nav_region.get_navigation_map()
	report("navmesh baked", level.nav_region.navigation_mesh.get_polygon_count() > 0, "polygons=%d" % level.nav_region.navigation_mesh.get_polygon_count())
	report("nav map synced", NavigationServer3D.map_get_iteration_id(map) > 0)
	var target := level.player_spawn(0).origin
	for i in level.barricades.size():
		var bar := level.barricades[i]
		var from := level.enemy_spawn_point(i)
		var inside := bar.global_position - bar.outward_dir() * 1.5 # a spot just behind this window
		# zombies walk to their own window first, so test spawn -> just inside the window, then inside -> players
		var in_path := NavigationServer3D.map_get_path(map, from, inside, true)
		var through := false
		for k in range(in_path.size() - 1): # waypoints are sparse on straight runs: test where each segment crosses the window plane
			var da := bar.distance_outside(in_path[k])
			var db := bar.distance_outside(in_path[k + 1])
			if (da > 0.0) != (db > 0.0):
				var cross: Vector3 = in_path[k].lerp(in_path[k + 1], da / (da - db))
				if absf(bar.lateral(cross)) < 1.6:
					through = true
		var path := NavigationServer3D.map_get_path(map, inside, target, true)
		var ok := path.size() >= 2 and path[path.size() - 1].distance_to(target) < 1.5
		report("path from just inside window %d to the players" % i, ok, "points=%d" % path.size())
		report("path from outside reaches window %d through its opening" % i, through)
	# the annex doorway is not part of the bake either (the gate sits outside Nav), so shop spots are reachable
	for spot in [Vector3(58.2, 0, -5.0), Vector3(34.2, 0, 6.6), Vector3(34.6, 0, -6.8), Vector3(34.6, 0, 3.4), Vector3(40.0, 0, 0.0), Vector3(10.2, 0, -4.8), Vector3(10.2, 0, 3.8), Vector3(-9.0, 0, 6.4)]:
		var p := NavigationServer3D.map_get_path(map, target, spot, true)
		report("path from the spawn to %s" % str(spot), p.size() >= 2 and p[p.size() - 1].distance_to(spot) < 1.0, "points=%d" % p.size())
	# every wall buy, machine, lever and shop can be walked up to
	var unreachable := PackedStringArray()
	for n in get_tree().get_nodes_in_group("interactables"):
		var it := n as Interactable
		var spot := it.global_position + it.global_basis.z.normalized() * 0.4
		var pth := NavigationServer3D.map_get_path(map, target, spot, true)
		if pth.size() < 2 or pth[pth.size() - 1].distance_to(spot) > 1.0:
			unreachable.append(str(it.name))
	report("every interactable (wall buys, machines, levers, shops) is reachable", unreachable.is_empty(), ", ".join(unreachable))
	finish()
