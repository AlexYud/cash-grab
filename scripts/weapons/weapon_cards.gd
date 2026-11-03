class_name WeaponCards
extends RefCounted
## The upgrade cards the weapon upgrader deals: three different additions for the weapon in your hands. Upgrades never
## run out: new special EFFECTS come first (every weapon can learn all of them once); when fewer than three are left
## the rest of the hand is filled with buffs - another level of an effect you own, or a plain stat boost.
## A card is {"w": weapon index, "mod": key, "lvl": the level it would reach}.

const OFFER_COUNT := 3

## kind "fx" = a special effect, "stat" = a plain number. ranged / melee: where it can appear.
const MODS := {
	&"bleed": {"name": "Bleeding", "kind": "fx", "desc": "Hits make zombies bleed: 6 damage per second per level, 4 seconds", "ranged": true, "melee": true},
	&"life": {"name": "Vampiric", "kind": "fx", "desc": "You heal 6% of the damage you deal, per level (up to 60%)", "ranged": true, "melee": true},
	&"freeze": {"name": "Frostbite", "kind": "fx", "desc": "Hits freeze zombies: slower by 20% per level for 2.5 seconds", "ranged": true, "melee": true},
	&"spark": {"name": "Static Spark", "kind": "fx", "desc": "20% chance per level that a hit arcs lightning to more zombies", "ranged": true, "melee": true},
	&"blast": {"name": "Boom Rounds", "kind": "fx", "desc": "15% chance per level that a hit bursts: area damage and a big shove", "ranged": true, "melee": true},
	&"boing": {"name": "Springy", "kind": "fx", "desc": "15% chance per level to boing the zombie into the air", "ranged": true, "melee": true},
	&"disco": {"name": "Disco Fever", "kind": "fx", "desc": "15% chance per level to make the zombie dance for 3 seconds", "ranged": true, "melee": true},
	&"ignite": {"name": "Burning", "kind": "fx", "desc": "Hits set zombies on fire: 5 damage per second per level, and the flames spread to their neighbours", "ranged": true, "melee": true},
	&"pinata": {"name": "Pinata", "kind": "fx", "desc": "Zombies you kill may burst into snacks and cash (25% per level)", "ranged": true, "melee": true},
	&"headhunter": {"name": "Headhunter", "kind": "fx", "desc": "Headshots do +50% more damage per level", "ranged": true, "melee": true},
	&"vortex": {"name": "Black Hole", "kind": "fx", "desc": "12% chance per level that a hit sucks the zombies around it in", "ranged": true, "melee": true},
	&"dmg": {"name": "Heavy Hitter", "kind": "stat", "desc": "+20% damage", "ranged": true, "melee": true},
	&"mag": {"name": "Extended Mag", "kind": "stat", "desc": "+30% magazine size", "ranged": true, "melee": false},
	&"rate": {"name": "Hair Trigger", "kind": "stat", "desc": "Fires and swings 12% faster", "ranged": true, "melee": true},
	&"knock": {"name": "Heavy Hits", "kind": "stat", "desc": "+35% knockback and flinch", "ranged": true, "melee": true},
}


static func applies(key: StringName, melee: bool) -> bool:
	return MODS[key]["melee" if melee else "ranged"]


## Three different cards for weapon `idx`: unlearned effects first, then buffs.
static func roll_upgrade(weapons: PlayerWeapons, idx: int) -> Array:
	var melee := weapons.list[idx].melee
	var fresh: Array[StringName] = []
	var buffs: Array[StringName] = []
	for k in MODS:
		if not applies(k, melee):
			continue
		if MODS[k]["kind"] == "fx" and weapons.mod_level(idx, k) == 0:
			fresh.append(k)
		else:
			buffs.append(k) # a level of an effect you own, or a stat
	fresh.shuffle()
	buffs.shuffle()
	var picks: Array[StringName] = []
	for k in fresh:
		if picks.size() < OFFER_COUNT:
			picks.append(k)
	for k in buffs:
		if picks.size() < OFFER_COUNT:
			picks.append(k)
	var out: Array = []
	for k in picks:
		out.append({"w": idx, "mod": String(k), "lvl": weapons.mod_level(idx, k) + 1})
	return out


static func title(card: Dictionary) -> String:
	return String(MODS[StringName(card["mod"])]["name"])


static func tag(card: Dictionary) -> String:
	var fx: bool = MODS[StringName(card["mod"])]["kind"] == "fx"
	var lvl := int(card["lvl"])
	if fx and lvl == 1:
		return "NEW EFFECT"
	return ("EFFECT  lvl %d" if fx else "BUFF  lvl %d") % lvl


static func description(card: Dictionary) -> String:
	return String(MODS[StringName(card["mod"])]["desc"])
