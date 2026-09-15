class_name ZeeWeaponArtTable
extends RefCounted

## Which mesh each weapon wears, and where it sits in the hand and on the screen.
##
## [b]The only file in the pack that knows a filename.[/b] Everything else names a role
## — [constant ZeeWeaponIds.SNIPER], not `blaster-e.glb` — so a game that wants its own
## art replaces this one table and changes no rule, no loadout and no save. That is the
## same seam dot-fx draws between a catalogue and a scene, and dot-props between a
## definition and a script.
##
## [b]Built in code rather than as `.tres` files, and only because this is a pack.[/b]
## Every class here is `@tool`-annotated and inspector-editable, which is what a game
## with an artist wants. What a reference pack wants is the opposite: one file you can
## read top to bottom and see every weapon's placement with the reasoning beside it.
##
## [b]The roles were assigned from the models' measurements, not from their names.[/b]
## `blaster-a` through `blaster-r` are the order Kenney exported them in and say nothing
## about what they are. Each was measured — length, width, height — and given the role
## its silhouette can carry: the two widest became the revolver and the drum shotgun
## because width reads as a cylinder, the slimmest became the beam weapon, the 1.39 m
## one became the sniper, and the 0.42 m one became the derringer. A role assigned from
## a filename would have been a coin flip eighteen times.

const CHANNEL := "zee.art"

const BLASTERS := "res://assets/blaster-kit/"
const MELEE := "res://assets/melee/"

# --- Shared parts -----------------------------------------------------------
#
# The kit ships these as separate models, which is the whole reason the reload and the
# attachment systems are worth having: a magazine that visibly falls out is readable in
# a way that a gun waggling for two seconds is not.

const CLIP_SMALL := BLASTERS + "clip-small.glb"
const CLIP_LARGE := BLASTERS + "clip-large.glb"
const SCOPE_SMALL := BLASTERS + "scope-small.glb"
const SCOPE_LARGE := BLASTERS + "scope-large-a.glb"
const SCOPE_LARGE_ALT := BLASTERS + "scope-large-b.glb"
const SILENCER_SMALL := BLASTERS + "silencer-small.glb"
const SILENCER_LARGE := BLASTERS + "silencer-larger.glb"

# --- Poses ------------------------------------------------------------------
#
# Five hand positions rather than twenty-seven. A pistol and a derringer are held the
# same way and differ by a centimetre nobody can see, so the offsets live here once and
# a weapon states which family it belongs to. The per-weapon nudges below are then only
# the ones that are actually about that weapon.

const POSE_PISTOL := &"pistol"
const POSE_RIFLE := &"rifle"
const POSE_HEAVY := &"heavy"
const POSE_MELEE := &"melee"
const POSE_THROWN := &"thrown"


## Where a weapon of each pose sits relative to the camera.
##
## [b]Lower and further out than a real weapon would be, and smaller than one.[/b] These
## numbers are not anatomical, and the arithmetic says why. The camera runs at a
## 90-degree vertical field of view, so at 0.5 m the visible world is a metre tall — and
## a 0.7 m rifle held there at life size fills two thirds of the screen. Every game in
## this genre answers that by drawing the view model at a much narrower field of view
## than the world; a single camera cannot do that, so the equivalent is done here by
## shrinking the weapon, which produces the same angular size.
##
## See [method pose_scale] for the other half of the same decision.
static func pose_offset(pose: StringName) -> Vector3:
	match pose:
		POSE_PISTOL:
			return Vector3(0.11, -0.15, -0.42)
		POSE_HEAVY:
			return Vector3(0.13, -0.17, -0.58)
		POSE_MELEE:
			return Vector3(0.17, -0.11, -0.50)
		POSE_THROWN:
			return Vector3(0.11, -0.15, -0.36)
		_:
			return Vector3(0.12, -0.16, -0.48)


## How much a weapon of each pose is shrunk to stand in for a narrower field of view.
##
## [b]Roughly half, and it is not an arbitrary taste.[/b] A weapon drawn at life size
## half a metre from a 90-degree camera spans most of the screen; a watcher reads that as
## the gun being enormous rather than as the camera being wide. Halving it puts a rifle
## at about a third of the screen height, which is where this genre has settled. A heavy
## weapon is shrunk a little further because it is longer to begin with.
static func pose_scale(pose: StringName) -> float:
	match pose:
		POSE_PISTOL:
			return 0.52
		POSE_HEAVY:
			return 0.40
		# [b]Melee is not shrunk the way the blasters are.[/b] A knife is 35 cm long against
		# a rifle's 71, so the correction that puts a rifle at a third of the screen puts a
		# knife at a sixth — behind the hand holding it, which is where the first render
		# had it. Held slightly above life size is what a first-person blade looks like in
		# every game that ships one.
		POSE_MELEE:
			return 1.10
		POSE_THROWN:
			return 0.75
		_:
			return 0.48


## How much a weapon of each pose sways, before its own [member ZeeWeaponArt.weight].
static func pose_weight(pose: StringName) -> float:
	match pose:
		POSE_PISTOL:
			return 0.8
		POSE_HEAVY:
			return 1.5
		POSE_MELEE:
			return 0.7
		POSE_THROWN:
			return 0.6
		_:
			return 1.0


# --- The table --------------------------------------------------------------

## Every weapon's art, keyed by weapon id.
##
## Ordered as [method ZeeWeaponIds.all] is, so the two can be read side by side. The
## self-test asserts they cover exactly the same ids, which is the check that catches a
## weapon added to one file and not the other — the failure mode being an invisible gun
## that works perfectly, which nobody notices on a dedicated server and everybody
## notices in a screenshot.
static func table() -> Dictionary:
	var out: Dictionary = {}

	for art in all():
		out[art.id] = art

	return out


static func all() -> Array[ZeeWeaponArt]:
	return [
		fists(), knife(), shiv(), hatchet(), mallet(), pickaxe(), spade(),
		pistol(), revolver(), machine_pistol(), derringer(),
		smg(), carbine(), rifle(), bullpup(), battle_rifle(), burst_rifle(),
		shotgun(), drum_shotgun(), marksman(),
		sniper(), minigun(), launcher(), beamer(), charge_rifle(),
		frag(), sticky(),
	]


## One weapon's art, or null.
static func get_art(id: StringName) -> ZeeWeaponArt:
	return table().get(id, null)


# --- Melee ------------------------------------------------------------------
#
# [b]Every melee model points along +Y, not +Z.[/b] Kenney's tools stand upright on
# their handle with the origin at the butt, which is exactly where a hand grips them —
# so the grip needs no offset at all, and `model_forward` does the rest. Getting this
# wrong would point the blade at the player's own face, which is the kind of thing that
# is obvious in a picture and invisible in every assertion.

## Nothing in the hands. Always carried, so a player is never holding nothing.
static func fists() -> ZeeWeaponArt:
	var art := _melee(ZeeWeaponIds.FISTS, "")
	art.weight = 0.5
	return art


static func knife() -> ZeeWeaponArt:
	return _melee(ZeeWeaponIds.KNIFE, MELEE + "knife_sharp.glb")


static func shiv() -> ZeeWeaponArt:
	return _melee(ZeeWeaponIds.SHIV, MELEE + "knifeRound_sharp.glb")


static func hatchet() -> ZeeWeaponArt:
	var art := _melee(ZeeWeaponIds.HATCHET, MELEE + "tool-axe.glb")
	# The tools are modelled at about a quarter of a metre, which is a toy hatchet.
	# Scaled up until the head reads at arm's length rather than as a detail.
	art.view_scale *= 1.5
	art.world_scale = 1.5
	art.weight = 1.1
	return art


static func mallet() -> ZeeWeaponArt:
	var art := _melee(ZeeWeaponIds.MALLET, MELEE + "tool-hammer.glb")
	art.view_scale *= 1.7
	art.world_scale = 1.7
	art.weight = 1.4
	return art


static func pickaxe() -> ZeeWeaponArt:
	var art := _melee(ZeeWeaponIds.PICKAXE, MELEE + "tool-pickaxe.glb")
	art.view_scale *= 1.5
	art.world_scale = 1.5
	art.weight = 1.2
	return art


static func spade() -> ZeeWeaponArt:
	var art := _melee(ZeeWeaponIds.SPADE, MELEE + "tool-shovel.glb")
	art.view_scale *= 1.6
	art.world_scale = 1.6
	art.weight = 1.3
	return art


# --- Sidearms ---------------------------------------------------------------

static func pistol() -> ZeeWeaponArt:
	return _blaster(ZeeWeaponIds.PISTOL, "blaster-k", POSE_PISTOL).with_magazine(
		CLIP_SMALL, Vector3(0.0, -0.09, -0.02)
	)


## The widest short model in the kit. Width reads as a cylinder, so it is the revolver.
static func revolver() -> ZeeWeaponArt:
	return _blaster(ZeeWeaponIds.REVOLVER, "blaster-o", POSE_PISTOL)


static func machine_pistol() -> ZeeWeaponArt:
	var art := _blaster(ZeeWeaponIds.MACHINE_PISTOL, "blaster-c", POSE_PISTOL)
	art.with_magazine(CLIP_SMALL, Vector3(0.0, -0.09, 0.0))
	# The silencer's origin is at its own front tip and its body runs backwards, so it
	# is placed a silencer-length in front of the barrel rather than at it.
	art.with_attachment(SILENCER_SMALL, Vector3(0.0, 0.0, 0.482))
	return art


## The smallest model in the kit, at 42 cm.
static func derringer() -> ZeeWeaponArt:
	return _blaster(ZeeWeaponIds.DERRINGER, "blaster-b", POSE_PISTOL)


# --- Primaries --------------------------------------------------------------

static func smg() -> ZeeWeaponArt:
	return _blaster(ZeeWeaponIds.SMG, "blaster-i", POSE_RIFLE).with_magazine(
		CLIP_LARGE, Vector3(0.0, -0.14, 0.02)
	)


static func carbine() -> ZeeWeaponArt:
	return _blaster(ZeeWeaponIds.CARBINE, "blaster-m", POSE_RIFLE).with_magazine(
		CLIP_LARGE, Vector3(0.0, -0.15, 0.0)
	)


static func rifle() -> ZeeWeaponArt:
	return _blaster(ZeeWeaponIds.RIFLE, "blaster-q", POSE_RIFLE).with_magazine(
		CLIP_LARGE, Vector3(0.0, -0.15, 0.0)
	)


## Rear-heavy: this is the one model whose bulk sits behind the grip.
static func bullpup() -> ZeeWeaponArt:
	var art := _blaster(ZeeWeaponIds.BULLPUP, "blaster-r", POSE_RIFLE)
	art.with_magazine(CLIP_LARGE, Vector3(0.0, -0.15, -0.14))
	art.with_attachment(SCOPE_SMALL, Vector3(0.0, 0.24, 0.08))
	return art


static func battle_rifle() -> ZeeWeaponArt:
	return _blaster(ZeeWeaponIds.BATTLE_RIFLE, "blaster-g", POSE_RIFLE).with_magazine(
		CLIP_LARGE, Vector3(0.0, -0.16, 0.0)
	)


static func burst_rifle() -> ZeeWeaponArt:
	return _blaster(ZeeWeaponIds.BURST_RIFLE, "blaster-n", POSE_RIFLE).with_magazine(
		CLIP_LARGE, Vector3(0.0, -0.15, 0.0)
	)


static func shotgun() -> ZeeWeaponArt:
	return _blaster(ZeeWeaponIds.SHOTGUN, "blaster-j", POSE_RIFLE)


## The widest model in the kit, at 24 cm across. A drum, so a drum shotgun.
static func drum_shotgun() -> ZeeWeaponArt:
	return _blaster(ZeeWeaponIds.DRUM_SHOTGUN, "blaster-l", POSE_RIFLE)


static func marksman() -> ZeeWeaponArt:
	var art := _blaster(ZeeWeaponIds.MARKSMAN, "blaster-p", POSE_RIFLE)
	art.with_magazine(CLIP_LARGE, Vector3(0.0, -0.16, -0.02))
	art.with_attachment(SCOPE_SMALL, Vector3(0.0, 0.19, 0.06))
	return art


# --- Heavies ----------------------------------------------------------------

## The longest model at 1.39 m, and the only one whose origin sits at the stock rather
## than at its centre — which is why the muzzle is measured rather than assumed.
static func sniper() -> ZeeWeaponArt:
	var art := _blaster(ZeeWeaponIds.SNIPER, "blaster-e", POSE_HEAVY)
	# [b]Pulled back along its own length, in both views, in the same direction — and
	# scaled with the model.[/b] Its mesh origin is at the stock rather than at the
	# middle, so left alone the whole weapon sits a metre out in front of wherever it is
	# placed. Three things about this line were wrong before a render showed them:
	# -Z is forward so the pull-back is +Z (the world offset had the sign flipped, which
	# the rack showed as the sniper lying across the row in front of it); and the
	# correction is a distance along a model that is drawn at 40% in first person, so a
	# flat 0.42 pulled it four times too far and put the stock 16 cm from the eye.
	art.view_offset += Vector3(0.0, 0.0, 0.42 * art.view_scale)
	art.world_offset += Vector3(0.0, 0.0, 0.42 * art.world_scale)
	art.with_attachment(SCOPE_LARGE, Vector3(0.0, 0.20, 0.55))
	art.weight = 1.8
	return art


static func minigun() -> ZeeWeaponArt:
	var art := _blaster(ZeeWeaponIds.MINIGUN, "blaster-f", POSE_HEAVY)
	art.with_attachment(SILENCER_LARGE, Vector3(0.0, 0.0, 0.938))
	art.weight = 2.0
	return art


## The tallest short model: a drum sitting above the body reads as a grenade launcher.
static func launcher() -> ZeeWeaponArt:
	var art := _blaster(ZeeWeaponIds.LAUNCHER, "blaster-a", POSE_HEAVY)
	art.weight = 1.6
	return art


## The slimmest model in the kit. Nothing about it reads as a magazine, so it is the
## one that does not have one.
static func beamer() -> ZeeWeaponArt:
	var art := _blaster(ZeeWeaponIds.BEAMER, "blaster-h", POSE_RIFLE)
	art.weight = 1.2
	return art


static func charge_rifle() -> ZeeWeaponArt:
	var art := _blaster(ZeeWeaponIds.CHARGE_RIFLE, "blaster-d", POSE_HEAVY)
	art.with_attachment(SCOPE_LARGE_ALT, Vector3(0.0, 0.19, 0.10))
	art.weight = 1.5
	return art


# --- Thrown -----------------------------------------------------------------
#
# The grenades stand on their base with the origin at the bottom, the same as the melee
# tools, so they take the same forward axis.

static func frag() -> ZeeWeaponArt:
	return _thrown(ZeeWeaponIds.FRAG, BLASTERS + "grenade-a.glb")


static func sticky() -> ZeeWeaponArt:
	return _thrown(ZeeWeaponIds.STICKY, BLASTERS + "grenade-b.glb")


# --- Builders ---------------------------------------------------------------

## A blaster: points along +Z, sits at its pose's offset, measures its own muzzle.
static func _blaster(id: StringName, model: String, pose: StringName) -> ZeeWeaponArt:
	var art := ZeeWeaponArt.make(id, BLASTERS + model + ".glb")
	art.model_forward = Vector3.BACK
	art.pose = pose
	art.view_offset = pose_offset(pose)
	art.view_scale = pose_scale(pose)
	art.weight = pose_weight(pose)
	# Held slightly muzzle-in and nose-down, which is what stops a long weapon from
	# looking like it is glued to the edge of the screen.
	art.view_rotation = Vector3(-2.0, -4.0, 0.0)
	return art


## A melee weapon or a tool: points along +Y with the grip on the origin.
static func _melee(id: StringName, model: String) -> ZeeWeaponArt:
	var art := ZeeWeaponArt.make(id, model)
	art.model_forward = Vector3.UP
	art.pose = POSE_MELEE
	art.view_offset = pose_offset(POSE_MELEE)
	art.view_scale = pose_scale(POSE_MELEE)
	art.weight = pose_weight(POSE_MELEE)
	# Carried at an angle rather than pointed straight ahead: a blade aimed at the
	# centre of the screen covers the crosshair.
	# [b]Carried across the view, not pointed down it.[/b] `model_forward` turns the blade
	# onto Godot's forward, which for a gun is exactly right and for a knife means the
	# blade points directly away from the eye — so it draws as its own cross-section, a
	# small disc floating above the hands, which is what the first melee render was.
	# Pitching it up and yawing it inward puts its length across the screen where it can
	# be seen, and keeps it off the crosshair.
	art.view_rotation = Vector3(-72.0, -34.0, 0.0)
	# [b]No world rotation, and the temptation to add one is the trap.[/b] These models
	# stand on their handle along +Y, so it is natural to write a -90 here to lay them
	# down — but `model_forward` has already turned +Y onto -Z by the time this is
	# applied, so a second rotation puts the blade through the floor. The rack render is
	# what caught it: six melee weapons drawn end-on as specks.
	return art


static func _thrown(id: StringName, model: String) -> ZeeWeaponArt:
	var art := ZeeWeaponArt.make(id, model)
	art.model_forward = Vector3.UP
	art.pose = POSE_THROWN
	art.view_offset = pose_offset(POSE_THROWN)
	art.view_scale = pose_scale(POSE_THROWN)
	art.weight = pose_weight(POSE_THROWN)
	art.view_rotation = Vector3(-35.0, 0.0, 0.0)
	return art


# --- Validation -------------------------------------------------------------

## Checks every entry, and that the table covers exactly the ids the pack defines.
##
## [b]Loads no mesh.[/b] It is the boot check, and a dedicated server runs it with the
## whole `assets/` directory absent — so it must be able to say "the launcher has no art
## entry" without being able to say "the launcher's mesh is missing". Whether the files
## are there is [method validate_models]'s question, asked where there is a screen.
static func validate() -> DotResult:
	var built := table()

	for art: ZeeWeaponArt in built.values():
		var res := art.validate()
		if not res.ok:
			return res

	for id in ZeeWeaponIds.all():
		if not built.has(id):
			return DotResult.fail(
				DotError.CODE_INVALID,
				"No art for '%s'. It would work perfectly and draw nothing, " % String(id)
				+ "which is a bug nobody notices on a server and everybody notices "
				+ "in a screenshot.",
				String(id)
			)

	for id: StringName in built.keys():
		if not ZeeWeaponIds.all().has(id):
			return DotResult.fail(
				DotError.CODE_INVALID,
				"Art for '%s', which is not a weapon in this pack." % String(id),
				String(id)
			)

	return DotResult.success(null)


## Checks that every mesh, magazine and attachment actually resolves.
##
## Loads scenes, so this is not the boot check. Run it once where there is a screen, or
## in the self-test. Reports every missing model rather than the first, because the
## usual cause is a whole directory that did not ship.
static func validate_models() -> DotResult:
	var missing: Array[String] = []

	for art: ZeeWeaponArt in all():
		for path in _paths_of(art):
			if not ResourceLoader.exists(path):
				missing.append("%s: %s" % [String(art.id), path])

	if missing.is_empty():
		return DotResult.success(null)

	return DotResult.fail(
		DotError.CODE_IO,
		"%d model(s) are missing: %s" % [missing.size(), ", ".join(missing)]
	)


## Every path one entry refers to: the weapon, its magazine and its attachments.
static func _paths_of(art: ZeeWeaponArt) -> Array[String]:
	var out: Array[String] = []

	if art.has_model():
		out.append(art.model_path)

	if art.has_magazine():
		out.append(art.magazine_path)

	for entry in art.attachments:
		out.append(str(entry.get("path", "")))

	return out


static func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var built := all()
	out.append("weapon art: %d entries" % built.size())

	for art in built:
		out.append("  %-16s %-28s %-7s x%.2f  %d attachment(s)" % [
			String(art.id),
			art.model_path.get_file() if art.has_model() else "(none)",
			String(art.pose),
			art.view_scale,
			art.attachments.size(),
		])

	return out
