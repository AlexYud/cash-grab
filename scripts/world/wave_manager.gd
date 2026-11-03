class_name WaveManager
extends Node
## Round flow: break -> wave (spawn budget) -> break -> ... forever, until nobody is left standing.
## Every break the players repair, shop and reposition; the next wave starts when everybody
## has pressed ready. Host drives it; the few replicated vars feed every peer's HUD.

enum State { IDLE, BREAK, ACTIVE, VICTORY, GAME_OVER } ## VICTORY is no longer reached (rounds are endless); kept for the end screen

signal announce(text: String)
signal notice(text: String) ## small, short-lived HUD message (shop feedback, lever refunds)
signal offers_changed ## this peer's reward cards changed (empty = none to pick from)

# --- replicated (host -> all) ---
var state: int = State.IDLE:
	set = _set_state
var wave := 0:
	set = _set_wave
var enemies_alive := 0
var to_spawn := 0
var break_left := 0.0 ## unused now (no countdown); kept so older tests and saved scenes still load
var cash := 0 ## one shared pot for the whole team (replicated)
var ready_ids := PackedInt32Array() ## peers that pressed ready this break (replicated)

var hold := false ## tests: freeze the break and spawning so a bot can stage its own scenario
var my_offers: Array = [] ## this peer's reward cards for the current break
var _spawn_timer := 0.0
var _next_id := 1
var _last_entrance := -1
var _kind_plan: Array = [] ## kinds still to spawn this wave (specials are shuffled in with the normals)
var _offers := {} ## host: peer -> that player's cards

@onready var enemy_spawner: MultiplayerSpawner = $"../EnemySpawner"
@onready var enemies: Node3D = $"../Enemies"
@onready var level: SaloonLevel = $"../Level"


func _ready() -> void:
	add_to_group("wave_manager")


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
				announce.emit("Wave %d cleared!" % wave)
			else:
				announce.emit("Get ready - repair and reposition")
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
	cash = 0
	for p in Net.all_players():
		p.weapons.reset_weapons.rpc() # a new run starts with just the pistol
		p.srv_reset_support()
		p.hugged = 0
	wave = 0
	to_spawn = 0
	_next_id = 1
	_clear_break()
	_clear_offers()
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
			if _everyone_ready():
				_begin_wave()
		State.ACTIVE:
			_tick_active(delta)
	if state == State.BREAK or state == State.ACTIVE:
		_check_game_over()


func _begin_wave() -> void:
	wave += 1
	_clear_break()
	var cfg := GameConfig.wave_cfg(wave)
	var players := maxi(Net.all_players().size(), 1)
	var scale: float = GameConfig.PLAYER_COUNT_SCALE[clampi(players - 1, 0, GameConfig.PLAYER_COUNT_SCALE.size() - 1)]
	var normal := maxi(int(round(cfg["count"] * scale)), 1)
	_kind_plan.clear()
	for entry in [["brutes", Zombie.Kind.BRUTE], ["leapers", Zombie.Kind.LEAPER], ["bloaters", Zombie.Kind.BLOATER], ["huggers", Zombie.Kind.HUGGER], ["crawlers", Zombie.Kind.CRAWLER]]:
		for i in _scaled_special(int(cfg.get(entry[0], 0)), scale):
			_kind_plan.append(entry[1])
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
	var cfg := GameConfig.wave_cfg(wave)
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
	state = State.BREAK
	_clear_break()
	var bonus := GameConfig.CASH_WAVE_CLEAR_BASE + GameConfig.CASH_WAVE_CLEAR_STEP * (wave - 1)
	srv_add_cash(bonus)
	cl_notice.rpc("Wave %d cleared  +$%d" % [wave, bonus])
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
	var zk: int = _kind_plan.pop_back() if not _kind_plan.is_empty() else Zombie.Kind.NORMAL
	if zk == Zombie.Kind.CRAWLER:
		if _spawn_crawler():
			to_spawn -= 1
			return
		zk = Zombie.Kind.NORMAL # no vent open: it is a plain zombie then
	var active: Array[int] = [] # the annex / hall windows only count once that room is open
	for i in level.barricades.size():
		if level.barricades[i].is_active():
			active.append(i)
	var entrance: int = active.pick_random()
	if entrance == _last_entrance and active.size() > 1 and randf() < 0.5:
		entrance = active[(active.find(entrance) + 1) % active.size()]
	_last_entrance = entrance
	var bar := level.barricades[entrance]
	var base := level.enemy_spawn_point(entrance)
	var lateral := bar.global_basis.x.normalized() * randf_range(-2.0, 2.0)
	var back := bar.outward_dir() * randf_range(0.0, 3.0)
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


## A crawler pops out of a wall vent in a room that is open and climbs to the ceiling.
func _spawn_crawler() -> bool:
	var open_vents: Array[Marker3D] = []
	for v in level.vents:
		if int(v.get_meta("stage", 0)) == 0 or (Annex.find_stage(get_tree(), int(v.get_meta("stage"))) != null and Annex.find_stage(get_tree(), int(v.get_meta("stage"))).is_open):
			open_vents.append(v)
	if open_vents.is_empty():
		return false
	var vent: Marker3D = open_vents.pick_random()
	var n := vent.global_basis.z.normalized() # points into the room
	var z := spawn_at(vent.global_position + n * 0.15, -1, int(GameConfig.CRAWLER_HP * (1.0 + 0.04 * maxi(wave - 4, 0))), GameConfig.CRAWLER_SPEED * randf_range(0.9, 1.1), Zombie.Kind.CRAWLER, atan2(n.x, n.z))
	return z != null


## Host only. Also used by tests to stage a zombie wherever they need one.
func spawn_at(pos: Vector3, entrance: int, hp: int, speed: float, zombie_kind: int = 0, yaw_override: float = NAN) -> Zombie:
	var yaw := yaw_override
	if is_nan(yaw):
		var out := level.barricades[entrance].outward_dir()
		yaw = atan2(out.x, out.z)
		pos.y = 0.1
	var z := enemy_spawner.spawn({
		"id": _next_id,
		"pos": pos,
		"entrance": entrance,
		"slot": randi() % 4,
		"hp": hp,
		"speed": speed,
		"kind": zombie_kind,
		"yaw": yaw,
	}) as Zombie
	_next_id += 1
	return z


## Specials scale with the team like everything else, but never round away to nothing.
func _scaled_special(n: int, scale: float) -> int:
	return 0 if n <= 0 else maxi(int(round(n * scale)), 1)


# --- ready button + reward cards ---------------------------------------------------------------------

func _everyone_ready() -> bool:
	var players := Net.all_players()
	if players.is_empty():
		return false
	for p in players:
		if not ready_ids.has(p.peer_id):
			return false
	return true


func is_ready(peer: int) -> bool:
	return ready_ids.has(peer)


## This peer presses (or un-presses) ready.
func press_ready(v: bool) -> void:
	if multiplayer.is_server():
		_srv_set_ready(1, v)
	else:
		srv_set_ready.rpc_id(1, v)


@rpc("any_peer", "call_remote", "reliable")
func srv_set_ready(v: bool) -> void:
	if multiplayer.is_server():
		_srv_set_ready(multiplayer.get_remote_sender_id(), v)


func _srv_set_ready(peer: int, v: bool) -> void:
	if state != State.BREAK or Net.get_player(peer) == null:
		return
	var has := ready_ids.has(peer)
	if v and not has:
		ready_ids.append(peer)
	elif not v and has:
		ready_ids.remove_at(ready_ids.find(peer))


## This peer takes upgrade card `i` of the cards it is holding.
func request_pick(i: int) -> void:
	if multiplayer.is_server():
		_srv_pick(1, i)
	else:
		srv_pick.rpc_id(1, i)


@rpc("any_peer", "call_remote", "reliable")
func srv_pick(i: int) -> void:
	if multiplayer.is_server():
		_srv_pick(multiplayer.get_remote_sender_id(), i)


## Host: a player collects what an upgrader machine finished (their weapon, or their gear). Three cards for it; they
## have already paid at drop-off, so choosing costs nothing - but until they choose, the weapon stays in the machine.
## Collecting again just brings the same cards back.
func srv_open_collect(p: Player, gear: bool, weapon_idx: int, machine_index: int) -> void:
	var held := _offers.get(p.peer_id, []) as Array
	if not held.is_empty() and int(held[0].get("machine", -1)) == machine_index:
		_send_offers(p.peer_id, held)
		return
	var cards: Array
	if gear:
		var levels := {}
		for i in ArmorCards.KEYS.size():
			levels[ArmorCards.KEYS[i]] = p.gear_levels[i]
		cards = ArmorCards.roll(levels)
	else:
		cards = WeaponCards.roll_upgrade(p.weapons, weapon_idx)
	for c in cards:
		c["cost"] = 0
		c["gear"] = gear
		c["machine"] = machine_index
	_offers[p.peer_id] = cards
	_send_offers(p.peer_id, cards)


## What the next weapon upgrade of weapon `idx` costs this player (paid when the weapon goes into the machine).
static func weapon_upgrade_cost(p: Player, idx: int) -> int:
	var spent := 0
	for k in p.weapons.mods[idx]:
		spent += int(p.weapons.mods[idx][k])
	return GameConfig.UPGRADE_BASE + GameConfig.UPGRADE_STEP * spent


static func gear_upgrade_cost(p: Player) -> int:
	return GameConfig.GEAR_BASE + GameConfig.GEAR_STEP * p.gear_level_sum()


func _srv_pick(peer: int, i: int) -> void:
	var p := Net.get_player(peer)
	if p == null or not _offers.has(peer):
		return
	var cards: Array = _offers[peer]
	if i < 0 or i >= cards.size():
		return
	var card: Dictionary = cards[i]
	_offers.erase(peer)
	_send_offers(peer, [])
	var machine := Interactable.find_by_index(get_tree(), int(card.get("machine", -1)))
	if machine != null:
		machine.srv_give_back(p) # the weapon / gear comes out of the machine, upgraded below
	if bool(card.get("gear", false)):
		p.srv_apply_gear(StringName(card["mod"]))
		p.notify("%s upgraded!" % ArmorCards.title(card))
	else:
		p.weapons.apply_mod.rpc(int(card["w"]), StringName(card["mod"]))
		p.notify("%s: %s!" % [p.weapons.list[int(card["w"])].display_name, WeaponCards.title(card)])


func _send_offers(peer: int, cards: Array) -> void:
	if peer == 1:
		_set_offers(cards)
	else:
		cl_offers.rpc_id(peer, cards)


@rpc("authority", "call_remote", "reliable")
func cl_offers(cards: Array) -> void:
	_set_offers(cards)


func _set_offers(cards: Array) -> void:
	my_offers = cards
	offers_changed.emit()


## Leaving a break: nobody is ready any more.
func _clear_break() -> void:
	ready_ids = PackedInt32Array()


## A new run: nobody holds any upgrade cards either.
func _clear_offers() -> void:
	_offers.clear()
	for p in Net.all_players():
		_send_offers(p.peer_id, [])


# --- shared cash ------------------------------------------------------------------------------------

func srv_add_cash(n: int) -> void:
	cash += n


@rpc("authority", "call_local", "reliable")
func cl_notice(text: String) -> void:
	notice.emit(text)


## Returns false (and spends nothing) if the team cannot afford it.
func srv_spend(n: int) -> bool:
	if cash < n:
		return false
	cash -= n
	return true
