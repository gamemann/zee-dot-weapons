@tool
extends EditorPlugin

## Editor entry point for zee-dot-weapons. Registers inspector types only.
##
## [b]No autoloads[/b], the same as every addon in this family and for the same reason:
## a server simulating thirty carriers and a client predicting one are many rigs in one
## process, and a global would make them one. A game places a [ZeeWeaponRig] per player
## and the rig finds what it needs through [DotNodeRef].

const _ICON := "res://icon.svg"

const _TYPES := [
	["ZeeWeaponRig", "Node", "res://addons/zee_weapons/runtime/zee_weapon_rig.gd"],
	["ZeeViewModel", "Node3D", "res://addons/zee_weapons/view/zee_view_model.gd"],
	["ZeeWorldModel", "Node3D", "res://addons/zee_weapons/view/zee_world_model.gd"],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
