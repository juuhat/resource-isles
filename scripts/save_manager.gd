class_name SaveManager
extends RefCounted

# File I/O for the save system. The game state itself is serialized by the data classes
# (WorldData/IslandData/Inventory.to_dict, StatTracker/QuestManager); this layer assembles
# the top-level payload, stamps a version, and writes it atomically.
#
# Format: a single Dictionary written with FileAccess.store_var (binary). store_var is used
# rather than JSON because the world is keyed by Vector2i (terrain, resources, buildings, …),
# which JSON cannot represent as object keys — store_var round-trips Vector2i natively. Reads
# use the default full_objects = false: only Variant-native data is decoded, never script
# instances, so a tampered save can't execute code.

# Each save version has its own file, so a build of the game never discards and overwrites a save
# written by a newer one.
const SAVE_PATH := "user://savegame_v2.sav"
# New saves are written here first, then swapped over SAVE_PATH, so a crash mid-write can
# never corrupt an existing good save (read() falls back to this file if the swap is cut off).
const TEMP_PATH := "user://savegame_v2.sav.tmp"
# Version 1 saves (cells counted per island). Until the game first saves in version 2, read()
# loads one and upgrades it (SaveMigration). The file is never written or deleted here, so older
# builds of the game keep their own save.
const V1_SAVE_PATH := "user://savegame.sav"
const V1_TEMP_PATH := "user://savegame.sav.tmp"

# Bump whenever the on-disk schema changes (enum reordering counts — values are stored as raw
# ints), with a SaveMigration step from the previous version and a new SAVE_PATH.
const SAVE_VERSION := 2

# Set once this run deletes the save (New Game, a check's clean start), so the version 1 file isn't
# loaded in its place.
static var _v1_ignored := false


static func has_save() -> bool:
	return _exists(SAVE_PATH, TEMP_PATH) or (not _v1_ignored and _exists(V1_SAVE_PATH, V1_TEMP_PATH))


static func delete_save() -> void:
	for path in [SAVE_PATH, TEMP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_v1_ignored = true


# Bundle already-serialized state into the versioned top-level payload. Callers pass plain
# data (world, stat values, completed-quest set, the next-island seed counter) so this stays
# decoupled from main.gd's managers.
static func build_payload(
	world: WorldData,
	stat_values: Dictionary,
	completed_quests: Dictionary,
	seed_value: int,
	reference_time: float
) -> Dictionary:
	return {
		version = SAVE_VERSION,
		seed_value = seed_value,
		world = world.to_dict(reference_time),
		stats = stat_values,
		completed_quests = completed_quests,
	}


static func write(payload: Dictionary) -> bool:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		# push_error rather than the Logger autoload: this is a static utility, and autoload
		# singletons aren't reachable from a static function.
		push_error("SaveManager: cannot open %s (err %d)" % [TEMP_PATH, FileAccess.get_open_error()])
		return false
	file.store_var(payload)
	file.close()

	# Atomic-ish swap: only replace the previous save once the new one is fully on disk.
	# (Windows rename won't overwrite an existing file, so the old save is removed first; the
	# brief gap is covered by read()'s fallback to the temp file.)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	var err := DirAccess.rename_absolute(TEMP_PATH, SAVE_PATH)
	if err != OK:
		push_error("SaveManager: rename returned err %d" % err)
		return false
	return true


# Returns the decoded payload, upgraded to SAVE_VERSION, or an empty Dictionary if there is no
# save, it can't be read, it isn't a dictionary, or its version can't be upgraded. Callers treat
# {} as "start a new game". A version 2 save, even an unreadable one, always wins over version 1.
static func read() -> Dictionary:
	var payload := {}
	if _exists(SAVE_PATH, TEMP_PATH):
		payload = _read_file(SAVE_PATH, TEMP_PATH)
	elif not _v1_ignored and _exists(V1_SAVE_PATH, V1_TEMP_PATH):
		payload = _read_file(V1_SAVE_PATH, V1_TEMP_PATH)
	if payload.is_empty():
		return {}

	payload = SaveMigration.upgrade(payload)
	var version := int(payload.get("version", 0))
	if version != SAVE_VERSION:
		push_warning("SaveManager: discarding save, version %d != current %d" % [version, SAVE_VERSION])
		return {}
	return payload


static func _exists(path: String, temp_path: String) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(temp_path)


static func _read_file(path: String, temp_path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		# The swap in write() may have been interrupted after removing the old save but before
		# the rename completed; the freshly written temp file is then the best available copy.
		path = temp_path
		if not FileAccess.file_exists(path):
			return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveManager: cannot open %s (err %d)" % [path, FileAccess.get_open_error()])
		return {}
	var payload: Variant = file.get_var()  # full_objects = false: data only, no script instances
	file.close()

	if typeof(payload) != TYPE_DICTIONARY:
		push_warning("SaveManager: save is not a dictionary; ignoring")
		return {}
	return payload
