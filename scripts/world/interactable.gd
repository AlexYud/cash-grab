class_name Interactable
extends Node3D
## Anything a player holds E on that costs shared cash: the annex levers, the mystery box and the two health shops.
## The player decides what is in reach and sends (GENERIC, index) while E is held (Player._update_interactions);
## the host times the hold here and applies the effect. prompt()/can_hold() only read replicated state, so every
## peer shows the same text.

enum Kind { LEVER, BOX, BANDAGE, MEDKIT }

const REACH := 1.9

@export var kind: Kind = Kind.LEVER
@export var index := 0 ## unique among interactables: what the player sends to the host
@export var slot := 0 ## which lever (0/1) this is
@export var stage := 1 ## which pair of levers (see Annex.stage)

var _hold := {} ## host: peer -> seconds held
var _spent := {} ## host: peers that already used it and have not let go of E yet
var _cool := {} ## host: peer -> msec timestamp the shop is ready for them again
var _pivot: Node3D ## lever handle
var _lid: Node3D ## mystery box lid
var _lid_open := 0.0
var _reveal: Label3D

var annex: Annex:
	get:
		if annex == null:
			annex = Annex.find_stage(get_tree(), stage)
		return annex


func _ready() -> void:
	add_to_group("interactables")
	_pivot = get_node_or_null("Pivot") as Node3D
	_lid = get_node_or_null("Lid") as Node3D
	_reveal = get_node_or_null("Reveal") as Label3D


func in_reach(p: Player) -> bool:
	var d := p.global_position - global_position
	return absf(d.y) < 2.0 and Vector2(d.x, d.z).length() <= REACH


func hold_time(_p: Player) -> float:
	match kind:
		Kind.LEVER:
			return GameConfig.LEVER_CANCEL_HOLD if annex != null and annex.lever_pulled(slot) else GameConfig.LEVER_HOLD
		Kind.BOX:
			return GameConfig.BOX_HOLD
	return GameConfig.SHOP_HOLD


func _cash() -> int:
	var wm := get_tree().get_first_node_in_group("wave_manager") as WaveManager
	return wm.cash if wm != null else 0


func _price() -> int:
	match kind:
		Kind.LEVER:
			return annex.lever_cost() if annex != null else GameConfig.LEVER_COST
		Kind.BOX:
			return GameConfig.BOX_COST
		Kind.BANDAGE:
			return GameConfig.BANDAGE_COST
	return GameConfig.MEDKIT_COST


## The mystery box sells support items instead of weapons (those come from the reward cards).
## Weighted roll among the ones that would actually do something for this player.
static func roll_support(p: Player) -> StringName:
	var pool := {}
	if p.hp < GameConfig.PLAYER_MAX_HP:
		pool[&"bandage"] = 3.0
		pool[&"medkit"] = 1.5
	if p.armor < GameConfig.ARMOR_MAX:
		pool[&"armor"] = 2.5
	pool[&"adrenaline"] = 2.0
	if not p.second_wind:
		pool[&"second_wind"] = 1.0
	var total := 0.0
	for k in pool:
		total += pool[k]
	var r := randf() * total
	for k in pool:
		r -= pool[k]
		if r <= 0.0:
			return k
	return &"adrenaline"


static func _apply_support(p: Player, item: StringName) -> String:
	match item:
		&"bandage":
			p.srv_heal(GameConfig.BANDAGE_HEAL)
			return "Bandages (+%d HP)" % GameConfig.BANDAGE_HEAL
		&"medkit":
			p.srv_heal(GameConfig.PLAYER_MAX_HP)
			return "Full Medkit"
		&"armor":
			p.srv_add_armor(GameConfig.ARMOR_ITEM)
			return "Armor Vest (+%d)" % GameConfig.ARMOR_ITEM
		&"adrenaline":
			p.srv_give_boost(GameConfig.ADRENALINE_TIME)
			return "Adrenaline (%d s of speed)" % int(GameConfig.ADRENALINE_TIME)
		_:
			p.second_wind = true
			return "Second Wind (one free revive)"


## HUD text for this player; "" means there is nothing to show (hidden).
func prompt(p: Player) -> String:
	var price := _price()
	match kind:
		Kind.LEVER:
			if annex == null or annex.is_open:
				return ""
			if annex.door_running():
				return "The door is opening..."
			if annex.lever_pulled(slot):
				return "Hold [E] to put the lever back (refund $%d)  -  %d s left" % [price, ceili(annex.latch_left)]
			if _cash() < price:
				return "Pull the lever to open %s  -  needs $%d" % ["the annex" if stage == 1 else "the hall", price]
			if annex.lever1 or annex.lever2:
				return "Hold [E] to pull the second lever ($%d)  -  %d s left" % [price, ceili(annex.latch_left)]
			return "Hold [E] to pull the lever ($%d), then pull the other one" % price
		Kind.BOX:
			if _cash() < price:
				return "Mystery Box  -  needs $%d" % price
			return "Hold [E] for a random support item ($%d)" % price
		Kind.BANDAGE:
			if p.hp >= GameConfig.PLAYER_MAX_HP:
				return "Bandages  -  you are at full health"
			if _cash() < price:
				return "Bandages (+%d HP)  -  needs $%d" % [GameConfig.BANDAGE_HEAL, price]
			return "Hold [E] for bandages: +%d HP ($%d)" % [GameConfig.BANDAGE_HEAL, price]
		Kind.MEDKIT:
			if p.hp >= GameConfig.PLAYER_MAX_HP:
				return "Medkit  -  you are at full health"
			if _cash() < price:
				return "Medkit (full heal)  -  needs $%d" % price
			return "Hold [E] for a medkit: full heal ($%d)" % price
	return ""


func can_hold(p: Player) -> bool:
	var price := _price()
	match kind:
		Kind.LEVER:
			if annex == null or annex.is_open or annex.door_running():
				return false
			return annex.lever_pulled(slot) or _cash() >= price
		Kind.BOX:
			return _cash() >= price
		Kind.BANDAGE, Kind.MEDKIT:
			return _cash() >= price and p.hp < GameConfig.PLAYER_MAX_HP
	return false


# --- host --------------------------------------------------------------------------------------------------

func srv_reset() -> void:
	_hold.clear()
	_spent.clear()
	_cool.clear()


func _physics_process(delta: float) -> void:
	_animate(delta)
	if not multiplayer.is_server():
		return
	for p in Net.all_players():
		var pid := p.peer_id
		var active := p.status == Player.Status.ALIVE and p.interact_kind == Player.Interact.GENERIC \
				and p.interact_target == index and in_reach(p)
		if not active:
			_hold.erase(pid)
			_spent.erase(pid)
			continue
		if _spent.has(pid) or not can_hold(p):
			_hold.erase(pid)
			continue
		_hold[pid] = float(_hold.get(pid, 0.0)) + delta
		if _hold[pid] >= hold_time(p):
			_hold.erase(pid)
			_spent[pid] = true
			_srv_use(p)


func _srv_use(p: Player) -> void:
	var wm := get_tree().get_first_node_in_group("wave_manager") as WaveManager
	if wm == null:
		return
	match kind:
		Kind.LEVER:
			if annex.lever_pulled(slot):
				if annex.srv_cancel(slot):
					p.notify("Lever put back - refunded $%d" % annex.lever_cost())
			elif annex.srv_pull(slot):
				fx_lever.rpc()
				if annex.door_running():
					p.notify("Both levers down - the annex door is opening!")
				else:
					p.notify("Lever pulled - now the other one (%d s)" % int(GameConfig.LEVER_WINDOW))
		Kind.BOX:
			var item := roll_support(p)
			if item == &"" or not wm.srv_spend(GameConfig.BOX_COST):
				return
			var label := _apply_support(p, item)
			fx_box.rpc(label)
			p.notify("You got: %s!" % label)
		Kind.BANDAGE, Kind.MEDKIT:
			var now := Time.get_ticks_msec()
			var ready_at: int = int(_cool.get(p.peer_id, 0))
			if now < ready_at:
				p.notify("Restocking... %d s" % ceili((ready_at - now) / 1000.0))
				return
			if p.hp >= GameConfig.PLAYER_MAX_HP or not wm.srv_spend(_price()):
				return
			p.srv_heal(GameConfig.BANDAGE_HEAL if kind == Kind.BANDAGE else GameConfig.PLAYER_MAX_HP)
			_cool[p.peer_id] = now + int(GameConfig.SHOP_COOLDOWN * 1000.0)
			fx_shop.rpc()
			p.notify("Healed!")


# --- cosmetics (every peer) -----------------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func fx_lever() -> void:
	Sfx.play_at(&"hammer", global_position + Vector3.UP, 2.0, 0.6)


@rpc("authority", "call_local", "reliable")
func fx_box(weapon_name: String) -> void:
	_lid_open = 1.0
	Sfx.play_at(&"disco", global_position + Vector3.UP, 0.0, 0.8)
	if _reveal != null:
		_reveal.text = weapon_name
		_reveal.visible = true
		var tw := create_tween()
		tw.tween_interval(3.0)
		tw.tween_callback(func() -> void:
			if is_instance_valid(_reveal):
				_reveal.visible = false)


@rpc("authority", "call_local", "reliable")
func fx_shop() -> void:
	Sfx.play_at(&"revive", global_position + Vector3.UP, -2.0, 1.1)


func _animate(delta: float) -> void:
	if _pivot != null and annex != null:
		var pulled := annex.lever_pulled(slot)
		_pivot.rotation.x = lerp_angle(_pivot.rotation.x, deg_to_rad(55.0) if pulled else deg_to_rad(-55.0), minf(delta * 10.0, 1.0))
	if _lid != null:
		_lid_open = maxf(_lid_open - delta * 0.35, 0.0)
		_lid.rotation.x = lerpf(_lid.rotation.x, deg_to_rad(-100.0) * minf(_lid_open * 3.0, 1.0), minf(delta * 12.0, 1.0))
