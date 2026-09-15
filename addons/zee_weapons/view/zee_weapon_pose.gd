class_name ZeeWeaponPose
extends RefCounted

## Where a first-person weapon actually sits this frame: sway, bob, recoil, deploy,
## reload and charge, as one transform.
##
## [b]Separated from the node on purpose, and the reason is that no assertion can see a
## picture.[/b] Everything about a view model is motion, and motion is one of the two
## things this family has learned it cannot test — so the part that [i]can[/i] be tested
## is pulled out and made into arithmetic with no [Node], no viewport and no clock in
## it. A headless suite can then assert the things that actually break: that a spring
## settles rather than oscillating for ever, that nothing here can produce a NaN, that a
## weapon which has been deployed and holstered a thousand times is where it started.
## Whether it [i]looks[/i] right is still a screenshot's job, and always will be.
##
## [b]Nothing here is part of the netcode contract.[/b] This runs on render frames at
## whatever rate the display does, reads a delta in seconds rather than a tick, and
## never writes to anything the simulation reads. That is the same line dot-player-
## controller draws between its motor and its view, and it is why a player with view bob
## switched off still simulates identically to one who has not.

## How the springs behave. One resource for the whole rig; a weapon scales it by its own
## [member ZeeWeaponArt.weight] rather than carrying its own copy.
class Tunables extends RefCounted:
	## Metres the weapon lags behind a turn, at [member sway_reference] degrees a second.
	var sway_amount: float = 0.035

	## Degrees per second of look movement producing the full sway.
	var sway_reference: float = 220.0

	## How quickly sway catches up, per second. Higher is stiffer.
	var sway_response: float = 9.0

	## Degrees the weapon rolls into a turn.
	var sway_roll: float = 4.0

	## Metres of vertical travel at [member bob_reference] metres a second.
	var bob_amount: float = 0.022

	## Horizontal travel, as a fraction of [member bob_amount]. Slightly more than the
	## vertical, because a figure-of-eight reads as walking and a straight bounce reads
	## as a lift.
	var bob_lateral: float = 1.4

	## Ground speed producing the full bob.
	var bob_reference: float = 6.0

	## Bob cycles per metre travelled.
	##
	## [b]Per metre, not per second.[/b] A bob driven by time keeps bobbing when the
	## player walks into a wall, and slides rather than steps when they slow down.
	var bob_per_metre: float = 0.55

	## How quickly the bob amplitude follows speed, per second.
	var bob_response: float = 7.0

	## Metres the weapon is pushed back per degree of recoil pitch.
	var kick_back: float = 0.012

	## Degrees the weapon pitches up per degree of recoil pitch.
	var kick_pitch: float = 1.6

	## Stiffness of the recoil spring, per second. Higher snaps back faster.
	var kick_response: float = 16.0

	## Damping of the recoil spring. 1 is critical; below 1 overshoots.
	var kick_damping: float = 0.7

	## Metres the weapon drops when fully holstered.
	var holster_drop: float = 0.35

	## Degrees it rolls away as it goes down.
	var holster_roll: float = 55.0

	## Metres it drops at the deepest point of a reload.
	var reload_drop: float = 0.12

	## Degrees it tips over at the deepest point of a reload.
	var reload_tip: float = 32.0

	## Metres it is pulled back at full charge.
	var charge_pull: float = 0.06

	## Metres of dip on a landing, at the controller's own reference speed.
	var landing_dip: float = 0.07

	## How quickly a landing dip recovers, per second.
	var landing_response: float = 8.0


# --- Configuration ----------------------------------------------------------

var tunables := Tunables.new()

## Multiplies sway, bob and kick together. A heavy weapon moves more.
var weight: float = 1.0

# --- State ------------------------------------------------------------------

## Sway, in metres, x right and y up. Lags the look direction.
var _sway := Vector2.ZERO

## Roll from turning, in degrees.
var _roll: float = 0.0

## Distance travelled, in metres. Drives the bob phase.
var _bob_distance: float = 0.0

## Smoothed bob amplitude, 0 to 1.
var _bob_amount: float = 0.0

## Recoil offset in metres (z back) and its velocity.
var _kick: float = 0.0
var _kick_velocity: float = 0.0

## Recoil rotation in degrees (x pitch, y yaw) and its velocity.
var _kick_rotation := Vector2.ZERO
var _kick_rotation_velocity := Vector2.ZERO

## 0 fully holstered, 1 fully deployed.
var _deploy: float = 1.0

## 0 not reloading, 1 at the deepest point.
var _reload: float = 0.0

## 0 to 1, a charged weapon's draw.
var _charge: float = 0.0

## Metres of landing dip left to recover.
var _landing: float = 0.0


static func make(p_weight: float = 1.0) -> ZeeWeaponPose:
	var pose := ZeeWeaponPose.new()
	pose.weight = p_weight
	return pose


# --- Driving ----------------------------------------------------------------

## One render frame.
##
## [param look_delta] is degrees of yaw and pitch this frame, [param speed] is ground
## speed in metres a second, and the rest is posture. Everything is clamped and
## sanitised on the way in, because a single NaN reaching a [Transform3D] makes the
## weapon vanish with no error anywhere — which presents as "the view model broke" and
## takes an hour to trace back to one frame with a zero delta in it.
func advance(
	delta: float,
	look_delta: Vector2,
	speed: float,
	on_floor: bool,
	crouched: bool = false
) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return

	# Capped rather than trusted: a frame after a level load can be a whole second long,
	# and an exponential smoothing step with a one-second delta overshoots past its
	# target and comes back, which reads as the weapon snapping.
	var step := minf(delta, 0.1)

	_advance_sway(step, look_delta)
	_advance_bob(step, speed, on_floor, crouched)
	_advance_kick(step)
	_advance_landing(step)


## Adds recoil. [param recoil] is the pitch and yaw in degrees a behaviour asked for.
##
## [b]An impulse into a spring, not a position.[/b] Setting the offset directly makes
## every shot look identical however fast they come; pushing a spring means a second
## shot arriving before the first has settled stacks on it, which is what makes holding
## the trigger down feel different from tapping it.
func punch(recoil: Vector2) -> void:
	if not is_finite(recoil.x) or not is_finite(recoil.y):
		return

	var scale := maxf(0.1, weight)
	_kick_velocity += recoil.x * tunables.kick_back * scale * 60.0
	_kick_rotation_velocity += Vector2(
		recoil.x * tunables.kick_pitch, recoil.y * tunables.kick_pitch
	) * scale * 60.0


## A landing, with [param impact] the downward speed in metres a second.
func land(impact: float) -> void:
	if not is_finite(impact):
		return
	_landing = minf(
		_landing + absf(impact) / 16.0 * tunables.landing_dip, tunables.landing_dip * 3.0
	)


## Where the switch is: 1 fully in hand, 0 fully out of frame.
func set_deploy(fraction: float) -> void:
	_deploy = clampf(fraction, 0.0, 1.0) if is_finite(fraction) else _deploy


## How far into a reload, 0 to 1.
func set_reload(fraction: float) -> void:
	_reload = clampf(fraction, 0.0, 1.0) if is_finite(fraction) else _reload


## A charged weapon's draw, 0 to 1.
func set_charge(fraction: float) -> void:
	_charge = clampf(fraction, 0.0, 1.0) if is_finite(fraction) else _charge


## Drops every spring to rest. For a respawn, a teleport and a correction.
##
## [b]Called on a teleport, and it matters.[/b] Sway is driven by how far the view moved
## this frame; a teleport moves it a hundred and eighty degrees in one frame, and
## without this the weapon swings right across the screen on arrival.
func reset() -> void:
	_sway = Vector2.ZERO
	_roll = 0.0
	_bob_amount = 0.0
	_kick = 0.0
	_kick_velocity = 0.0
	_kick_rotation = Vector2.ZERO
	_kick_rotation_velocity = Vector2.ZERO
	_landing = 0.0


# --- The result -------------------------------------------------------------

## Everything above, as one transform to apply on top of the weapon's resting place.
func offset() -> Transform3D:
	var holstered := 1.0 - _deploy

	var position := Vector3(
		_sway.x,
		_sway.y - _landing - holstered * tunables.holster_drop - _reload * tunables.reload_drop,
		_kick + _charge * tunables.charge_pull
	)

	position += _bob_offset()

	var basis := Basis.from_euler(Vector3(
		deg_to_rad(_kick_rotation.x + _reload * tunables.reload_tip),
		deg_to_rad(_kick_rotation.y),
		deg_to_rad(_roll + holstered * tunables.holster_roll)
	))

	return Transform3D(basis, position)


## The deploy fraction, for a caller that wants to hide the model entirely at zero.
func deploy_fraction() -> float:
	return _deploy


# --- Internals --------------------------------------------------------------

func _advance_sway(step: float, look_delta: Vector2) -> void:
	var reference := maxf(1.0, tunables.sway_reference)
	# Divided by the step to get degrees a second: the same mouse movement over two
	# frames must produce the same sway as over one, or the weapon sways further at a
	# low frame rate.
	var rate := Vector2(
		look_delta.x / step / reference, look_delta.y / step / reference
	)
	rate.x = clampf(rate.x, -1.0, 1.0)
	rate.y = clampf(rate.y, -1.0, 1.0)

	var scale := tunables.sway_amount * maxf(0.1, weight)
	# Negated: the weapon lags the turn, so turning right leaves it behind on the left.
	var target := Vector2(-rate.x * scale, -rate.y * scale)

	var follow := _smoothing(step, tunables.sway_response)
	_sway = _sway.lerp(target, follow)
	_roll = lerpf(_roll, -rate.x * tunables.sway_roll * maxf(0.1, weight), follow)


func _advance_bob(step: float, speed: float, on_floor: bool, crouched: bool) -> void:
	var ground := maxf(0.0, speed) if is_finite(speed) else 0.0

	# Airborne means no footfalls, so the bob fades out rather than continuing in the
	# air — which is the tell that a bob is driven by a timer rather than by walking.
	var target := 0.0
	if on_floor:
		target = clampf(ground / maxf(0.1, tunables.bob_reference), 0.0, 1.0)
	if crouched:
		target *= 0.45

	_bob_amount = lerpf(
		_bob_amount, target, _smoothing(step, tunables.bob_response)
	)

	# Advanced by distance travelled rather than by time, so the weapon stops bobbing
	# the instant the player stops rather than easing out over half a step, and a player
	# walking into a wall does not bob at all.
	if on_floor:
		_bob_distance += ground * step

	_bob_distance = fposmod(_bob_distance, 1000.0)


func _bob_offset() -> Vector3:
	if _bob_amount <= 0.0001:
		return Vector3.ZERO

	var phase := _bob_distance * tunables.bob_per_metre * TAU
	var scale := tunables.bob_amount * _bob_amount * maxf(0.1, weight)

	# A figure of eight: the lateral term runs at half the vertical's frequency, which
	# is what a walk cycle does — two footfalls per left-right sway.
	return Vector3(
		sin(phase * 0.5) * scale * tunables.bob_lateral,
		absf(sin(phase)) * scale - scale * 0.5,
		0.0
	)


## A damped spring, integrated semi-implicitly.
##
## [b]Semi-implicit rather than explicit Euler[/b] — velocity updated first, then
## position from the new velocity. Explicit Euler adds energy at every step, so a spring
## that should settle instead grows until the weapon is flying around the screen; it
## takes a few seconds of held automatic fire to become obvious and looks like a tuning
## problem rather than an integration one.
func _advance_kick(step: float) -> void:
	var stiffness := tunables.kick_response * tunables.kick_response
	var damping := 2.0 * tunables.kick_damping * tunables.kick_response

	_kick_velocity += (-stiffness * _kick - damping * _kick_velocity) * step
	_kick += _kick_velocity * step

	_kick_rotation_velocity += (
		-stiffness * _kick_rotation - damping * _kick_rotation_velocity
	) * step
	_kick_rotation += _kick_rotation_velocity * step

	# Clamped so that a pathological delta or a stack of impulses in one frame cannot
	# throw the weapon somewhere it can never spring back from.
	_kick = clampf(_kick, -0.5, 0.5)
	_kick_rotation.x = clampf(_kick_rotation.x, -45.0, 45.0)
	_kick_rotation.y = clampf(_kick_rotation.y, -45.0, 45.0)


func _advance_landing(step: float) -> void:
	_landing = move_toward(
		_landing, 0.0, _landing * tunables.landing_response * step + 0.0005
	)


## Frame-rate independent exponential smoothing.
##
## [b]`1 - exp(-rate * dt)`, not `rate * dt`.[/b] The linear form is the one everybody
## writes and it is a different amount of smoothing at 60 fps and at 144, so a weapon
## tuned on one machine sways visibly differently on another.
static func _smoothing(step: float, rate: float) -> float:
	return 1.0 - exp(-maxf(0.0, rate) * step)


func describe() -> Dictionary:
	return {
		"sway": _sway,
		"roll": _roll,
		"bob": _bob_amount,
		"kick": _kick,
		"kick_rotation": _kick_rotation,
		"deploy": _deploy,
		"reload": _reload,
		"charge": _charge,
		"landing": _landing,
		"weight": weight,
	}
