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
		var from := level.enemy_spawn_point(i)
		var path := NavigationServer3D.map_get_path(map, from, target, true)
		var ok := path.size() >= 2 and path[path.size() - 1].distance_to(target) < 1.5
		var through := false
		for pt in path:
			if absf(level.barricades[i].distance_outside(pt)) < 1.0 and absf(level.barricades[i].lateral(pt)) < 1.6:
				through = true
		report("path from entrance %d to players" % i, ok, "points=%d" % path.size())
		report("path %d runs through its doorway" % i, through)
	finish()
