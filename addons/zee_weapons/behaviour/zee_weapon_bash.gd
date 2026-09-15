class_name ZeeWeaponBash
extends DotWeaponBehaviour

## Hitting somebody with the weapon you are already holding.
##
## [b]Why this is not a fire mode on [DotWeaponDef].[/b] dot-weapon's arsenal routes
## exactly one button — [constant DotWeaponCommand.BUTTON_ATTACK] — into a behaviour,
## and that is the arsenal being right rather than the arsenal being incomplete: an
## alt-fire is a second, independent state machine with its own cadence, its own
## refusals and its own animation, and folding it into the first one means every weapon
## in every game built on dot-weapon pays for a feature most of them do not have.
##
## So the second state machine lives here and in [ZeeWeaponRig], which owns its
## cooldown, includes it in its snapshot and rolls it back with everything else. The
## addon is not forked and the pack gets its alt-fire — which is the extension point
## working, not a gap in it.
##
## [b]One instance serves every blaster.[/b] A bash has no per-weapon state: the reach
## and the damage come from the definition of whatever is in hand, which is handed in
## through [method for_def] on each use rather than bound once by
## [method DotWeaponBehaviour.setup]. That is the one place this behaviour deliberately
## differs from every other one in the family, and it is why [member def] is re-pointed
## rather than fixed.

const CHANNEL := "zee.bash"

## What a bash does when the weapon in hand says nothing about it.
const DEFAULT_DAMAGE := 40.0
const DEFAULT_REACH := 1.9
const DEFAULT_COOLDOWN := 51

## The arc is narrow and the rays are few, because a bash is a shove rather than a
## sweep. A wide arc would make it better than the knife at the knife's own job.
const ARC_DEGREES := 22.0
const RAYS := 3

## The damage type a bash deals.
##
## [b]Built here rather than taken from the pack's table[/b] so that a bash still deals
## strike damage in a game that supplied its own damage tables and never thought about
## the alt-fire. A game that wants its own assigns this.
var strike_type: DotDamageType = null


## The weapon whose numbers this bash is using, and the damage type it deals.
##
## Re-pointed on every use rather than set once, because the same instance serves
## whatever the carrier happens to be holding.
func for_def(weapon: DotWeaponDef) -> void:
	def = weapon


## Ticks before this weapon may bash again.
##
## Read from the weapon in hand rather than fixed here, so a minigun can be slower to
## bring round than a machine pistol.
func cooldown_for(weapon: DotWeaponDef) -> int:
	if weapon == null:
		return DEFAULT_COOLDOWN
	return maxi(1, weapon.param_int(&"bash_cooldown_ticks", DEFAULT_COOLDOWN))


## Whether a weapon can bash at all.
##
## [b]A melee weapon cannot.[/b] Bashing with a hatchet is swinging a hatchet, and
## giving it a second, worse swing on another button is two buttons doing one thing.
## A weapon with no `bash_damage` in its parameters is one this pack did not mean to
## give a bash to, which is exactly the melee weapons and the grenades.
static func can_bash(weapon: DotWeaponDef) -> bool:
	if weapon == null:
		return false
	return weapon.param_float(&"bash_damage", 0.0) > 0.0


func _use(ctx: DotWeaponContext) -> DotWeaponOutcome:
	var damage := DEFAULT_DAMAGE
	var reach := DEFAULT_REACH
	var type: DotDamageType = null

	if def != null:
		damage = def.param_float(&"bash_damage", DEFAULT_DAMAGE)
		reach = def.param_float(&"bash_reach", DEFAULT_REACH)

	var out := DotWeaponOutcome.of(DotWeaponOutcome.KIND_SWING)

	var shot := DotShot.make(_shot_id(), ctx.entity, ctx.tick, ctx.index)
	shot.origin = ctx.origin
	shot.direction = ctx.direction
	shot.damage = damage
	shot.max_range = reach
	shot.replayed = ctx.replayed
	shot.pellet_count = RAYS
	# Fixed rather than hashed, for the same reason melee is: a swing that scattered
	# differently every time would sometimes miss a target standing still in front of
	# it, which reads as broken rather than as spread.
	shot.fixed_pattern = true
	shot.spread = ARC_DEGREES * 0.5

	type = _strike_type()
	if type != null:
		shot.damage_type = type

	shot.scatter()
	out.add_shot(shot)

	# The cadence is the bash's, not the weapon's: a bash must not put the gun on its
	# own fire cooldown, and the rig applies this rather than the arsenal.
	out.cooldown_ticks = cooldown_for(def)
	# A bash spends no ammunition. Stated rather than left to the definition, because
	# the definition's cost is what a *shot* costs and a bash is not one.
	out.ammo_used = 0
	out.recoil = Vector2(0.8, 0.0)
	out.add_event({"event": "bash", "weapon": String(_shot_id())})

	return out


## The id a bash's damage is billed to.
##
## The weapon's own id rather than a `bash` constant, so a kill feed says which gun was
## used to do it — which is the thing anybody reading a kill feed actually wants.
func _shot_id() -> StringName:
	return def.id if def != null else &"bash"



func _strike_type() -> DotDamageType:
	if strike_type == null:
		strike_type = ZeeWeaponDamage.strike()
	return strike_type


func describe() -> Dictionary:
	var d := super.describe()
	d["bashing_with"] = String(_shot_id())
	d["cooldown"] = cooldown_for(def)
	return d
