class_name ZeeWeaponIds
extends RefCounted

## Every name this pack puts into a shared namespace, in one file.
##
## [b]A weapon id, an ammunition pool and a tag are all strings that two repositories
## have to agree on[/b], and the way that agreement breaks is that one of them spells it
## in a string literal. A game writing `arsenal.give(&"blaster_rifle")` compiles whether
## or not the weapon exists, gives the player nothing, and reports nothing; a game
## writing `arsenal.give(ZeeWeaponIds.RIFLE)` fails to parse the moment the id is
## renamed. So every id lives here and nothing else in this addon spells one.
##
## [b]The ids do not name the model.[/b] `blaster-h.glb` is a filename Kenney chose and
## is meaningless to a player, a server console or a loadout document. The ids below
## name the [i]role[/i] — what the weapon is for — and [ZeeWeaponArtTable] is the only
## file in the pack that knows which mesh a role wears. That is what lets the art be
## swapped for a game's own without touching a rule, a loadout or a save.

# --- Damage types -----------------------------------------------------------

## Anything the blasters fire. Foam darts, in this kit's fiction.
const DAMAGE_DART := &"dart"

## Explosions: the launcher, both grenades, the demolition charge.
const DAMAGE_BLAST := &"blast"

## Melee. Separate from [constant DAMAGE_DART] because armour should stop a dart and
## should not stop a hatchet, and that is one field on the damage type rather than a
## special case in every melee weapon.
const DAMAGE_STRIKE := &"strike"

## The beam weapon. Its own type so a game can make something immune to energy without
## making it immune to bullets.
const DAMAGE_ENERGY := &"energy"

# --- Ammunition pools -------------------------------------------------------
#
# Seven pools rather than twenty-seven, deliberately. A pool per weapon means every pickup
# is useful to exactly one weapon and a player who is out of ammunition stays out; pools
# shared across a family are what makes "there is a dart box over there" a decision.

## The small blasters. Pistols, the machine pistol, the derringer.
const AMMO_LIGHT := &"darts_light"

## The rifle family: carbines, assault rifles, the marksman rifle.
const AMMO_HEAVY := &"darts_heavy"

## Shotguns.
const AMMO_SHELL := &"shells"

## The belt-fed minigun, and nothing else — which is what makes its ammunition a
## resource worth finding rather than a number that tops up with everyone else.
const AMMO_BELT := &"belt"

## The beam weapon and the charge rifle.
const AMMO_CELL := &"cells"

## Anything that leaves the barrel slowly enough to see: the launcher's shells and the
## rocket.
const AMMO_ORDNANCE := &"ordnance"

## Both grenades draw from one pool, so the throwable slot is a budget rather than two
## independent counts. Carrying three frags or two frags and a sticky is then a choice,
## which three of each would not be.
const AMMO_GRENADE := &"grenades"

# --- Tags -------------------------------------------------------------------
#
# What a mode filters on. A rule that names weapon ids has to be edited every time a
# weapon is added; a rule that names a tag does not.

const TAG_SIDEARM := &"sidearm"
const TAG_PRIMARY := &"primary"
const TAG_HEAVY := &"heavy"
const TAG_MELEE := &"melee"
const TAG_THROWN := &"thrown"
const TAG_EXPLOSIVE := &"explosive"
const TAG_SILENCED := &"silenced"
const TAG_SCOPED := &"scoped"
const TAG_ENERGY := &"energy"
const TAG_AUTOMATIC := &"automatic"

# --- Slots ------------------------------------------------------------------
#
# dot-weapon's slots are 1-based integers and it attaches no meaning to them. The
# meaning is this pack's, and it is the layout every shooter in this genre has
# converged on, because it maps to the number keys.

const SLOT_MELEE := 1
const SLOT_SIDEARM := 2
const SLOT_PRIMARY := 3
const SLOT_HEAVY := 4
const SLOT_THROWN := 5

# --- Weapons ----------------------------------------------------------------

## Melee. Always carried, never runs out, and always loses to anything with a barrel.
const FISTS := &"fists"
const KNIFE := &"knife"
const SHIV := &"shiv"
const HATCHET := &"hatchet"
const MALLET := &"mallet"
const PICKAXE := &"pickaxe"
const SPADE := &"spade"

## Sidearms.
const PISTOL := &"pistol"
const REVOLVER := &"revolver"
const MACHINE_PISTOL := &"machine_pistol"
const DERRINGER := &"derringer"

## Primaries.
const SMG := &"smg"
const CARBINE := &"carbine"
const RIFLE := &"rifle"
const BULLPUP := &"bullpup"
const BATTLE_RIFLE := &"battle_rifle"
const BURST_RIFLE := &"burst_rifle"
const SHOTGUN := &"shotgun"
const DRUM_SHOTGUN := &"drum_shotgun"
const MARKSMAN := &"marksman"

## Heavies.
const SNIPER := &"sniper"
const MINIGUN := &"minigun"
const LAUNCHER := &"launcher"
const BEAMER := &"beamer"
const CHARGE_RIFLE := &"charge_rifle"

## Thrown.
const FRAG := &"frag"
const STICKY := &"sticky"

## Every id this pack defines, in catalogue order.
##
## Kept beside the constants rather than derived from them, because a
## [code]const[/code] cannot be enumerated in GDScript and the alternative — a
## dictionary the constants index into — makes every call site one lookup longer to
## read. The self-test asserts this list and the catalogue agree, which is the check
## that catches an id added to one and not the other.
static func all() -> Array[StringName]:
	return [
		FISTS, KNIFE, SHIV, HATCHET, MALLET, PICKAXE, SPADE,
		PISTOL, REVOLVER, MACHINE_PISTOL, DERRINGER,
		SMG, CARBINE, RIFLE, BULLPUP, BATTLE_RIFLE, BURST_RIFLE,
		SHOTGUN, DRUM_SHOTGUN, MARKSMAN,
		SNIPER, MINIGUN, LAUNCHER, BEAMER, CHARGE_RIFLE,
		FRAG, STICKY,
	]


## Every ammunition pool, for a game filling a player up or drawing a HUD.
static func ammo_pools() -> Array[StringName]:
	return [
		AMMO_LIGHT, AMMO_HEAVY, AMMO_SHELL, AMMO_BELT,
		AMMO_CELL, AMMO_ORDNANCE, AMMO_GRENADE,
	]
