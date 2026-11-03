class_name ArmorCards
extends RefCounted
## The armor upgrader's cards. Your gear gains chaotic effects that trigger when zombies hit you; like weapons the
## list never ends: unlearned effects first, then another level of one you have or a plain stat.
## A card is {"gear": true, "mod": key, "lvl": the level it would reach}.

const KEYS: Array[StringName] = [&"thorns", &"anchor", &"springy", &"shock", &"funky", &"stink", &"mend", &"rage", &"ghost", &"plate", &"pad"]

const MODS := {
	&"thorns": {"name": "Thorns", "kind": "fx", "desc": "Zombies that hit you get hurt back: 12 damage per level and a shove"},
	&"anchor": {"name": "Lead Boots", "kind": "fx", "desc": "Knockback hits you 40% less per level (level 3: you cannot be knocked back)"},
	&"springy": {"name": "Bouncy Castle", "kind": "fx", "desc": "25% chance per level that whoever hits you is boinged into the air"},
	&"shock": {"name": "Static Cling", "kind": "fx", "desc": "Getting hit zaps the zombies around you with lightning (14 damage per level)"},
	&"funky": {"name": "Funky Fresh", "kind": "fx", "desc": "Getting hit makes the zombies around you dance for 1.5 seconds per level"},
	&"stink": {"name": "Stink Cloud", "kind": "fx", "desc": "Zombies near you move 12% slower per level (up to 60%)"},
	&"mend": {"name": "Slurpee", "kind": "fx", "desc": "You slowly heal: 0.5 health per second per level"},
	&"rage": {"name": "Hot Head", "kind": "fx", "desc": "After you get hit your weapons do +30% damage per level for 4 seconds"},
	&"ghost": {"name": "Slippery", "kind": "fx", "desc": "8% chance per level that a hit passes right through you (up to 60%)"},
	&"plate": {"name": "Plating", "kind": "stat", "desc": "+25 maximum armor, and the vest fills up"},
	&"pad": {"name": "Padding", "kind": "stat", "desc": "The vest soaks 5% more of every hit (up to 90%)"},
}


static func roll(levels: Dictionary) -> Array:
	var fresh: Array[StringName] = []
	var buffs: Array[StringName] = []
	for k in KEYS:
		if MODS[k]["kind"] == "fx" and int(levels.get(k, 0)) == 0:
			fresh.append(k)
		else:
			buffs.append(k)
	fresh.shuffle()
	buffs.shuffle()
	var picks: Array[StringName] = []
	for k in fresh:
		if picks.size() < 3:
			picks.append(k)
	for k in buffs:
		if picks.size() < 3:
			picks.append(k)
	var out: Array = []
	for k in picks:
		out.append({"gear": true, "w": -1, "mod": String(k), "lvl": int(levels.get(k, 0)) + 1})
	return out


static func title(card: Dictionary) -> String:
	return String(MODS[StringName(card["mod"])]["name"])


static func tag(card: Dictionary) -> String:
	var fx: bool = MODS[StringName(card["mod"])]["kind"] == "fx"
	var lvl := int(card["lvl"])
	if fx and lvl == 1:
		return "NEW GEAR EFFECT"
	return ("GEAR EFFECT  lvl %d" if fx else "GEAR BUFF  lvl %d") % lvl


static func description(card: Dictionary) -> String:
	return String(MODS[StringName(card["mod"])]["desc"])
