@tool
class_name ZeeWeaponRig
extends Node

## One player's weapons: the arsenal, the bash, the view model and the world model,
## driven from one command a tick.
##
## [b]This is the node a game adds, and ideally the only one.[/b] Everything under it is
## wired together here because the wiring is the part every game gets subtly wrong: the
## arsenal has to be simulated before the presentation is updated, the presentation has
## to be skipped during a replay, the bash has to roll back with everything else, and the
## view model has to be told how far through a switch it is by somebody who is counting.
## Four rules, none of them obvious, all of them silent when broken.
##
## [codeblock]
## var outcome := rig.simulate_tick(command, tick)
## for shot in outcome.shots:
##     combat.resolve(shot)          # the game's, on the authority only
## [/codeblock]
##
## [b]The same node runs in all three roles.[/b] A server simulating thirty carriers, a
## client predicting its own, and a client drawing somebody else's are the same code with
## [member role] set differently — because the moment they are three code paths, two of
## them are wrong and nobody notices until a player reports that hit registration feels
## bad. What the role changes is only what is [i]drawn[/i]: a server draws nothing, a
## remote player has no view model, and a local player has both.

const CHANNEL := "zee.rig"

const BASH_BEHAVIOUR := "res://addons/zee_weapons/behaviour/zee_weapon_bash.gd"

## A use happened. Carries the whole outcome, so a listener can tell a swing from a shot.
signal used(outcome: DotWeaponOutcome)

## A bash happened. Separate from [signal used] because it is a different animation, a
## different sound and, for most games, a different statistic.
signal bashed(outcome: DotWeaponOutcome)

## The weapon in hand changed, once the deploy has finished.
signal equipped(id: StringName)

## Which role this rig is playing.
enum Role {
	## The player at this keyboard. Predicts, draws a view model and a world model.
	LOCAL,
	## Somebody else, drawn from replicated state. No prediction, no view model.
	REMOTE,
	## A dedicated server or a headless simulation. Draws nothing at all.
	SERVER,
}

@export_group("Role")

@export var role: Role = Role.LOCAL

## True on the machine that decides. Handed to every context and to the arsenal.
##
## [b]Not the same question as [member role].[/b] A listen server's own player is LOCAL
## and authoritative; a dedicated server is SERVER and authoritative; a client predicting
## itself is LOCAL and is not. Folding the two into one flag is how a client ends up
## resolving its own damage.
@export var authority: bool = false

@export_range(1, 240, 1) var tick_rate: int = 64

@export_group("Content")

## Every weapon this carrier could hold. Left null, the pack's own catalogue is built.
@export var catalogue: DotWeaponCatalogue = null

@export_group("Wiring")

## The arsenal. Left null, the rig creates one as its own child.
@export var arsenal_ref: DotNodeRef = null

## The first-person rig, usually a child of the camera. Ignored unless
## [member role] is [constant Role.LOCAL].
@export var view_model_ref: DotNodeRef = null

## The third-person weapon. Drawn in every role but [constant Role.SERVER].
@export var world_model_ref: DotNodeRef = null

## The player this carrier is, for the origin and the aim direction.
##
## Duck-typed through [DotWeaponPlayerBridge], so this addon names no player class and
## works with a game's own.
@export var player_ref: DotNodeRef = null

@export_group("Rules")

## Whether the alt-fire bash is available at all.
@export var allow_bash: bool = true

# --- State ------------------------------------------------------------------

## The arsenal, once [method setup] has run.
##
## Public because [ZeeWeaponNet] reads it by name, and because a game will want to ask
## it about ammunition for its HUD.
var arsenal: DotWeaponArsenal = null

## Uses so far, for the replication counter. Wraps in [ZeeWeaponNet], not here.
var fire_seq: int = 0

## What the last use was, as a [ZeeWeaponNet] kind number.
var fire_kind: int = ZeeWeaponNet.KIND_NONE

var _view: ZeeViewModel = null
var _world: ZeeWorldModel = null
var _player: Node = null
var _art: Dictionary = {}

var _bash: ZeeWeaponBash = null

## The tick the carrier may next bash on.
var _bash_ready_tick: int = 0

## Tick the current reload started on, and how long one round of it takes. -1 when not
## reloading.
var _reload_started: int = -1
var _reload_ticks: int = 0

## Tick the current switch started on, how long it lasts, and whether it is the holster
## half or the deploy half.
var _switch_started: int = -1
var _switch_ticks: int = 0
var _switch_deploying: bool = false

## Tick a charged weapon's draw started on. -1 when the button is up.
var _charge_started: int = -1

## The weapon the presentation is currently showing, so it is only rebuilt on a change.
var _shown: StringName = &""

## The tick most recently simulated, so a signal handler knows when it fired.
##
## [b]Signals arrive from inside [method DotWeaponArsenal.simulate_tick] and carry no
## tick of their own.[/b] A handler reading a clock instead would be a handler that is
## wrong during a replay, which is where a reload animation would start over on every
## correction.
var _last_tick: int = 0

## Whether the arsenal was mid-switch last tick, so the holster half can be noticed.
var _was_switching: bool = false

var _previous_command: DotWeaponCommand = null
var _replaying: bool = false
var _ready_for_use: bool = false


# --- Lifecycle --------------------------------------------------------------

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if arsenal == null:
		setup()


## Builds everything and validates the catalogue. Safe to call twice.
func setup() -> DotResult:
	if _ready_for_use:
		return DotResult.success(null)

	var res := _resolve_arsenal()
	if not res.ok:
		return res.wrap("The rig could not find or build an arsenal.")

	arsenal.catalogue = catalogue if catalogue != null else ZeeWeaponPack.catalogue()
	arsenal.tick_rate = tick_rate
	arsenal.authority = authority

	var ready_res := arsenal.setup()
	if not ready_res.ok:
		return ready_res

	_art = ZeeWeaponArtTable.table()

	if allow_bash:
		var script: Variant = load(BASH_BEHAVIOUR)
		if script is Script:
			_bash = (script as Script).new()

	_resolve_carrier()
	_resolve_presentation()
	_connect_arsenal()

	_ready_for_use = true
	return DotResult.success(null)


func is_ready() -> bool:
	return _ready_for_use


func _resolve_arsenal() -> DotResult:
	if arsenal_ref != null:
		var found := arsenal_ref.resolve(self)
		if found.ok and found.value is DotWeaponArsenal:
			arsenal = found.value
			return DotResult.success(null)

	arsenal = DotWeaponArsenal.new()
	arsenal.name = "Arsenal"
	add_child(arsenal)
	return DotResult.success(null)


## Who is carrying this, which is NOT presentation and must not be skipped on a server.
##
## [b]This was inside [method _resolve_presentation], behind its `role == SERVER` early
## return, and that made every shot on every dedicated server come out of the world
## origin.[/b] The view model and the world model genuinely are presentation and are
## genuinely right to skip on a server; the player is where [method
## DotWeaponPlayerBridge.context_for] takes the muzzle position and the aim direction from,
## so a null one produces a [DotWeaponContext] holding its defaults — origin
## `(0, 0, 0)`, direction `(0, 0, -1)` — and dot-combat then traces from the middle of the
## map, due north, for every player at once.
##
## Nothing reports it. The weapon fires, the ammunition goes down, the use counter
## increments and replicates, the hit registration runs, and it finds nothing because there
## is nothing where it looked. A game built on this has a showdown in which nobody can be
## shot and every number about it is correct.
##
## Found by mg-smash-copter, whose bots fought each other for twenty rounds and ended every
## single one with exactly two players alive — one per side, a draw, every time. A number
## that is identical every round is a number nothing is deciding.
func _resolve_carrier() -> void:
	if player_ref == null:
		return

	var player := player_ref.resolve(self)

	if player.ok:
		_player = player.value
		return

	# Loud, because a carrier that cannot be found is a carrier that shoots the map.
	DotLog.warn(CHANNEL, "the rig could not find the player carrying it", {
		"why": player.error.message,
		"consequence": "shots resolve from the world origin",
	})


func _resolve_presentation() -> void:
	if role == Role.SERVER:
		return

	if role == Role.LOCAL and view_model_ref != null:
		var view := view_model_ref.resolve(self)
		if view.ok and view.value is ZeeViewModel:
			_view = view.value

	if world_model_ref != null:
		var world := world_model_ref.resolve(self)
		if world.ok and world.value is ZeeWorldModel:
			_world = world.value



func _connect_arsenal() -> void:
	arsenal.reload_started.connect(_on_reload_started)
	arsenal.reload_finished.connect(_on_reload_finished)
	arsenal.switched.connect(_on_switched)


# --- Carrying ---------------------------------------------------------------

## Gives the carrier a weapon, by id.
func give(id: StringName, full: bool = true) -> DotResult:
	if not _ready_for_use:
		return DotResult.fail(DotError.CODE_STATE, "setup() has not been called.")

	return arsenal.give(id, full)


## Gives the carrier everything in the pack. For a test range and a sandbox mode.
func give_everything() -> int:
	var given := 0

	for id in ZeeWeaponIds.all():
		if arsenal.give(id).ok:
			given += 1

	return given


func current_def() -> DotWeaponDef:
	return arsenal.current_def() if arsenal != null else null


func current_art() -> ZeeWeaponArt:
	var def := current_def()
	return _art.get(def.id, null) if def != null else null


# --- The tick ---------------------------------------------------------------

## One tick of one command: the arsenal, then the bash, then the picture.
##
## [param command] is what the player asked for; [param tick] is the tick it happens on.
## [param ctx] is optional — left null, one is built from the player through
## [DotWeaponPlayerBridge], which is what a game with a dot-player player wants.
##
## [b]The order is load-bearing.[/b] The arsenal simulates, then the bash gets its turn
## on the state the arsenal left behind, then the presentation is updated from both. A
## presentation updated first shows the previous tick, and a bash run first can fire
## through a weapon the arsenal was about to holster.
func simulate_tick(
	command: DotWeaponCommand,
	tick: int,
	ctx: DotWeaponContext = null
) -> DotWeaponOutcome:
	if not _ready_for_use:
		return DotWeaponOutcome.nothing("setup() has not been called.")

	_last_tick = tick

	var context := ctx if ctx != null else _context_for(tick)
	context.tick = tick
	context.authority = authority

	_notice_holster(tick)

	var outcome := arsenal.simulate_tick(command, context, _previous_command)

	_notice_switch_end()

	if outcome.used:
		_record_use(outcome)

	var bash_outcome := _advance_bash(command, context, tick)

	if bash_outcome != null and bash_outcome.used:
		_record_use(bash_outcome)
		bashed.emit(bash_outcome)
		outcome = bash_outcome

	_advance_charge(command, tick)
	_update_presentation(tick)

	_previous_command = command.duplicate_command()
	return outcome


## Marks the start of a reconciliation replay.
##
## Everything still simulates; what stops is the drawing. A replay that re-equipped the
## view model would rebuild the weapon's meshes several times a second on every
## correction, and a replay that re-punched the recoil spring would shake the screen
## once per replayed tick.
func begin_replay() -> void:
	_replaying = true
	arsenal.begin_replay()


func end_replay() -> void:
	_replaying = false
	arsenal.end_replay()


func is_replaying() -> bool:
	return _replaying


# --- The bash ---------------------------------------------------------------

## The alt-fire, simulated here because dot-weapon's arsenal routes one button.
##
## See [ZeeWeaponBash] for why that is the arsenal being right rather than incomplete.
## The cooldown lives in [member _bash_ready_tick], travels in [method snapshot] and
## rolls back with everything else, which is what stops a corrected client from bashing
## twice.
func _advance_bash(
	command: DotWeaponCommand, context: DotWeaponContext, tick: int
) -> DotWeaponOutcome:
	if _bash == null or not allow_bash:
		return null

	if not command.just_pressed(DotWeaponCommand.BUTTON_ALT, _previous_command):
		return null

	if arsenal.is_switching() or tick < _bash_ready_tick:
		return null

	var def := arsenal.current_def()

	if not ZeeWeaponBash.can_bash(def):
		return null

	_bash.for_def(def)

	# A bash interrupts a reload, the same as firing does. Unlike firing, it can always
	# afford to: a bash spends nothing, so there is no order-of-operations trap here of
	# the kind that made dot-weapon's `_try_use` check payment before cancelling.
	arsenal.cancel_reload()
	_reload_started = -1

	var outcome := _bash.use(context)

	if outcome.used:
		_bash_ready_tick = tick + maxi(1, outcome.cooldown_ticks)

	return outcome


# --- Presentation -----------------------------------------------------------

## Everything the player sees, from state the simulation has already settled.
##
## [b]Skipped entirely during a replay.[/b] The simulation must re-run after a
## correction; a model rebuild, a recoil punch and a sound must not.
func _update_presentation(tick: int) -> void:
	if _replaying or role == Role.SERVER:
		return

	var def := arsenal.current_def()
	var id := def.id if def != null else &""

	if id != _shown:
		_shown = id
		var art: ZeeWeaponArt = _art.get(id, null)

		if _view != null:
			_view.equip(art)

		if _world != null:
			_world.equip(art)

		equipped.emit(id)

	if _view != null:
		_view.on_deploy(_deploy_fraction(tick))
		_view.on_reload(_reload_fraction(tick))
		_view.on_charge(_charge_fraction(tick, def))

	if _world != null:
		_world.on_switching(arsenal.is_switching())


## Drives the view model's sway and bob from the carrier's motion.
##
## [b]Called on a render frame, not on a tick.[/b] Sway and bob are interpolation
## between ticks and doing them on the tick quantises them to the tick rate, which is the
## same reason dot-player-controller runs its view in `_process`. A game already calling
## the controller's own view each frame calls this beside it.
func drive_view(look: Vector2, speed: float, on_floor: bool, crouched: bool) -> void:
	if _view != null:
		_view.drive(look, speed, on_floor, crouched)


## A landing, for the view model's dip.
func on_landed(impact: float) -> void:
	if _view != null:
		_view.on_landed(impact)


## Everything back to rest: a respawn, a teleport, a correction that moved the carrier.
func on_reset() -> void:
	if _view != null:
		_view.on_reset()


## Hangs the world model off the carrier's character, if they have one.
##
## Duck-typed, and false is not an error — a server has no model and a 2D game has no
## hand.
func attach_world_model(character: Object = null) -> bool:
	if _world == null:
		return false

	var target := character if character != null else _player
	return _world.attach_to(target)


func view_model() -> ZeeViewModel:
	return _view


func world_model() -> ZeeWorldModel:
	return _world


## Where the muzzle is, for an effect. Never for a shot — see
## [method ZeeViewModel.muzzle_transform].
func muzzle_transform() -> Transform3D:
	if _view != null:
		return _view.muzzle_transform()

	if _world != null:
		return _world.muzzle_transform()

	return Transform3D.IDENTITY


# --- Progress -------------------------------------------------------------
#
# [b]Counted here rather than read off the arsenal, and deliberately.[/b] The arsenal
# knows exactly how far through a reload it is and keeps it private, which is correct:
# exposing a fraction would make an animation's needs part of a simulation's public
# interface, and the next game to want a different animation would want a different
# fraction. So the rig listens to the signals the arsenal does emit and counts the ticks
# itself, which costs three integers and forks nothing.

func _deploy_fraction(tick: int) -> float:
	if _switch_started < 0 or _switch_ticks <= 0:
		return 1.0

	var through := clampf(
		float(tick - _switch_started) / float(_switch_ticks), 0.0, 1.0
	)

	# A holster runs the animation down and a deploy runs it back up. One number for
	# both is why this is a fraction rather than a flag.
	return through if _switch_deploying else 1.0 - through


func _reload_fraction(tick: int) -> float:
	if _reload_started < 0 or _reload_ticks <= 0:
		return 0.0

	# Wrapped rather than clamped, so a shell-at-a-time reload plays one animation per
	# shell instead of one stretched across the whole magazine.
	return fposmod(float(tick - _reload_started) / float(_reload_ticks), 1.0)


func _charge_fraction(tick: int, def: DotWeaponDef) -> float:
	if _charge_started < 0 or def == null or not def.is_charged():
		return 0.0

	return def.charge_at(tick - _charge_started)


## Tracks a charged weapon's draw, so the view model can pull the weapon back.
##
## The arsenal has this number and does not publish it, for the reason above.
func _advance_charge(command: DotWeaponCommand, tick: int) -> void:
	var def := arsenal.current_def()

	if def == null or not def.is_charged():
		_charge_started = -1
		return

	var down := command.is_pressed(DotWeaponCommand.BUTTON_ATTACK)

	if down and _charge_started < 0:
		_charge_started = tick
	elif not down:
		_charge_started = -1


## Catches the start of a switch, which no signal announces.
##
## [b][signal DotWeaponArsenal.switched] fires between the holster and the deploy, not
## at the start of the holster.[/b] A rig that waited for it would draw the weapon at
## rest for the whole of the way down and then snap it to the bottom of the screen the
## instant the swap happened — so the holster half is noticed by watching
## [method DotWeaponArsenal.is_switching] go true, on the tick before the arsenal runs.
func _notice_holster(tick: int) -> void:
	var switching := arsenal.is_switching()

	if switching and not _was_switching:
		var carried := arsenal.current()
		_switch_started = tick
		_switch_deploying = false
		_switch_ticks = maxi(1, carried.def.holster_ticks if carried != null else 1)

	_was_switching = switching


## Puts the switch animation away once the arsenal says the switch is over.
##
## Without this the deploy fraction stays pinned at 1.0 from a stale start tick, which
## is correct by accident — until the tick counter wraps or a rollback moves it
## backwards, and then the weapon animates itself back down for no reason.
func _notice_switch_end() -> void:
	if _switch_started >= 0 and not arsenal.is_switching():
		_switch_started = -1
		_was_switching = false


func _on_reload_started(slot: int) -> void:
	var carried := arsenal.slot_at(slot)

	if carried == null:
		return

	_reload_started = _last_tick
	_reload_ticks = maxi(
		1,
		carried.def.reload_ticks if not carried.def.reload_per_round
		else carried.def.reload_start_ticks
	)


func _on_reload_finished(_slot: int, _rounds: int) -> void:
	_reload_started = -1


## The holster half finished and the deploy half began.
##
## [b]The arsenal emits this in the middle of a switch, not at the end of one.[/b]
## Treating it as "the switch is over" leaves the weapon drawn at the bottom of the
## screen until the next switch, which reads as the weapon having disappeared.
func _on_switched(_from: int, to: int) -> void:
	var carried := arsenal.slot_at(to)

	_switch_started = _last_tick
	_switch_deploying = true
	_switch_ticks = maxi(1, carried.def.deploy_ticks if carried != null else 1)


# --- Context ----------------------------------------------------------------

func _context_for(tick: int) -> DotWeaponContext:
	if _player != null:
		var ctx := DotWeaponPlayerBridge.context_for(_player, tick)
		ctx.authority = authority
		return ctx

	var made := DotWeaponContext.new()
	made.tick = tick
	made.authority = authority
	return made


func _record_use(outcome: DotWeaponOutcome) -> void:
	fire_seq += 1
	fire_kind = ZeeWeaponNet.kind_number(outcome.kind)

	if not _replaying:
		used.emit(outcome)

		if _view != null:
			_view.on_used(outcome)

		if _world != null:
			_world.on_fired(outcome.recoil)


# --- Netcode ----------------------------------------------------------------

## Everything that has to travel and everything a rollback has to restore.
##
## [b]The arsenal's snapshot plus the rig's own.[/b] The bash cooldown and the charge are
## simulation state that lives here rather than in the arsenal, so a snapshot carrying
## only the arsenal's half reconciles a correction by handing the player a free bash —
## which is the exact bug dot-weapon's own slot snapshot exists to prevent, one level up.
func snapshot() -> Dictionary:
	return {
		"arsenal": arsenal.snapshot() if arsenal != null else {},
		"bash_ready": _bash_ready_tick,
		"charge_started": _charge_started,
		"fire_seq": fire_seq,
		"fire_kind": fire_kind,
		# [b]The previous command's buttons, and they are simulation state.[/b] The bash,
		# the reload and every semi-automatic weapon are edge-triggered against this, so a
		# snapshot that left it out restores a rig which thinks the alt-fire button was
		# already down — and then refuses the next press, once, silently. The arsenal does
		# not have this problem because it is HANDED the previous command rather than
		# keeping one; the rig keeps one, so the rig has to save it.
		"prev_buttons": _previous_command.buttons if _previous_command != null else 0,
		"prev_slot": _previous_command.slot if _previous_command != null else 0,
	}


func restore(state: Dictionary) -> DotResult:
	if not _ready_for_use:
		return DotResult.fail(DotError.CODE_STATE, "setup() has not been called.")

	var res := arsenal.restore(state.get("arsenal", {}))

	if not res.ok:
		return res

	_bash_ready_tick = int(state.get("bash_ready", 0))
	_charge_started = int(state.get("charge_started", -1))
	fire_seq = int(state.get("fire_seq", fire_seq))
	fire_kind = int(state.get("fire_kind", ZeeWeaponNet.KIND_NONE))

	_previous_command = DotWeaponCommand.new()
	_previous_command.buttons = int(state.get("prev_buttons", 0))
	_previous_command.slot = int(state.get("prev_slot", 0))

	# The switch bookkeeping is presentation only, but it is derived from ticks that have
	# just moved backwards. Left alone it animates a switch that already finished.
	_was_switching = arsenal.is_switching()
	_switch_started = -1
	_reload_started = -1

	return DotResult.success(null)


## Copies this rig's state onto a replicating object. See [ZeeWeaponNet].
func pull_net(target: Object) -> void:
	ZeeWeaponNet.pull(self, target)


# --- Reporting --------------------------------------------------------------

func describe() -> Dictionary:
	return {
		"ready": _ready_for_use,
		"role": Role.keys()[role],
		"authority": authority,
		"showing": String(_shown),
		"fire_seq": fire_seq,
		"bash_ready": _bash_ready_tick,
		"arsenal": arsenal.describe() if arsenal != null else {},
		"view": _view.describe() if _view != null else {},
		"world": _world.describe() if _world != null else {},
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("rig: %s%s, showing %s" % [
		Role.keys()[role],
		" (authority)" if authority else "",
		String(_shown) if _shown != &"" else "(nothing)",
	])

	if arsenal != null:
		out.append_array(arsenal.describe_lines())

	if _view != null:
		out.append_array(_view.describe_lines())

	return out
