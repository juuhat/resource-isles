class_name ResourceDefinition
extends RefCounted

# Per-resource metadata: the single source of truth for everything that used to be
# duplicated across separate match statements (display name, floating-text color, UI
# icon, lifetime "gathered" stat). One of these lives in ResourceDatabase per
# GameTypes.ResourceType. Add a resource by adding one entry there — nothing else.

var id: int
var display_name: String
# Colour used for this resource's floating mining/spend text.
var color: Color
# UI icon (resource bar, floating text). May be null if no art exists yet.
var icon: Texture2D
# The cumulative "<resource> gathered" Stat, or -1 if this resource has none.
var gathered_stat: int


func _init(
	new_id: int,
	new_display_name: String,
	new_color: Color,
	new_icon: Texture2D,
	new_gathered_stat: int = -1
) -> void:
	id = new_id
	display_name = new_display_name
	color = new_color
	icon = new_icon
	gathered_stat = new_gathered_stat
