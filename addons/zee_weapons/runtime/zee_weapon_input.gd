class_name ZeeWeaponInput
extends RefCounted

## Turns what the keyboard and mouse are doing into a [DotWeaponCommand].
##
## [b]The only file in the pack that touches an input device, and it is deliberately the
## only one.[/b] Everything downstream — the rig, the arsenal, every behaviour — is a
## pure function of the command this produces, which is what lets a server re-run a
## client's shot and reach the same answer, and what lets a bot, a replay and a headless
## test drive exactly the same code by building a command by hand.
##
## [b]Sampled on a render frame, consumed on a tick.[/b] A button pressed and released
## between two ticks would be missed entirely by code that read the device on the tick,
## which is the classic dropped-shot bug in every fixed-timestep game. So presses are
## latched here as they arrive and cleared when the command is taken.
##
## [b]Yaw and pitch are copied from the movement command, never sampled again.[/b] Two
## samples of the same mouse a frame apart differ, and a shot fired along an angle the
## movement never had is a shot that leaves the muzzle somewhere the player was not
## looking. [method set_aim] is how that is done.

const CHANNEL := "zee.input"

## The actions this maps, and what they mean. A game that uses different names passes
## its own table to [method make].
const DEFAULT_ACTIONS := {
	&"attack": DotWeaponCommand.BUTTON_ATTACK,
	&"attack_alt": DotWeaponCommand.BUTTON_ALT,
	&"reload": DotWeaponCommand.BUTTON_RELOAD,
	&"use": DotWeaponCommand.BUTTON_USE,
	&"weapon_next": DotWeaponCommand.BUTTON_NEXT,
	&"weapon_previous": DotWeaponCommand.BUTTON_PREVIOUS,
	&"weapon_last": DotWeaponCommand.BUTTON_LAST,
	&"weapon_drop": DotWeaponCommand.BUTTON_DROP,
}

## Slot actions, in slot order. `weapon_slot_1` selects slot 1.
const SLOT_ACTION_PREFIX := "weapon_slot_"

## How many slot actions to look for.
const MAX_SLOTS := 8

## Action name to button bit.
var actions: Dictionary = DEFAULT_ACTIONS.duplicate()

## Buttons held right now, sampled every frame.
var _held: int = 0

## Buttons pressed since the last command was taken, latched so a press between two
## ticks is not lost.
var _latched: int = 0

## Slot requested since the last command was taken. Zero means no change.
var _slot: int = 0

var _yaw: float = 0.0
var _pitch: float = 0.0


static func make(action_table: Dictionary = {}) -> ZeeWeaponInput:
	var input := ZeeWeaponInput.new()

	if not action_table.is_empty():
		input.actions = action_table.duplicate()

	return input


# --- Sampling ---------------------------------------------------------------

## Reads the device. Call once per render frame.
##
## [b]Missing actions are silently skipped[/b], not reported: a game that has no
## `weapon_drop` has simply not implemented dropping, which is a design decision rather
## than a misconfiguration, and a warning per frame per missing action would be the
## noisiest possible way to say so.
func sample() -> void:
	_held = 0

	for action: StringName in actions.keys():
		if not InputMap.has_action(action):
			continue

		var bit := int(actions[action])

		if Input.is_action_pressed(action):
			_held |= bit

		if Input.is_action_just_pressed(action):
			_latched |= bit

	for slot in range(1, MAX_SLOTS + 1):
		var action := StringName(SLOT_ACTION_PREFIX + str(slot))

		if InputMap.has_action(action) and Input.is_action_just_pressed(action):
			_slot = slot


## Where the player is looking, copied from the movement command that tick.
func set_aim(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch


# --- Consuming --------------------------------------------------------------

## The command for this tick, and clears the latches.
##
## [b]Held buttons are OR-ed with latched ones.[/b] A held trigger has to appear every
## tick for an automatic weapon to keep firing, and a tapped one has to appear on the
## tick after the tap even though it is no longer down — so both go in, and the arsenal's
## own edge detection against the previous command sorts out which is which.
func take(max_slots: int = MAX_SLOTS) -> DotWeaponCommand:
	var command := DotWeaponCommand.new()
	command.buttons = _held | _latched
	command.slot = _slot
	command.yaw = _yaw
	command.pitch = _pitch
	command.sanitise(max_slots)

	_latched = 0
	_slot = 0

	return command


## Drops everything held and latched. For a menu opening, a death, a round ending.
##
## [b]Worth calling, because a latch survives losing focus.[/b] A player who presses fire
## and then alt-tabs comes back to a weapon that fires once on the first tick after they
## return, which reads as the game firing by itself.
func clear() -> void:
	_held = 0
	_latched = 0
	_slot = 0


# --- Default bindings -------------------------------------------------------

## Registers bindings for any of the actions above the project does not already define.
##
## [b]Only ever adds, never replaces.[/b] A game that has bound its own `attack` has
## bound it on purpose, and an addon that overwrote it at startup would be an addon that
## silently un-configures the project it is installed into. Returns how many it added.
static func register_default_actions() -> int:
	var bindings := {
		&"attack": [MOUSE_BUTTON_LEFT],
		&"attack_alt": [MOUSE_BUTTON_RIGHT],
		&"reload": [KEY_R],
		&"use": [KEY_E],
		&"weapon_next": [MOUSE_BUTTON_WHEEL_DOWN],
		&"weapon_previous": [MOUSE_BUTTON_WHEEL_UP],
		&"weapon_last": [KEY_Q],
		&"weapon_drop": [KEY_G],
		&"weapon_slot_1": [KEY_1],
		&"weapon_slot_2": [KEY_2],
		&"weapon_slot_3": [KEY_3],
		&"weapon_slot_4": [KEY_4],
		&"weapon_slot_5": [KEY_5],
	}

	var added := 0

	for action: StringName in bindings.keys():
		if InputMap.has_action(action):
			continue

		InputMap.add_action(action)
		added += 1

		for code: int in bindings[action]:
			InputMap.action_add_event(action, _event_for(action, code))

	return added


## Builds the event for a binding, mouse or key.
##
## The mouse bindings and the key bindings share one table above, so which kind a code is
## has to be decided somewhere; deciding it from the action name would break the moment
## somebody rebinds one, so it is decided from the code's own range.
static func _event_for(_action: StringName, code: int) -> InputEvent:
	if code in [
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE,
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
	]:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = code
		return mouse

	var key := InputEventKey.new()
	key.physical_keycode = code
	return key


func describe() -> Dictionary:
	return {
		"held": Array(DotWeaponCommand.button_names(_held)),
		"latched": Array(DotWeaponCommand.button_names(_latched)),
		"slot": _slot,
		"yaw": _yaw,
		"pitch": _pitch,
	}
