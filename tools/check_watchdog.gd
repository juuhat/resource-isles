extends Node

# Keeps a check (an `extends SceneTree` script in tools/) from hanging, and from losing the
# player's save, however it ends.
#
# Install it first thing in the check's _initialize():
#   const CheckWatchdog := preload("res://tools/check_watchdog.gd")
#   CheckWatchdog.install(self)              # or install(self, seconds) for a longer limit
#
# A failed assert() only stops the function it is in, so the check never reached quit() and the
# process idled until something killed it. Use CheckWatchdog.require(condition, message) instead:
# it reports the failing line and quits with exit code 1. Anything else that leaves a check
# stuck (a runtime error, a coroutine that never resumes) is stopped once the time limit passes.
#
# Most checks run the real game, which saves as it plays. The save is copied aside before the
# check starts and put back when the process exits, passed or failed. The copy stays on disk until
# then, so if the process is killed outright, the next check to start restores it first. Run
# checks one at a time: they share the save. (tools/run_checks.ps1 gives each check its own empty
# user:// folder, so there the backup is just a no-op.)

# The slowest check (world_sailing_check) takes about 7 s.
const DEFAULT_SECONDS := 30.0
const BACKUP_PATH := SaveManager.SAVE_PATH + ".check_backup"

static var _active: Node
static var _failure := ""

var _seconds := DEFAULT_SECONDS
var _deadline_msec := 0
var _restored := false


static func install(tree: SceneTree, seconds := DEFAULT_SECONDS) -> void:
	_restore_save()
	var had_save := FileAccess.file_exists(SaveManager.SAVE_PATH)
	var backup := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
	backup.store_var({had_save = had_save, had_temp = FileAccess.file_exists(SaveManager.TEMP_PATH),
		bytes = FileAccess.get_file_as_bytes(SaveManager.SAVE_PATH) if had_save else PackedByteArray()})
	backup.close()

	var watchdog: Node = load("res://tools/check_watchdog.gd").new()
	watchdog.name = "CheckWatchdog"
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog._seconds = seconds
	watchdog._deadline_msec = Time.get_ticks_msec() + int(seconds * 1000.0)
	_active = watchdog
	tree.root.add_child(watchdog)


# Ends the check with exit code 1 if `condition` is false. Unlike assert(), the calling function
# carries on until the frame ends, but the exit code and the last line printed stay a failure.
static func require(condition: bool, message := "") -> void:
	if condition:
		return
	var caller: Dictionary = get_stack()[1] if get_stack().size() > 1 else {}
	_fail("%s (%s:%s)" % [message if message != "" else "Requirement failed",
		caller.get("source", "?"), caller.get("line", "?")])


static func _fail(text: String) -> void:
	if _failure == "":
		_failure = text
	push_error("CHECK FAILED: " + text)
	(Engine.get_main_loop() as SceneTree).quit(1)


# Put the backed-up save back (or remove the check's save if there was none), then drop the backup.
static func _restore_save() -> void:
	if not FileAccess.file_exists(BACKUP_PATH):
		return
	var backup: Dictionary = FileAccess.open(BACKUP_PATH, FileAccess.READ).get_var()
	if backup.get("had_save", false):
		var bytes: PackedByteArray = backup.bytes
		if not FileAccess.file_exists(SaveManager.SAVE_PATH) \
				or FileAccess.get_file_as_bytes(SaveManager.SAVE_PATH) != bytes:
			FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE).store_buffer(bytes)
	elif FileAccess.file_exists(SaveManager.SAVE_PATH):
		DirAccess.remove_absolute(SaveManager.SAVE_PATH)
	# SaveManager.read() falls back to a leftover temp file, so drop one the check left behind.
	if not backup.get("had_temp", false) and FileAccess.file_exists(SaveManager.TEMP_PATH):
		DirAccess.remove_absolute(SaveManager.TEMP_PATH)
	DirAccess.remove_absolute(BACKUP_PATH)


func _process(_delta: float) -> void:
	if _failure == "" and Time.get_ticks_msec() > _deadline_msec:
		_fail("Timed out after %d s" % _seconds)


# The process is exiting (the tree frees its root's children on quit).
func _notification(what: int) -> void:
	if (what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE) and not _restored:
		_restored = true
		_restore_save()
		if _failure != "":
			# The check may have called quit() after the failure; keep the failing exit code.
			(Engine.get_main_loop() as SceneTree).quit(1)
			printerr("CHECK FAILED: " + _failure)
