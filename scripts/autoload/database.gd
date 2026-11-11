extends Node
## Loads the editable game database from JSON.
##   res://data/<table>.json   - shipped defaults (edit these in the project)
##   user://data/<table>.json  - optional overrides/additions (works in exported builds)
## Each file is a JSON array of objects with a unique "id". Missing fields are
## filled from the DEFAULTS below. Add  "disabled": true  to remove an entry.

const TABLES := ["creatures", "sharks", "biomes", "upgrades"]

const CREATURE_DEFAULTS := {
	"name": "Unknown", "description": "", "length": 24.0, "shape": "fish",
	"color": "#88aacc", "accent": "#ffffff",
	"min_depth": 0, "max_depth": 12000, "weight": 10.0, "habitats": [], "max_count": 10, "school_size": 1,
	"behavior": "wander", "speed": 70.0, "hp": 1.0,
	"xp": 5, "hunger": 6, "coins": 1, "score": 10,
	"contact_damage": 0.0, "thorns": 0.0, "poison": 0.0, "stun": 0.0,
	"edible": true, "flee_range": 0.0, "aggro_range": 0.0,
	"projectile_damage": 12.0, "sprite": "", "tags": [],
	"sprite_frames": 1, "sprite_fps": 8.0, "sprite_scale": 1.0,
	"sprite_faces_left": false, "sprite_smooth": false, "sprite_autosize": true, "sprite_wiggle": 0.0,
	# --- life / AI (see data/DATABASE.md)
	"diet": "none", "eats": [], "prey_ratio": 0.5, "activity": "any", "rest_style": "open",
	"territorial": false, "migrates": false, "leaps": false,
	# --- playable
	"playable": true, "cost": 0, "player": {},
}
const SHARK_DEFAULTS := {
	"name": "Shark", "description": "", "color": "#6f8fa8", "belly": "#e6eef3",
	"length": 70.0, "speed": 300.0, "accel": 900.0, "boost_mult": 1.6,
	"bite_damage": 2.0, "bite_range": 44.0, "max_health": 100.0, "max_hunger": 100.0,
	"hunger_drain": 2.6, "stamina": 100.0, "cost": 0, "stun_resist": 0.0,
	"sprite": "", "sprite_frames": 1, "sprite_fps": 8.0, "sprite_scale": 1.0,
	"sprite_faces_left": false, "sprite_smooth": false, "sprite_autosize": true, "sprite_wiggle": 0.0,
}
const BIOME_DEFAULTS := {
	"name": "Ocean", "min_depth": 0, "max_depth": 99999, "darkness": 0.0,
	"pressure": 0.0, "tint": "#4fc3f7",
}
const UPGRADE_DEFAULTS := {
	"name": "Upgrade", "description": "", "stat": "", "per_level": 0.1,
	"max_level": 5, "base_cost": 100, "cost_growth": 1.5,
}

var creatures: Array = []
var sharks: Array = []
var biomes: Array = []
var upgrades: Array = []
var _creature_idx := {}
var _shark_idx := {}


func _ready() -> void:
	reload()


func reload() -> void:
	SpriteSet.clear_cache()
	creatures = _load_table("creatures", CREATURE_DEFAULTS)
	sharks = _load_table("sharks", SHARK_DEFAULTS)
	biomes = _load_table("biomes", BIOME_DEFAULTS)
	upgrades = _load_table("upgrades", UPGRADE_DEFAULTS)
	biomes.sort_custom(func(a, b): return float(a["min_depth"]) < float(b["min_depth"]))
	_creature_idx.clear()
	for c in creatures:
		_creature_idx[str(c["id"])] = c
	_shark_idx.clear()
	for s in sharks:
		_shark_idx[str(s["id"])] = s
	print("Database: %d creatures, %d sharks, %d biomes, %d upgrades" % [creatures.size(), sharks.size(), biomes.size(), upgrades.size()])


func _load_table(table: String, defaults: Dictionary) -> Array:
	var by_id := {}
	var order: Array = []
	var sources: Array = [_read_json("res://data/%s.json" % table), _read_json("user://data/%s.json" % table)]
	for rows in sources:
		for r in rows:
			if not (r is Dictionary) or not r.has("id"):
				push_warning("Database: entry without 'id' ignored in %s" % table)
				continue
			var id := str(r["id"])
			if bool(r.get("disabled", false)):
				by_id.erase(id)
				order.erase(id)
				continue
			var merged: Dictionary
			if by_id.has(id):
				merged = by_id[id]
			else:
				merged = defaults.duplicate(true)
				order.append(id)
			merged.merge(r, true)
			by_id[id] = merged
	var out: Array = []
	for id in order:
		out.append(by_id[id])
	return out


func _read_json(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Array:
		return parsed
	push_warning("Database: %s is not a valid JSON array" % path)
	return []


func creature(id: String) -> Dictionary:
	return _creature_idx.get(id, {})


func shark(id: String) -> Dictionary:
	if _shark_idx.has(id):
		return _shark_idx[id]
	return sharks[0]


## True for creatures that can be chosen as the player's character.
func is_playable(c: Dictionary) -> bool:
	return bool(c.get("playable", true))


## Everything the player can choose: id -> {kind, def}. Sharks first, then every playable species.
func player_def(kind: String, id: String) -> Dictionary:
	if kind == "fish" and _creature_idx.has(id) and is_playable(_creature_idx[id]):
		return creature_as_player(_creature_idx[id])
	var s := shark(id).duplicate(true)
	s["_kind"] = "sharks"
	s["diet"] = "any"
	s["prey_ratio"] = 2.4
	s["shape"] = "shark"
	s["species_id"] = str(s["id"])
	return s


## The def of whatever the player has selected in the menu.
func selected_def() -> Dictionary:
	var fish := str(Save.data.get("selected_fish", ""))
	if fish != "" and _creature_idx.has(fish) and is_playable(_creature_idx[fish]):
		return player_def("fish", fish)
	return player_def("shark", str(Save.data["selected_shark"]))


## Turns a creature entry into a shark-style player def. The derived numbers keep the
## original shark roughly where it was (length 70 -> bite 2.0, speed 300, health 100) and
## scale smoothly for tiny sardines and huge whales. Any key inside the creature's
## "player" object overrides the derived value, so you can hand-tune one species.
func creature_as_player(c: Dictionary) -> Dictionary:
	var L := float(c["length"])
	var hp := float(c["hp"])
	var spd := float(c["speed"])
	var diet := str(c["diet"])
	var hunts := diet in ["carnivore", "omnivore"]
	var d := {
		"id": str(c["id"]), "species_id": str(c["id"]), "_kind": "creatures",
		"name": str(c["name"]), "description": str(c["description"]),
		"shape": str(c["shape"]), "color": str(c["color"]), "belly": str(c["accent"]),
		"length": L, "diet": diet, "eats": c["eats"], "activity": str(c["activity"]),
		"prey_ratio": float(c["prey_ratio"]) if hunts or diet == "filter" else 0.0,
		"speed": clampf(spd * 2.0 + 40.0, 115.0, 480.0),
		"accel": clampf(700.0 + spd * 2.0 - L * 0.6, 380.0, 1100.0),
		"boost_mult": 1.35 if L > 300.0 else (1.8 if str(c["behavior"]) == "ambush" else 1.6),
		"bite_damage": maxf(L / 35.0, 1.0) * (1.3 if hunts else 1.0),
		"bite_range": maxf(L * 0.62, 20.0),
		"max_health": maxf(60.0, 45.0 + 11.0 * pow(hp, 0.75) + L * 0.15),
		"max_hunger": 100.0,
		"hunger_drain": {"carnivore": 2.6, "omnivore": 2.5, "herbivore": 2.4, "plankton": 2.7, "filter": 2.6, "scavenger": 2.0}.get(diet, 2.5),
		"stamina": 100.0 + clampf(spd - 100.0, 0.0, 100.0) * 0.4,
		"cost": int(c["cost"]), "stun_resist": 0.8 if float(c["stun"]) > 0.0 else 0.0,
		# passive body traits of the species
		"contact_damage": float(c["contact_damage"]), "thorns": float(c["thorns"]),
		"stun": float(c["stun"]), "poison": float(c["poison"]),
		# species that live in the deep are built for it
		"innate_pressure_resist": 0.92 if float(c["min_depth"]) >= 2600.0 else (0.5 if float(c["min_depth"]) >= 900.0 else 0.0),
		"innate_light": 0.6 if float(c["min_depth"]) >= 2600.0 else (0.25 if float(c["min_depth"]) >= 900.0 else 0.0),
		"start_depth": clampf(float(c["min_depth"]) + 200.0, 260.0, 11000.0),
		"start_region": str(c["habitats"][0]) if not (c["habitats"] as Array).is_empty() else "reef",
		"sprite": str(c["sprite"]), "sprite_frames": c["sprite_frames"], "sprite_fps": c["sprite_fps"],
		"sprite_scale": c["sprite_scale"], "sprite_faces_left": c["sprite_faces_left"],
		"sprite_smooth": c["sprite_smooth"], "sprite_autosize": c["sprite_autosize"], "sprite_wiggle": c["sprite_wiggle"],
		"behavior": str(c["behavior"]), "tags": c["tags"],
	}
	var over: Variant = c.get("player", {})
	if over is Dictionary:
		d.merge(over, true)
	return d


## Short text for the character menu: what this species eats.
func diet_text(d: Dictionary) -> String:
	match str(d.get("diet", "none")):
		"any": return "Eats: anything that fits in its jaws"
		"carnivore": return "Eats: smaller fish and sea life"
		"omnivore": return "Eats: algae, plankton and small prey"
		"herbivore": return "Eats: algae on reefs and kelp"
		"plankton": return "Eats: drifting plankton"
		"filter": return "Eats: plankton and tiny fish (filter feeder)"
		"scavenger": return "Eats: carrion and sea-floor debris"
	return "Eats: nothing special"


func biome_at(y: float) -> Dictionary:
	var result: Dictionary = biomes[0] if biomes.size() > 0 else BIOME_DEFAULTS
	for b in biomes:
		if y >= float(b["min_depth"]):
			result = b
	return result


func upgrade_bonus(stat: String) -> float:
	var total := 0.0
	for u in upgrades:
		if str(u["stat"]) == stat:
			total += float(u["per_level"]) * float(Save.upgrade_level(str(u["id"])))
	return total


func upgrade_cost(u: Dictionary, level: int) -> int:
	return int(round(float(u["base_cost"]) * pow(float(u["cost_growth"]), float(level))))


## Copies the shipped JSON files to user://data so they can be edited in exported builds.
func export_defaults() -> void:
	DirAccess.make_dir_recursive_absolute("user://data")
	for t in TABLES:
		var dst := "user://data/%s.json" % t
		if FileAccess.file_exists(dst):
			continue
		var src := FileAccess.open("res://data/%s.json" % t, FileAccess.READ)
		if src == null:
			continue
		var out := FileAccess.open(dst, FileAccess.WRITE)
		if out != null:
			out.store_string(src.get_as_text())
