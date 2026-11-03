class_name Interactable
extends Node3D
## Anything a player holds E on that costs shared cash: the annex levers, the mystery box and the two health shops.
## The player decides what is in reach and sends (GENERIC, index) while E is held (Player._update_interactions);
## the host times the hold here and applies the effect. prompt()/can_hold() only read replicated state, so every
## peer shows the same text.

enum Kind { LEVER, BOX, BANDAGE, MEDKIT, WALL_WEAPON, WALL_SUPPORT, WEAPON_UPGRADER, ARMOR_UPGRADER }

const REACH := 1.9

@export var kind: Kind = Kind.LEVER
@export var index := 0 ## unique among interactables: what the player sends to the host
@export var slot := 0 ## which lever (0/1) this is
@export var stage := 1 ## which pair of levers (see Annex.stage)
@export var item: StringName = &"" ## wall buys: the weapon id (WeaponData.id) or support item sold here

var _hold := {} ## host: peer -> seconds held
var _spent := {} ## host: peers that already used it and have not let go of E yet
var _cool := {} ## host: peer -> msec timestamp the shop is ready for them again
var _pivot: Node3D ## lever handle
var _lid: Node3D ## mystery box lid
var _lid_open := 0.0
var _reveal: Label3D
var _status: Label3D ## upgrader machines: who has what inside
var _slots := {} ## host: peer -> {"w": weapon index (-1 = gear), "ready_at": host msec}
var _slot_view := {} ## every peer: peer -> {"w", "ready_at": local msec} (a copy of the above, via fx_slots)

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
	_status = get_node_or_null("Status") as Label3D


func in_reach(p: Player) -> bool:
	var d := p.global_position - global_position
	return absf(d.y) < 2.0 and Vector2(d.x, d.z).length() <= REACH


func hold_time(_p: Player) -> float:
	match kind:
		Kind.LEVER:
			return GameConfig.LEVER_CANCEL_HOLD if annex != null and annex.lever_pulled(slot) else GameConfig.LEVER_HOLD
		Kind.BOX:
			return GameConfig.BOX_HOLD
		Kind.WEAPON_UPGRADER, Kind.ARMOR_UPGRADER:
			return GameConfig.UPGRADE_HOLD
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
		Kind.WALL_WEAPON:
			return int(GameConfig.WEAPON_PRICES.get(item, 500))
		Kind.WALL_SUPPORT:
			return {&"armor": GameConfig.ARMOR_BUY_COST, &"adrenaline": GameConfig.ADRENALINE_COST, &"second_wind": GameConfig.SECOND_WIND_COST}.get(item, 500)
	return GameConfig.MEDKIT_COST


## The mystery box sells support items instead of weapons (those come from the reward cards).
## Weighted roll among the ones that would actually do something for this player.
static func roll_support(p: Player) -> StringName:
	var pool := {}
	if p.hp < GameConfig.PLAYER_MAX_HP:
		pool[&"bandage"] = 3.0
		pool[&"medkit"] = 1.5
	if p.armor < p.armor_cap():
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


static func _apply_support(p: Player, what: StringName) -> String:
	match what:
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
		Kind.WALL_WEAPON:
			var idx := _weapon_index(p)
			var wname := p.weapons.list[idx].display_name if idx >= 0 else String(item)
			if idx >= 0 and p.weapons.owned[idx]:
				return "%s  -  you already have it" % wname
			if _cash() < price:
				return "%s  -  needs $%d" % [wname, price]
			return "Hold [E] to buy the %s ($%d)" % [wname, price]
		Kind.WALL_SUPPORT:
			var sname: String = {&"armor": "Armor Vest (+50 armor)", &"adrenaline": "Adrenaline (30 s of speed)", &"second_wind": "Second Wind (one free revive)"}.get(item, String(item))
			if not _support_useful(p):
				return "%s  -  you already have it" % sname
			if _cash() < price:
				return "%s  -  needs $%d" % [sname, price]
			return "Hold [E] to buy: %s ($%d)" % [sname, price]
		Kind.WEAPON_UPGRADER, Kind.ARMOR_UPGRADER:
			return _machine_prompt(p)
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
		Kind.WALL_WEAPON:
			var idx := _weapon_index(p)
			return idx >= 0 and not p.weapons.owned[idx] and _cash() >= price
		Kind.WALL_SUPPORT:
			return _cash() >= price and _support_useful(p)
		Kind.WEAPON_UPGRADER, Kind.ARMOR_UPGRADER:
			if p.status != Player.Status.ALIVE:
				return false
			var mine := _slot_view.get(p.peer_id, {}) as Dictionary
			if mine.is_empty(): # drop-off: needs something to hand in, and the cash
				return _cash() >= _upgrade_price(p) and (kind == Kind.ARMOR_UPGRADER or p.weapons.owned[p.weapons.current])
			return _slot_left(mine) <= 0.0 # collect, once it is done
	return false


func _weapon_index(p: Player) -> int:
	for i in p.weapons.list.size():
		if p.weapons.list[i].id == item:
			return i
	return -1


func _support_useful(p: Player) -> bool:
	match item:
		&"armor":
			return p.armor < p.armor_cap()
		&"second_wind":
			return not p.second_wind
	return true


func _upgrade_price(p: Player) -> int:
	if kind == Kind.ARMOR_UPGRADER:
		return WaveManager.gear_upgrade_cost(p)
	return WaveManager.weapon_upgrade_cost(p, p.weapons.current)


# --- upgrader machines: hand it in and pay, wait 5 s, collect it and pick one of three upgrades ------------------

## Seconds until this slot is done (<= 0: ready). `view` is {"w": weapon index or -1 for gear, "ready_at": local msec}.
func _slot_left(view: Dictionary) -> float:
	return (int(view["ready_at"]) - Time.get_ticks_msec()) / 1000.0


func _machine_prompt(p: Player) -> String:
	var gear := kind == Kind.ARMOR_UPGRADER
	var mine := _slot_view.get(p.peer_id, {}) as Dictionary
	if not mine.is_empty():
		var what := "gear" if gear else String(p.weapons.list[int(mine["w"])].display_name)
		var left := _slot_left(mine)
		if left > 0.0:
			return "Upgrading your %s...  %d s" % [what, ceili(left)]
		return "Hold [E] to collect your %s  -  pick one of three upgrades (or it stays here)" % what
	var price := _upgrade_price(p)
	if gear:
		if _cash() < price:
			return "Armor upgrader  -  hand in your gear for $%d (5 s)" % price
		return "Hold [E] to put your gear in the machine ($%d)  -  5 s, then pick one of three upgrades" % price
	var cur := p.weapons.list[p.weapons.current]
	if not p.weapons.owned[p.weapons.current]:
		return "Weapon upgrader  -  hold the weapon you want upgraded"
	if _cash() < price:
		return "Weapon upgrader  -  upgrading your %s costs $%d" % [cur.display_name, price]
	return "Hold [E] to put your %s in the machine ($%d)  -  5 s, then pick one of three upgrades" % [cur.display_name, price]


## Host: a slot was created, finished or emptied: every peer learns who has what in here and how long is left.
func _sync_slots() -> void:
	var out: Array = []
	for peer in _slots:
		out.append([peer, int(_slots[peer]["w"]), maxf((int(_slots[peer]["ready_at"]) - Time.get_ticks_msec()) / 1000.0, 0.0)])
	fx_slots.rpc(out)


@rpc("authority", "call_local", "reliable")
func fx_slots(data: Array) -> void:
	_slot_view.clear()
	for e in data:
		_slot_view[int(e[0])] = {"w": int(e[1]), "ready_at": Time.get_ticks_msec() + int(float(e[2]) * 1000.0)}
	Sfx.play_at(&"hammer", global_position + Vector3.UP, -6.0, 1.4)


## Host: the weapon / gear goes into the machine and the player pays.
func _srv_hand_in(p: Player, wm: WaveManager) -> void:
	if _slots.has(p.peer_id):
		return
	var gear := kind == Kind.ARMOR_UPGRADER
	var idx := -1 if gear else p.weapons.current
	if not gear and not p.weapons.owned[idx]:
		return
	if not wm.srv_spend(_upgrade_price(p)):
		return
	if gear:
		p.srv_hand_in_gear()
	else:
		p.weapons.take_weapon.rpc(idx)
	_slots[p.peer_id] = {"w": idx, "ready_at": Time.get_ticks_msec() + int(GameConfig.UPGRADE_TIME * 1000.0)}
	_sync_slots()
	p.notify("Hand-in done: back in %d seconds" % int(GameConfig.UPGRADE_TIME))


## Host: the player picked an upgrade, so the weapon / gear comes back out (called by WaveManager).
func srv_give_back(p: Player) -> void:
	var slot_data := _slots.get(p.peer_id, {}) as Dictionary
	if slot_data.is_empty():
		return
	_slots.erase(p.peer_id)
	if int(slot_data["w"]) < 0:
		p.srv_give_back_gear()
	else:
		p.weapons.give_weapon.rpc(int(slot_data["w"]))
	_sync_slots()


static func find_by_index(tree: SceneTree, i: int) -> Interactable:
	for n in tree.get_nodes_in_group("interactables"):
		if (n as Interactable).index == i:
			return n as Interactable
	return null


# --- host --------------------------------------------------------------------------------------------------

func srv_reset() -> void:
	_hold.clear()
	_spent.clear()
	_cool.clear()
	if not _slots.is_empty() and is_inside_tree():
		_slots.clear()
		_sync_slots()
	_slots.clear()


func _physics_process(delta: float) -> void:
	_animate(delta)
	if not multiplayer.is_server():
		return
	for peer in _slots.keys(): # whoever left takes nothing with them
		if Net.get_player(peer) == null:
			_slots.erase(peer)
			_sync_slots()
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
			var drawn := roll_support(p)
			if drawn == &"" or not wm.srv_spend(GameConfig.BOX_COST):
				return
			var label := _apply_support(p, drawn)
			fx_box.rpc(label)
			p.notify("You got: %s!" % label)
		Kind.WALL_WEAPON:
			var widx := _weapon_index(p)
			if widx < 0 or p.weapons.owned[widx] or not wm.srv_spend(_price()):
				return
			p.weapons.give_weapon.rpc(widx)
			fx_shop.rpc()
			p.notify("You bought the %s!" % p.weapons.list[widx].display_name)
		Kind.WALL_SUPPORT:
			if not _support_useful(p) or not wm.srv_spend(_price()):
				return
			var label := _apply_support(p, item)
			fx_shop.rpc()
			p.notify("You bought: %s" % label)
		Kind.WEAPON_UPGRADER, Kind.ARMOR_UPGRADER:
			var theirs := _slots.get(p.peer_id, {}) as Dictionary
			if theirs.is_empty():
				_srv_hand_in(p, wm)
			elif (int(theirs["ready_at"]) - Time.get_ticks_msec()) <= 0:
				wm.srv_open_collect(p, kind == Kind.ARMOR_UPGRADER, int(theirs["w"]), index)
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
	if _status != null: # what is in the machine: "Hostie: Shotgun 3s", "READY" ...
		var lines := PackedStringArray()
		for peer in _slot_view:
			var pl := Net.get_player(peer)
			var v: Dictionary = _slot_view[peer]
			var left := _slot_left(v)
			var what := "gear" if int(v["w"]) < 0 or pl == null else String(pl.weapons.list[int(v["w"])].display_name)
			lines.append("%s: %s %s" % [pl.player_name if pl != null else "?", what, ("%ds" % ceili(left)) if left > 0.0 else "READY"])
		_status.text = "\n".join(lines)
		_status.visible = not lines.is_empty()
	if _pivot != null and annex != null:
		var pulled := annex.lever_pulled(slot)
		_pivot.rotation.x = lerp_angle(_pivot.rotation.x, deg_to_rad(55.0) if pulled else deg_to_rad(-55.0), minf(delta * 10.0, 1.0))
	if _lid != null:
		_lid_open = maxf(_lid_open - delta * 0.35, 0.0)
		_lid.rotation.x = lerpf(_lid.rotation.x, deg_to_rad(-100.0) * minf(_lid_open * 3.0, 1.0), minf(delta * 12.0, 1.0))
