extends Node
## Persistent save data + settings. Stored in user://save.json

const SAVE_PATH := "user://save.json"
const DEFAULTS := {
	"coins": 0,
	"best_score": 0,
	"total_eaten": 0,
	"runs": 0,
	"selected_shark": "reef_shark",
	"fish_unlocked": [],   # creature ids bought via an optional "cost" in creatures.json
	"selected_fish": "",   # non-empty = playing as this creature id instead of a shark
	"unlocked_sharks": ["reef_shark"],
	"upgrades": {},
	"discovered": [],
	"settings": {
		"master_volume": 0.8,
		"fullscreen": false,
		"mouse_steer": true,
		"screen_shake": true,
		"show_hints": true,
	},
}

var data: Dictionary = {}
var pending_page := "main"   # which main-menu page to open next
var _known := {}


func _ready() -> void:
	load_game()


func load_game() -> void:
	data = DEFAULTS.duplicate(true)
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_merge(data, parsed)
	_known.clear()
	for id in data["discovered"]:
		_known[str(id)] = true


func _merge(base: Dictionary, over: Dictionary) -> void:
	for k in over:
		if base.has(k) and base[k] is Dictionary and over[k] is Dictionary:
			_merge(base[k], over[k])
		else:
			base[k] = over[k]


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))


func reset() -> void:
	data = DEFAULTS.duplicate(true)
	_known.clear()
	save_game()


func setting(key: String) -> Variant:
	return data["settings"].get(key, DEFAULTS["settings"].get(key))


func set_setting(key: String, value: Variant) -> void:
	data["settings"][key] = value
	save_game()


func coins() -> int:
	return int(data["coins"])


func spend(amount: int) -> bool:
	if coins() < amount:
		return false
	data["coins"] = coins() - amount
	save_game()
	return true


func upgrade_level(id: String) -> int:
	return int(data["upgrades"].get(id, 0))


func set_upgrade_level(id: String, lv: int) -> void:
	data["upgrades"][id] = lv
	save_game()


func has_shark(id: String) -> bool:
	return id in data["unlocked_sharks"]


func unlock_shark(id: String) -> void:
	if not has_shark(id):
		data["unlocked_sharks"].append(id)
		save_game()


func discover(id: String) -> void:
	if not _known.has(id):
		_known[id] = true
		data["discovered"].append(id)


func is_discovered(id: String) -> bool:
	return _known.has(id)
