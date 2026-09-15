class_name ZeeWeaponNet
extends RefCounted

## What has to travel so that somebody else's weapon looks right on your screen.
##
## [b]dot-weapon already replicates the simulation; this replicates the picture.[/b]
## [DotWeaponNetSync] sends the slot, the magazine and the reserve — everything needed to
## keep a carrier's state correct. None of that tells a watcher that a shot just
## happened, and a watcher who is not told sees a silent gun that never moves. So this
## adds four small fields on top, and a game concatenates the two spec lists.
##
## [b]A counter, not an event.[/b] The obvious design is an RPC per shot, and it is wrong
## in three ways that all show up at once: it needs a reliable channel for something that
## is worthless if it arrives late, it costs a packet per shot per watcher, and it
## desynchronises from the state snapshot it belongs with — so a watcher can see the
## muzzle flash of a weapon the same snapshot says has been holstered. A four-bit counter
## that lives [i]in[/i] the snapshot cannot do any of those: it arrives with the state it
## describes, it costs four bits, and a watcher who missed a snapshot sees the counter
## jump by two and plays one flash instead of two. Missing one flash out of forty in a
## burst nobody can count is the correct amount of wrong.
##
## [b]Ammunition stays owner-only, and that is not a bandwidth decision.[/b] Exact
## magazine and reserve counts are information an opponent should not have; sending them
## to everybody is how a modified client knows when to push. [DotWeaponNetSync] already
## makes that call and this changes none of it — what is added here is public because
## "that player is firing" is something anybody in the room can see anyway.
##
## [b]dot-net is not a dependency and is not named here[/b], the same rule dot-weapon and
## dot-combat both follow: a script that so much as mentions a `class_name` the project
## does not have fails to parse, and takes every script that references it down as well.
## So the bridge lives in the host game and this is everything it would otherwise have
## had to work out.

const CHANNEL := "zee.net"

## Bits in the fire counter. Four is sixteen shots between snapshots, which at 64 Hz is
## a weapon firing at 960 rounds a minute — the fastest thing in the pack is 1100, so a
## watcher of a minigun at full rate can miss one flash in a snapshot they already
## missed. Five bits would fix a case nobody can perceive.
const FIRE_SEQ_BITS := 4
const FIRE_SEQ_WRAP := 1 << FIRE_SEQ_BITS

## Bits for what kind of use it was, so a watcher can tell a swing from a shot and play
## the right animation and the right sound.
const FIRE_KIND_BITS := 3

const KIND_NONE := 0
const KIND_SHOT := 1
const KIND_SWING := 2
const KIND_SPAWN := 3
const KIND_BEAM := 4
const KIND_THROW := 5


## The fields this adds, on top of [method DotWeaponNetSync.specs].
static func specs() -> Array[Dictionary]:
	return [
		{
			"property": &"net_fire_seq",
			"type": "UINT",
			"bits": FIRE_SEQ_BITS,
			"owner_only": false,
			# Never interpolated: it is a counter, and a half-way value between two
			# counts is a shot that did not happen.
			"interpolated": false,
		},
		{
			"property": &"net_fire_kind",
			"type": "UINT",
			"bits": FIRE_KIND_BITS,
			"owner_only": false,
			"interpolated": false,
		},
		{
			"property": &"net_reloading",
			"type": "BOOL",
			"bits": 1,
			"owner_only": false,
			"interpolated": false,
		},
		{
			"property": &"net_switching",
			"type": "BOOL",
			"bits": 1,
			"owner_only": false,
			"interpolated": false,
		},
	]


## Every spec a carrier with weapons needs: dot-weapon's, then these.
##
## The one call a game should make. Concatenating the two lists by hand is the same
## work and is one more place for a game to forget the second half, which presents as
## weapons that are silent for everybody but their owner.
static func all_specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(DotWeaponNetSync.specs())
	out.append_array(specs())
	return out


static func properties() -> Array[StringName]:
	var out: Array[StringName] = []
	for spec in all_specs():
		out.append(spec["property"])
	return out


## Bits one carrier's whole weapon state costs. For a bandwidth estimate.
static func estimated_bits() -> int:
	return (
		DotWeaponNetSync.estimated_bits() + FIRE_SEQ_BITS + FIRE_KIND_BITS + 1 + 1
	)


# --- Sending ----------------------------------------------------------------

## Copies a rig's state onto the replicating object.
##
## Call it on the authority, once per tick, after the arsenal has simulated.
static func pull(rig: Object, target: Object) -> void:
	if rig == null or target == null:
		return

	var arsenal: Variant = rig.get("arsenal")

	if arsenal is DotWeaponArsenal:
		DotWeaponNetSync.pull(arsenal, target)
		target.set(&"net_reloading", (arsenal as DotWeaponArsenal).is_reloading())
		target.set(&"net_switching", (arsenal as DotWeaponArsenal).is_switching())

	target.set(&"net_fire_seq", int(rig.get("fire_seq")) % FIRE_SEQ_WRAP)
	target.set(&"net_fire_kind", int(rig.get("fire_kind")))


# --- Receiving --------------------------------------------------------------

## How many uses happened between two counter readings.
##
## [b]Wrap-aware, and the wrap is the whole reason this is a function.[/b] Subtracting
## the two numbers gives a negative every sixteen shots, and code that treats a negative
## as "nothing happened" makes a weapon go silent for one snapshot out of every sixteen —
## a stutter that is maddening to track down and trivially avoided here.
static func uses_between(previous: int, now: int) -> int:
	var delta := (now - previous) % FIRE_SEQ_WRAP

	if delta < 0:
		delta += FIRE_SEQ_WRAP

	return delta


## Plays whatever a snapshot says happened, on a watcher's copy of somebody's weapon.
##
## [param previous_seq] is what this watcher last saw; the new value is returned, so the
## caller keeps one integer per watched player and this file keeps no state at all —
## which is what lets one static function serve every player in the room.
##
## Returns `{"seq": int, "fired": int, "kind": int}`.
static func apply(
	source: Object, world_model: ZeeWorldModel, previous_seq: int
) -> Dictionary:
	if source == null:
		return {"seq": previous_seq, "fired": 0, "kind": KIND_NONE}

	var seq := int(source.get(&"net_fire_seq"))
	var kind := int(source.get(&"net_fire_kind"))
	var fired := uses_between(previous_seq, seq)

	if world_model != null:
		world_model.on_switching(bool(source.get(&"net_switching")))

		# One kick however many shots arrived in the snapshot. Playing one per shot
		# would put a burst's worth of recoil into a single frame, which reads as the
		# weapon jumping rather than as firing.
		if fired > 0:
			world_model.on_fired(_recoil_for(kind))

	return {"seq": seq, "fired": fired, "kind": kind}


## Which of dot-weapon's outcome kinds a number means, and back.
##
## [b]Numbers on the wire, names in the code.[/b] [member DotWeaponOutcome.kind] is a
## [StringName] precisely so a game can invent a nineteenth kind without editing an addon
## — but a [StringName] is not something to put in a three-bit field, so this is the
## mapping, and a kind this pack does not know travels as [constant KIND_SHOT] rather
## than as nothing. A watcher seeing the wrong animation is better than a watcher seeing
## no animation at all.
static func kind_number(kind: StringName) -> int:
	match kind:
		DotWeaponOutcome.KIND_NONE:
			return KIND_NONE
		DotWeaponOutcome.KIND_SHOT:
			return KIND_SHOT
		DotWeaponOutcome.KIND_SWING:
			return KIND_SWING
		DotWeaponOutcome.KIND_SPAWN:
			return KIND_SPAWN
		DotWeaponOutcome.KIND_BEAM:
			return KIND_BEAM
		DotWeaponOutcome.KIND_THROW:
			return KIND_THROW
		_:
			return KIND_SHOT


static func kind_name(number: int) -> StringName:
	match number:
		KIND_SHOT:
			return DotWeaponOutcome.KIND_SHOT
		KIND_SWING:
			return DotWeaponOutcome.KIND_SWING
		KIND_SPAWN:
			return DotWeaponOutcome.KIND_SPAWN
		KIND_BEAM:
			return DotWeaponOutcome.KIND_BEAM
		KIND_THROW:
			return DotWeaponOutcome.KIND_THROW
		_:
			return DotWeaponOutcome.KIND_NONE


## How much a watcher's copy of the weapon moves for each kind of use.
##
## Approximate on purpose: the real recoil is on the outcome, and the outcome does not
## travel. Sending it would be two more floats per carrier per tick to make a watcher's
## weapon move by an amount they cannot measure.
static func _recoil_for(kind: int) -> Vector2:
	match kind:
		KIND_SWING:
			return Vector2(1.2, 0.0)
		KIND_SPAWN, KIND_THROW:
			return Vector2(2.0, 0.0)
		KIND_BEAM:
			return Vector2(0.05, 0.0)
		_:
			return Vector2(0.6, 0.1)


static func describe(source: Object) -> Dictionary:
	if source == null:
		return {}

	return {
		"slot": int(source.get(&"net_slot")),
		"fire_seq": int(source.get(&"net_fire_seq")),
		"fire_kind": String(kind_name(int(source.get(&"net_fire_kind")))),
		"reloading": bool(source.get(&"net_reloading")),
		"switching": bool(source.get(&"net_switching")),
	}
