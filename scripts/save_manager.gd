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

const SAVE_PATH := "user://savegame.sav"
# New saves are written here first, then swapped over SAVE_PATH, so a crash mid-write can
# never corrupt an existing good save (read() falls back to this file if the swap is cut off).
const TEMP_PATH := "user://savegame.sav.tmp"

# Bump whenever the on-disk schema changes (enum reordering counts — values are stored as raw
# ints). There is no migration path yet: a mismatched save is discarded rather than risk
# loading a half-readable world.
const SAVE_VERSION := 1


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(TEMP_PATH)


static func delete_save() -> void:
	for path in [SAVE_PATH, TEMP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


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


# Returns the decoded payload, or an empty Dictionary if there is no save, it can't be read,
# it isn't a dictionary, or its version doesn't match. Callers treat {} as "start a new game".
static func read() -> Dictionary:
	var path := SAVE_PATH
	if not FileAccess.file_exists(path):
		# The swap in write() may have been interrupted after removing the old save but before
		# the rename completed; the freshly written temp file is then the best available copy.
		path = TEMP_PATH
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
	var version := int((payload as Dictionary).get("version", 0))
	if version != SAVE_VERSION:
		push_warning("SaveManager: discarding save, version %d != current %d" % [version, SAVE_VERSION])
		return {}
	return payload
