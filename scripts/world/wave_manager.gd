class_name WaveManager
extends Node
## Round flow: break -> wave (spawn budget) -> break ... -> victory after the last wave, or game over when
## nobody is left standing. Host drives it; the few replicated vars feed every peer's HUD.

enum State { IDLE, BREAK, ACTIVE, VICTORY, GAME_OVER }

signal announce(text: String)

# --- replicated (host -> all) ---
var state: int = State.IDLE:
	set = _set_state
var wave := 0:
	set = _set_wave
var enemies_alive := 0
var to_spawn := 0
var break_left := 0.0

var total_waves: int = GameConfig.WAVES.size()
var hold := false ## tests: freeze the break timer and spawning so a bot can stage its own scenario
var _spawn_timer := 0.0
var _next_id := 1
var _last_entrance := -1
var _kind_plan: Array = [] ## kinds still to spawn this wave (specials are shuffled in with the normals)

@onready var enemy_spawner: MultiplayerSpawner = $"../EnemySpawner"
@onready var enemies: Node3D = $"../Enemies"
@onready var level: SaloonLevel = $"../Level"


func _set_state(v: int) -> void:
	if v == state:
		return
	state = v
	match v:
		State.ACTIVE:
			announce.emit("WAVE %d" % wave)
			Sfx.play(&"wave_start", -4.0)
		State.BREAK:
			if wave > 0:
				announce.emit("Wave %d cleared - repair the barricades!" % wave)
			else:
				announce.emit("Get ready - repair and reposition")
		State.VICTORY:
			announce.emit("YOU SURVIVED ALL %d WAVES" % total_waves)
		State.GAME_OVER:
			announce.emit("EVERYONE IS DOWN")


func _set_wave(v: int) -> void:
	wave = v


# --- host ------------------------------------------------------------------------------------------

func start_run() -> void:
	for e in enemies.get_children():
		e.queue_free()
	level.reset_run()
	Fx.srv_clear_snacks()
	for p in Net.all_players():
		p.hugged = 0
	wave = 0
	to_spawn = 0
	_next_id = 1
	break_left = GameConfig.FIRST_BREAK
	state = State.IDLE # force the setter to fire even on a restart from BREAK
	state = State.BREAK


func restart_run() -> void:
	for p in Net.all_players():
		p.kills = 0
		p.srv_restore(level.player_spawn(Net.all_players().find(p)).origin, true)
	start_run()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	enemies_alive = enemies.get_child_count()
	if hold:
		return
	match state:
		State.BREAK:
			break_left -= delta
			if break_left <= 0.0:
				_begin_wave()
		State.ACTIVE:
			_tick_active(delta)
	if state == State.BREAK or state == State.ACTIVE:
		_check_game_over()


func _begin_wave() -> void:
	wave += 1
	var cfg: Dictionary = GameConfig.WAVES[wave - 1]
	var players := maxi(Net.all_players().size(), 1)
	var scale: float = GameConfig.PLAYER_COUNT_SCALE[clampi(players - 1, 0, GameConfig.PLAYER_COUNT_SCALE.size() - 1)]
	var normal := maxi(int(round(cfg["count"] * scale)), 1)
	_kind_plan.clear()
	for i in _scaled_special(int(cfg.get("brutes", 0)), scale):
		_kind_plan.append(Zombie.Kind.BRUTE)
	for i in _scaled_special(int(cfg.get("leapers", 0)), scale):
		_kind_plan.append(Zombie.Kind.LEAPER)
	for i in _scaled_special(int(cfg.get("bloaters", 0)), scale):
		_kind_plan.append(Zombie.Kind.BLOATER)
	for i in _scaled_special(int(cfg.get("huggers", 0)), scale):
		_kind_plan.append(Zombie.Kind.HUGGER)
	var specials := _kind_plan.size()
	for i in normal:
		_kind_plan.append(Zombie.Kind.NORMAL)
	_kind_plan.shuffle()
	to_spawn = normal + specials
	_spawn_timer = 1.5
	for b in level.barrels:
		if not b.alive:
			b.srv_reset()
	state = State.ACTIVE


func _tick_active(delta: float) -> void:
	var cfg: Dictionary = GameConfig.WAVES[wave - 1]
	if to_spawn > 0:
		var cap := int(cfg["max_alive"])
		if enemies_alive < cap:
			_spawn_timer -= delta
			if _spawn_timer <= 0.0:
				_spawn_timer = float(cfg["interval"])
				_spawn_one(cfg)
	elif enemies_alive == 0:
		_end_wave()


func _end_wave() -> void:
	if wave >= total_waves:
		state = State.VICTORY
		return
	break_left = GameConfig.BREAK_TIME
	state = State.BREAK
	if GameConfig.RESTORE_ON_WAVE_CLEAR:
		var idx := 0
		for p in Net.all_players():
			if p.status != Player.Status.ALIVE:
				p.srv_restore(level.player_spawn(idx).origin, p.status == Player.Status.ELIMINATED)
			idx += 1


func _check_game_over() -> void:
	var players := Net.all_players()
	if players.is_empty():
		return
	for p in players:
		if p.status == Player.Status.ALIVE:
			return
	state = State.GAME_OVER


func _spawn_one(cfg: Dictionary) -> void:
	var entrance := randi() % level.barricades.size()
	if entrance == _last_entrance and randf() < 0.5:
		entrance = (entrance + 1) % level.barricades.size()
	_last_entrance = entrance
	var bar := level.barricades[entrance]
	var base := level.enemy_spawn_point(entrance)
	var lateral := bar.global_basis.x.normalized() * randf_range(-2.0, 2.0)
	var back := bar.outward_dir() * randf_range(0.0, 3.0)
	var zk: int = _kind_plan.pop_back() if not _kind_plan.is_empty() else Zombie.Kind.NORMAL
	var hp := int(cfg["hp"] * randf_range(0.92, 1.08))
	var speed := float(cfg["speed"]) * randf_range(0.85, 1.15)
	if zk == Zombie.Kind.BRUTE:
		hp = int(hp * GameConfig.BRUTE_HP_MULT)
		speed = GameConfig.BRUTE_SPEED
	elif zk == Zombie.Kind.LEAPER:
		hp = GameConfig.LEAPER_HP
		speed = GameConfig.LEAPER_SPEED * randf_range(0.9, 1.1)
	elif zk == Zombie.Kind.BLOATER:
		hp = GameConfig.BLOATER_HP
		speed = GameConfig.BLOATER_SPEED
	elif zk == Zombie.Kind.HUGGER:
		hp = GameConfig.HUGGER_HP
		speed = GameConfig.HUGGER_SPEED * randf_range(0.9, 1.1)
	spawn_at(base + lateral + back, entrance, hp, speed, zk)
	to_spawn -= 1


## Host only. Also used by tests to stage a zombie wherever they need one.
func spawn_at(pos: Vector3, entrance: int, hp: int, speed: float, zombie_kind: int = 0) -> Zombie:
	var out := level.barricades[entrance].outward_dir()
	pos.y = 0.1
	var z := enemy_spawner.spawn({
		"id": _next_id,
		"pos": pos,
		"entrance": entrance,
		"slot": randi() % 4,
		"hp": hp,
		"speed": speed,
		"kind": zombie_kind,
		"yaw": atan2(out.x, out.z),
	}) as Zombie
	_next_id += 1
	return z


## Specials scale with the team like everything else, but never round away to nothing.
func _scaled_special(n: int, scale: float) -> int:
	return 0 if n <= 0 else maxi(int(round(n * scale)), 1)
