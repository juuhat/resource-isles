class_name GameLogger
extends Node

signal message_logged(level: int, source: String, message: String, line: String)

enum Level {
	DEBUG,
	INFO,
	WARN,
	ERROR,
}

const LEVEL_NAMES := {
	Level.DEBUG: "DEBUG",
	Level.INFO: "INFO",
	Level.WARN: "WARN",
	Level.ERROR: "ERROR",
}

var minimum_level: int = Level.DEBUG
var include_timestamp := true
var history_limit := 200
var history: Array[String] = []


func debug(message: Variant, source := "") -> void:
	_write(Level.DEBUG, source, str(message))


func info(message: Variant, source := "") -> void:
	_write(Level.INFO, source, str(message))


func warn(message: Variant, source := "") -> void:
	_write(Level.WARN, source, str(message))


func error(message: Variant, source := "") -> void:
	_write(Level.ERROR, source, str(message))


func set_minimum_level(level: int) -> void:
	minimum_level = clampi(level, Level.DEBUG, Level.ERROR)


func set_minimum_level_name(level_name: String) -> void:
	var normalized_name := level_name.strip_edges().to_upper()
	for level in LEVEL_NAMES.keys():
		if LEVEL_NAMES[level] == normalized_name:
			minimum_level = level
			return

	push_warning("Unknown logger level: %s" % level_name)


func clear_history() -> void:
	history.clear()


func _write(level: int, source: String, message: String) -> void:
	if level < minimum_level:
		return

	var line := _format_line(level, source, message)
	_add_to_history(line)
	message_logged.emit(level, source, message, line)

	match level:
		Level.WARN:
			push_warning(line)
		Level.ERROR:
			push_error(line)
		_:
			print(line)


func _format_line(level: int, source: String, message: String) -> String:
	var parts: PackedStringArray = [str(LEVEL_NAMES.get(level, "INFO"))]

	if include_timestamp:
		parts.insert(0, "%.3f" % (Time.get_ticks_msec() / 1000.0))

	if not source.is_empty():
		parts.append(source)

	return "[%s] %s" % [" ".join(parts), message]


func _add_to_history(line: String) -> void:
	history.append(line)

	while history.size() > history_limit:
		history.pop_front()
