class_name ZeeWeaponDamage
extends RefCounted

## The four damage types this pack's weapons produce, built in code.
##
## [b]Built once and shared, not built per weapon.[/b] A [DotDamageType] is a document
## describing a rule — how armour behaves, whether hit groups apply, what falloff looks
## like — and twenty-seven weapons that each build their own copy of "dart" are
## twenty-seven places for that rule to drift. [method table] builds them once and every
## weapon in [ZeeWeaponPack] takes a reference.
##
## [b]A game may replace any of them.[/b] Hand [method ZeeWeaponPack.catalogue] your own
## table and the pack's weapons take yours; the ids in [ZeeWeaponIds] are the whole
## contract. That is the seam a game uses to make armour worth more, to turn falloff
## off for an arena mode, or to add a resistance its own characters have.

const CHANNEL := "zee.damage"


## Foam darts. What seventeen of the eighteen blasters send down range.
##
## [b]Falloff exists and the floor is high.[/b] Starting at 30 m and ending at 70 m
## punishes cross-map plinking, and a floor of 0.6 means a long shot is worth taking and
## is not worth spamming. A floor of zero would be the same weapon with a hard range
## limit nobody can see, which players read as the gun being broken.
static func dart() -> DotDamageType:
	var type := DotDamageType.make(ZeeWeaponIds.DAMAGE_DART, "Dart")
	type.armour_share = 0.5
	type.armour_wear = 1.0
	type.falloff_start = 30.0
	type.falloff_end = 70.0
	type.falloff_floor = 0.6
	# A dart cannot hurt the person who fired it. Nothing in the pack reflects one, and
	# a non-zero self scale here would only ever fire on a bug.
	type.self_scale = 0.0
	return type


## Explosions: the launcher, the rocket, both grenades.
static func blast() -> DotDamageType:
	var type := DotDamageType.make(ZeeWeaponIds.DAMAGE_BLAST, "Blast")
	type.armour_share = 0.75
	type.armour_wear = 1.5
	# [b]Hit groups off.[/b] A splash sphere touches whatever hitbox is nearest, and a
	# grenade at somebody's feet landing a headshot because the sphere reached a head
	# box first is damage nobody can explain and nobody can play around.
	type.uses_hit_groups = false
	# Half damage to yourself, which is the number every game with rocket jumping has
	# arrived at independently: enough that the jump costs something, not so much that
	# the mobility is unusable.
	type.self_scale = 0.5
	type.knockback_per_point = 0.35
	return type


## Melee.
##
## [b]Armour barely helps and there is no falloff[/b], because a melee weapon already
## has the shortest range in the game and taking damage off it for distance would be
## charging it twice for the same weakness.
static func strike() -> DotDamageType:
	var type := DotDamageType.make(ZeeWeaponIds.DAMAGE_STRIKE, "Strike")
	type.armour_share = 0.15
	type.armour_wear = 0.5
	type.self_scale = 0.0
	return type


## The beam and the charge rifle.
##
## Shares the dart's armour behaviour and has no falloff at all: a beam that weakened
## with distance would be a beam whose damage depends on a number the player cannot see,
## and the beam's whole cost is already that it has to be held on a target.
static func energy() -> DotDamageType:
	var type := DotDamageType.make(ZeeWeaponIds.DAMAGE_ENERGY, "Energy")
	type.armour_share = 0.5
	type.armour_wear = 2.0
	type.self_scale = 0.0
	return type


## Every type, keyed by id, built once.
##
## What [method ZeeWeaponPack.catalogue] takes, and what a game overrides an entry of.
static func table() -> Dictionary:
	return {
		ZeeWeaponIds.DAMAGE_DART: dart(),
		ZeeWeaponIds.DAMAGE_BLAST: blast(),
		ZeeWeaponIds.DAMAGE_STRIKE: strike(),
		ZeeWeaponIds.DAMAGE_ENERGY: energy(),
	}


## Every type as a list, for dot-combat's manager, which registers them that way.
static func all() -> Array[DotDamageType]:
	return [dart(), blast(), strike(), energy()]


## One type out of a table, falling back to the pack's own when a game's table omits it.
##
## [b]A missing type is a warning rather than a failure.[/b] A game that supplies three
## of the four has made a mistake worth hearing about, and refusing to build the
## catalogue over it would mean a game cannot adopt the pack one damage type at a time.
static func from(table_in: Dictionary, id: StringName) -> DotDamageType:
	var found: Variant = table_in.get(id, null)

	if found is DotDamageType:
		return found

	DotLog.warn(
		CHANNEL,
		"no damage type supplied for '%s'; using the pack's own" % String(id),
		{"supplied": table_in.keys().size()}
	)

	return table()[id]
