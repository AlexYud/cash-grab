class_name WeaponCards
extends RefCounted
## The between-rounds reward cards: what a card can be, how it reads, and how the host rolls three of them for a
## player. A card is {"w": weapon index, "mod": ""} for a weapon the player does not have yet ("" = the weapon itself),
## or {"w": index, "mod": key} for a buff to a weapon they already own.

const OFFER_COUNT := 3

## Buffs. "stat" ones can stack high, "fx" ones are special effects with a few levels. ranged/melee say where they apply.
const MODS := {
	&"dmg": {"name": "Heavy Hitter", "desc": "+20% damage", "max": 5, "ranged": true, "melee": true},
	&"mag": {"name": "Extended Mag", "desc": "+30% magazine size", "max": 4, "ranged": true, "melee": false},
	&"rate": {"name": "Hair Trigger", "desc": "Fires and swings 12% faster", "max": 4, "ranged": true, "melee": true},
	&"knock": {"name": "Heavy Rounds", "desc": "+35% knockback and flinch", "max": 4, "ranged": true, "melee": true},
	&"bleed": {"name": "Bleeding", "desc": "Hits make zombies bleed: 6 damage per second per level for 4 seconds", "max": 3, "ranged": true, "melee": true},
	&"life": {"name": "Vampiric", "desc": "You heal 6% of the damage you deal, per level", "max": 3, "ranged": true, "melee": true},
	&"freeze": {"name": "Frostbite", "desc": "Hits freeze zombies: 25% slower per level for 2.5 seconds", "max": 3, "ranged": true, "melee": true},
	&"spark": {"name": "Static Spark", "desc": "20% chance per level that a hit arcs lightning to 2 more zombies", "max": 3, "ranged": true, "melee": true},
	&"blast": {"name": "Boom Rounds", "desc": "15% chance per level that a hit bursts: area damage and a big shove", "max": 3, "ranged": true, "melee": true},
	&"boing": {"name": "Springy", "desc": "15% chance per level to boing the zombie into the air", "max": 3, "ranged": true, "melee": true},
	&"disco": {"name": "Disco Fever", "desc": "15% chance per level to make the zombie dance for 3 seconds", "max": 3, "ranged": true, "melee": true},
}

const BLURBS := {
	&"pistol": "Reliable, never runs dry. Good with every buff.",
	&"shotgun": "Nine pellets of point-blank trouble.",
	&"yank": "Reels zombies (and friends) in by the collar.",
	&"disco": "Makes zombies dance instead of bite.",
	&"tesla": "Lightning that jumps to three more zombies.",
	&"boing": "Sends everything it hits skyward.",
	&"assault_rifle": "Hold the trigger: 30 rounds of fast automatic fire.",
	&"sniper": "One huge shot. Aim down the sights and go for heads.",
	&"bat": "Huge knockback. Sometimes just flattens them.",
	&"katana": "Lightning-fast slashes that hit up to three zombies.",
	&"axe": "Slow, brutal swing that cleaves a whole crowd.",
}


## Three different weapons, random per player: ones they lack are offered as the weapon itself, ones they own as a buff.
static func roll(weapons: PlayerWeapons) -> Array:
	var pool: Array[int] = []
	for i in weapons.list.size():
		pool.append(i)
	pool.shuffle()
	var out: Array = []
	for i in mini(OFFER_COUNT, pool.size()):
		var idx: int = pool[i]
		if not weapons.owned[idx]:
			out.append({"w": idx, "mod": ""})
		else:
			out.append({"w": idx, "mod": String(_pick_mod(weapons, idx))})
	return out


static func _pick_mod(weapons: PlayerWeapons, idx: int) -> StringName:
	var melee := weapons.list[idx].melee
	var options: Array[StringName] = []
	for k in MODS:
		var m: Dictionary = MODS[k]
		if not (m["melee"] if melee else m["ranged"]):
			continue
		if weapons.mod_level(idx, k) < int(m["max"]):
			options.append(k)
	if options.is_empty():
		return &"dmg"
	return options.pick_random()


static func is_new(offer: Dictionary) -> bool:
	return String(offer["mod"]) == ""


static func title(offer: Dictionary, weapons: PlayerWeapons) -> String:
	var wname: String = weapons.list[int(offer["w"])].display_name
	if is_new(offer):
		return wname
	return "%s: %s" % [wname, MODS[StringName(offer["mod"])]["name"]]


static func tag(offer: Dictionary, weapons: PlayerWeapons) -> String:
	if is_new(offer):
		return "NEW WEAPON"
	var lvl := weapons.mod_level(int(offer["w"]), StringName(offer["mod"])) + 1
	return "UPGRADE  lvl %d" % lvl


static func description(offer: Dictionary, weapons: PlayerWeapons) -> String:
	if is_new(offer):
		return String(BLURBS.get(weapons.list[int(offer["w"])].id, ""))
	return String(MODS[StringName(offer["mod"])]["desc"])
