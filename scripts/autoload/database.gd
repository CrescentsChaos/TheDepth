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
	"min_depth": 0, "max_depth": 3200, "weight": 10.0, "max_count": 10, "school_size": 1,
	"behavior": "wander", "speed": 70.0, "hp": 1.0,
	"xp": 5, "hunger": 6, "coins": 1, "score": 10,
	"contact_damage": 0.0, "thorns": 0.0, "poison": 0.0, "stun": 0.0,
	"edible": true, "flee_range": 0.0, "aggro_range": 0.0,
	"projectile_damage": 12.0, "sprite": "", "tags": [],
	"sprite_frames": 1, "sprite_fps": 8.0, "sprite_scale": 1.0,
	"sprite_faces_left": false, "sprite_smooth": false, "sprite_autosize": true, "sprite_wiggle": 0.0,
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
