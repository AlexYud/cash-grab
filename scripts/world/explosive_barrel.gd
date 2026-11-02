class_name ExplosiveBarrel
extends StaticBody3D
## The one test explosion: shoot it and everything nearby (players and zombies) gets launched.
## Host decides; `alive` replicates so every peer hides the barrel; Fx.explosion renders the blast.

const MAX_HP := 40

@export var index := 0

var hp := MAX_HP
var alive := true:
	set = _set_alive


func _ready() -> void:
	add_to_group("barrels")
	collision_layer = GameConfig.L_PROPS
	collision_mask = 0


static func find_by_index(tree: SceneTree, i: int) -> ExplosiveBarrel:
	for n in tree.get_nodes_in_group("barrels"):
		var b := n as ExplosiveBarrel
		if b != null and b.index == i:
			return b
	return null


func srv_reset() -> void:
	hp = MAX_HP
	alive = true


func srv_damage(amount: int, source: Player) -> void:
	if not alive:
		return
	hp -= amount
	if hp <= 0:
		_explode(source)


func _explode(source: Player) -> void:
	alive = false
	var radius := GameConfig.EXPLOSION_RADIUS
	var center := global_position + Vector3(0, 0.6, 0)
	Fx.explosion.rpc(global_position, radius)
	for p in Net.all_players():
		if p.status == Player.Status.ELIMINATED:
			continue
		var to := p.global_position + Vector3(0, 0.9, 0) - center
		var d := to.length()
		if d > radius:
			continue
		var f := 1.0 - d / radius
		var flat := Vector3(to.x, 0.0, to.z)
		flat = flat.normalized() if flat.length() > 0.1 else Vector3.FORWARD
		p.srv_launch(flat * GameConfig.EXPLOSION_FORCE * (0.4 + 0.6 * f) + Vector3.UP * GameConfig.EXPLOSION_UP * (0.5 + 0.5 * f), 0.9, true)
		if GameConfig.EXPLOSION_PLAYER_DAMAGE > 0:
			p.srv_take_damage(int(GameConfig.EXPLOSION_PLAYER_DAMAGE * f))
	for n in get_tree().get_nodes_in_group("enemies"):
		var z := n as Zombie
		if z == null or z.is_dead():
			continue
		var to := z.global_position + Vector3(0, 0.9, 0) - center
		var d := to.length()
		if d > radius:
			continue
		var f := 1.0 - d / radius
		var flat := Vector3(to.x, 0.0, to.z)
		flat = flat.normalized() if flat.length() > 0.1 else Vector3.FORWARD
		z.srv_explode(int(GameConfig.EXPLOSION_ENEMY_DAMAGE * f), flat * GameConfig.EXPLOSION_FORCE * (0.4 + 0.6 * f) + Vector3.UP * 5.0, source)
	# chain reaction
	for n in get_tree().get_nodes_in_group("barrels"):
		var b := n as ExplosiveBarrel
		if b != null and b != self and b.alive and b.global_position.distance_to(global_position) < radius * 0.8:
			get_tree().create_timer(0.3).timeout.connect(func() -> void:
				if is_instance_valid(b):
					b.srv_damage(999, source))


func _set_alive(v: bool) -> void:
	alive = v
	if is_node_ready():
		visible = v
		collision_layer = GameConfig.L_PROPS if v else 0
