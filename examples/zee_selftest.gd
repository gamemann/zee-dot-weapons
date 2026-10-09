extends Node

## The headless suite. Run it before believing anything in this repository.
##
## [b]It counts two things, and the second is the one that catches what the first
## cannot.[/b] Sections entered against sections that ran to their last line, and a total
## number of checks. A script error aborts the section it is in and nothing else, and the
## section counter is already satisfied because the section announced itself on the way
## in — so a suite counting only sections reports "12 sections, 0 failed" while eight
## checks never ran. Another project in this family shipped exactly that.
##
## [b]What it cannot see.[/b] Everything about how the weapons look. Whether the sniper
## is held at the right angle, whether the reload reads as a reload, whether the arms are
## in front of the gun rather than through it — no assertion reaches any of that, and
## four bugs in this family were found by looking at a picture that every check had
## passed. `tools/screenshot.sh` is the other half of the test suite and is not optional.

# No CHANNEL: a suite's verdict is its output, and it prints it; it is not a log record.

## Every check this suite makes. A script error aborts the section it is in, and a section
## that aborts after its last `_check` still counts as finished; only a total can see the
## checks that never ran. It was counted and compared with nothing until 2026-09-24.
const CHECKS := 184

var _sections_entered: int = 0
var _sections_finished: int = 0
var _checks: int = 0
var _failures: int = 0
var _section: String = ""


func _ready() -> void:
	print("zee-dot-weapons self-test")
	print("=========================")

	_ids()
	_damage()
	_pack()
	_art()
	_orientation()
	_muzzles()
	_arsenal()
	_bash()
	_pose()
	_pose_stability()
	_recoil()
	_net()
	_rig()
	_rig_carrier()
	_rig_rollback()
	_view_models()
	_aim()
	_effects()
	_input_bindings()

	print("")
	print("%d sections entered, %d finished, %d checks, %d failed" % [
		_sections_entered, _sections_finished, _checks, _failures
	])

	if _sections_entered != _sections_finished:
		print(
			"!! %d section(s) did not reach their last line — a script error aborted "
			% (_sections_entered - _sections_finished)
			+ "one, and its remaining checks never ran."
		)

	if _checks != CHECKS:
		print("!! %d checks ran, %d expected. A section aborted part-way." % [_checks, CHECKS])

	var passed := _failures == 0 and _sections_entered == _sections_finished and _checks == CHECKS

	print("RESULT: %s" % ("PASS" if passed else "FAIL"))

	# Half a second before quitting, for the effects section: a report still playing is
	# held by the audio server until its mix thread lets go, and quitting before it has
	# reports the playback and its stream as leaked at exit. Four frames was the first
	# try and leaked two of each on about half the runs (2026-10-05): the mix thread runs
	# on its own clock, not the frame's, and four headless frames can pass inside one of
	# its periods. Stopping the voice and dropping its stream in ZeeShotFx._exit_tree did
	# not change the rate, so the wait is the fix and it is measured: 0 in 6 runs.
	await get_tree().create_timer(0.5).timeout

	get_tree().quit(0 if passed else 1)


# --- Sections ---------------------------------------------------------------

func _ids() -> void:
	_begin("ids")

	var all := ZeeWeaponIds.all()
	_check("twenty-seven weapons are named", all.size() == 27)

	var seen: Dictionary = {}
	var duplicates := 0

	for id in all:
		_check_quiet("no id is empty", id != &"")
		if seen.has(id):
			duplicates += 1
		seen[id] = true

	_check("no id appears twice", duplicates == 0)
	_check("seven ammunition pools", ZeeWeaponIds.ammo_pools().size() == 7)

	_end()


func _damage() -> void:
	_begin("damage types")

	var table := ZeeWeaponDamage.table()
	_check("four damage types", table.size() == 4)

	for id: StringName in table.keys():
		var type: DotDamageType = table[id]
		_check_quiet("%s has its own id" % String(id), type.id == id)

	_check(
		"a dart does not hurt the person who fired it",
		ZeeWeaponDamage.dart().self_scale == 0.0
	)
	_check(
		"a blast does, at half",
		is_equal_approx(ZeeWeaponDamage.blast().self_scale, 0.5)
	)
	_check(
		"a blast ignores hit groups",
		not ZeeWeaponDamage.blast().uses_hit_groups
	)
	_check(
		"armour barely stops a strike",
		ZeeWeaponDamage.strike().armour_share < 0.25
	)

	# The fallback path: a game supplying an incomplete table still gets a type back.
	var partial := {ZeeWeaponIds.DAMAGE_DART: ZeeWeaponDamage.dart()}
	var fell_back := ZeeWeaponDamage.from(partial, ZeeWeaponIds.DAMAGE_BLAST)
	_check("a missing type falls back rather than returning null", fell_back != null)
	_check(
		"and falls back to the right one",
		fell_back != null and fell_back.id == ZeeWeaponIds.DAMAGE_BLAST
	)

	_end()


func _pack() -> void:
	_begin("the weapon table")

	var catalogue := ZeeWeaponPack.catalogue()
	var res := catalogue.validate()
	_check("the whole catalogue validates: %s" % _why(res), res.ok)
	_check("twenty-seven rows", catalogue.size() == 27)

	# The check that catches an id added to one file and not the other.
	var ids := catalogue.ids()
	var named := ZeeWeaponIds.all()
	named.sort()
	_check(
		"the catalogue and ZeeWeaponIds name exactly the same weapons",
		ids == named
	)

	var behaviours := catalogue.validate_behaviours()
	_check("every behaviour script resolves: %s" % _why(behaviours), behaviours.ok)

	# Every duration is in ticks, so nothing may be fractional or negative.
	var bad_timing := 0
	var no_tuning := 0

	for def in ZeeWeaponPack.weapons():
		if def.use_interval_ticks < 0 or def.deploy_ticks < 0 or def.reload_ticks < 0:
			bad_timing += 1
		if def.tuning == null:
			no_tuning += 1

	_check("no negative durations", bad_timing == 0)
	_check("every weapon carries tuning", no_tuning == 0)

	# The roles have to actually differ, or this is one weapon with twenty-seven skins.
	var damages: Dictionary = {}
	for def in ZeeWeaponPack.weapons():
		var b := def.tuning as DotWeaponBallistics
		if b != null:
			damages[snappedf(b.damage, 0.5)] = true

	_check("at least fifteen distinct damage values", damages.size() >= 15)

	var melee := catalogue.ids_with_tag(ZeeWeaponIds.TAG_MELEE)
	_check("seven melee weapons carry the melee tag", melee.size() == 7)

	var slots := catalogue.ids_in_slot(ZeeWeaponIds.SLOT_THROWN)
	_check("two weapons in the thrown slot", slots.size() == 2)

	_end()


func _art() -> void:
	_begin("the art table")

	var res := ZeeWeaponArtTable.validate()
	_check("every art entry validates: %s" % _why(res), res.ok)

	var models := ZeeWeaponArtTable.validate_models()
	_check("every model, magazine and attachment exists: %s" % _why(models), models.ok)

	var table := ZeeWeaponArtTable.table()
	_check("one art entry per weapon", table.size() == 27)

	# Eighteen blasters, and each must wear a different one — two roles sharing a mesh
	# is a mistake that reads as a missing model rather than as a duplicated one.
	var meshes: Dictionary = {}
	var duplicates := 0

	for art: ZeeWeaponArt in ZeeWeaponArtTable.all():
		if not art.has_model():
			continue
		if meshes.has(art.model_path):
			duplicates += 1
		meshes[art.model_path] = true

	_check("no two weapons wear the same mesh", duplicates == 0)
	_check("twenty-six meshes, one weapon with none", meshes.size() == 26)

	# The fists are the one weapon with no model, and that is on purpose.
	var fists: ZeeWeaponArt = table[ZeeWeaponIds.FISTS]
	_check("the fists have no model", not fists.has_model())

	# A delivered game mounts its copy of the art under `res://dot_cloud/<id>/<version>/`, and
	# `set_asset_root` is how it says so. Armed: with `scene()` loading `path` rather than the
	# resolved one, the load under a root that holds nothing succeeds and the fourth check fails.
	var pistol: ZeeWeaponArt = table[ZeeWeaponIds.PISTOL]
	_check("built in, a path resolves to itself", ZeeModelCache.resolve(pistol.model_path) == pistol.model_path)

	ZeeModelCache.set_asset_root("res://dot_cloud/x/1.0")
	_check(
		"under a root, res://assets/ moves there (and the root gains its slash)",
		ZeeModelCache.resolve("res://assets/a.glb") == "res://dot_cloud/x/1.0/assets/a.glb"
	)
	_check("a path outside res://assets/ is left alone", ZeeModelCache.resolve("res://addons/a.glb") == "res://addons/a.glb")
	_check("a model is looked for under the root, not where the table says", not ZeeModelCache.scene(pistol.model_path).ok)

	ZeeModelCache.set_asset_root("res://")
	_check("putting res:// back finds it again, not the failure", ZeeModelCache.scene(pistol.model_path).ok)

	_end()


func _orientation() -> void:
	_begin("orientation")

	# Every blaster in the kit points along +Z and Godot's forward is -Z. Getting this
	# wrong fires out of the stock, which looks exactly like a netcode problem.
	var blaster := ZeeWeaponArtTable.rifle()
	var pointed := blaster.orientation() * blaster.model_forward.normalized()

	_check(
		"a blaster's +Z barrel ends up pointing along Godot's -Z",
		pointed.is_equal_approx(Vector3.FORWARD)
	)

	# The melee models stand upright on their handle instead.
	var knife := ZeeWeaponArtTable.knife()
	var blade := knife.orientation() * knife.model_forward.normalized()

	_check(
		"a melee weapon's +Y blade ends up pointing along -Z too",
		blade.is_equal_approx(Vector3.FORWARD)
	)

	# The degenerate case: the rotation taking a vector onto its exact opposite has a
	# zero cross product, and an unguarded axis produces a basis full of NaN — which
	# draws nothing at all, with no error anywhere.
	var flipped := ZeeWeaponArt.make(&"test", "")
	flipped.model_forward = Vector3.BACK
	var basis := flipped.orientation()
	var finite := true

	for i in range(3):
		var column := basis[i]
		if not (is_finite(column.x) and is_finite(column.y) and is_finite(column.z)):
			finite = false

	_check("an exactly reversed model produces no NaN", finite)
	_check(
		"and still ends up facing forward",
		(basis * Vector3.BACK).is_equal_approx(Vector3.FORWARD)
	)

	_end()


func _muzzles() -> void:
	_begin("muzzles")

	# blaster-e is the one model in the kit whose origin is at the stock rather than at
	# its centre, so a hand-written offset correct for the other seventeen puts its
	# muzzle somewhere behind the player's ear. Measuring cannot get that wrong.
	var sniper := ZeeWeaponArtTable.sniper()
	var long := ZeeModelCache.muzzle_distance(
		sniper.model_path, sniper.model_forward
	)

	_check(
		"the off-centre model measures its full 1.39 m rather than half of it",
		long > 1.2 and long < 1.6
	)

	# A centred model measures about half its length, which is the other half of the
	# same claim: the measurement follows the mesh rather than a constant.
	var rifle := ZeeWeaponArtTable.rifle()
	var centred := ZeeModelCache.muzzle_distance(rifle.model_path, rifle.model_forward)

	_check(
		"a centred model measures about half its length",
		centred > 0.25 and centred < 0.45
	)

	_check("a muzzle is never behind the origin", long >= 0.0 and centred >= 0.0)

	# Melee "muzzles" are blade tips, which is the reuse that makes reach work.
	var knife := ZeeWeaponArtTable.knife()
	var tip := ZeeModelCache.muzzle_distance(knife.model_path, knife.model_forward)
	_check("a blade measures a tip", tip > 0.1)

	var missing := ZeeModelCache.muzzle_distance("res://nothing/at/all.glb", Vector3.BACK)
	_check("a model that is not there measures zero rather than failing", missing == 0.0)

	var cached := ZeeModelCache.describe()
	_check("the cache measured something", int(cached["measured"]) > 0)

	_end()


func _arsenal() -> void:
	_begin("the arsenal")

	var arsenal := _make_arsenal()
	var res := arsenal.setup()
	_check("an arsenal built on the pack sets up: %s" % _why(res), res.ok)

	var given := 0
	for id in [
		ZeeWeaponIds.KNIFE, ZeeWeaponIds.PISTOL, ZeeWeaponIds.RIFLE,
		ZeeWeaponIds.LAUNCHER, ZeeWeaponIds.FRAG,
	]:
		if arsenal.give(id).ok:
			given += 1

	_check("five weapons across five slots are carried", given == 5)
	_check("the first one given is in hand", arsenal.current() != null)

	# Firing the rifle: hold the trigger and count what comes out.
	arsenal.select(ZeeWeaponIds.SLOT_PRIMARY, 0)
	_run(arsenal, 0, 40, 0)                     # let the deploy finish

	var rifle := arsenal.slot_at(ZeeWeaponIds.SLOT_PRIMARY)
	var before := rifle.magazine
	var shots := _run(arsenal, 40, 100, DotWeaponCommand.BUTTON_ATTACK)

	_check("holding the trigger fires an automatic weapon", shots > 3)
	_check("and spends the magazine", rifle.magazine < before)

	# The bug dot-weapon's CLAUDE.md is loudest about: a held trigger on an empty
	# weapon must not cancel the reload it just started, for ever.
	rifle.magazine = 0

	# Held through less than one reload, so nothing can legitimately come out yet.
	var dry := _run(arsenal, 140, 200, DotWeaponCommand.BUTTON_ATTACK)
	_check("an empty weapon fires nothing while held", dry == 0)

	# Kept held well past the reload. The bug this guards is that a held trigger cancels
	# the reload it just started, every time the cadence comes round, so the magazine
	# never refills — nothing errors and the weapon simply stops working.
	_run(arsenal, 200, 400, DotWeaponCommand.BUTTON_ATTACK)
	_check(
		"and refills anyway, rather than restarting its reload for ever",
		rifle.magazine > 0
	)

	_cleanup(arsenal)
	_end()


func _bash() -> void:
	_begin("the bash")

	_check(
		"a blaster can bash",
		ZeeWeaponBash.can_bash(ZeeWeaponPack.rifle())
	)
	_check(
		"a melee weapon cannot — that would be two buttons doing one thing",
		not ZeeWeaponBash.can_bash(ZeeWeaponPack.hatchet())
	)
	_check(
		"nor can a grenade",
		not ZeeWeaponBash.can_bash(ZeeWeaponPack.frag())
	)
	_check("and neither can nothing at all", not ZeeWeaponBash.can_bash(null))

	var bash := ZeeWeaponBash.new()
	bash.for_def(ZeeWeaponPack.rifle())

	var ctx := DotWeaponContext.make(7, 100, Vector3.ZERO, Vector3.FORWARD)
	var outcome := bash.use(ctx)

	_check("a bash is a swing", outcome.kind == DotWeaponOutcome.KIND_SWING)
	_check("it produces exactly one shot", outcome.shots.size() == 1)
	_check("it spends no ammunition", outcome.ammo_used == 0)
	_check("it sets its own cadence", outcome.cooldown_ticks > 0)
	_check(
		"it reaches about two metres, not two hundred",
		outcome.shots[0].max_range > 1.0 and outcome.shots[0].max_range < 3.0
	)
	_check(
		"it is billed to the weapon, so a kill feed can name it",
		outcome.shots[0].weapon_id == ZeeWeaponIds.RIFLE
	)

	# A behaviour must be a pure function of its context: the same context twice must
	# give the same answer, or a client and a server disagree about what happened.
	var again := bash.use(DotWeaponContext.make(7, 100, Vector3.ZERO, Vector3.FORWARD))
	_check(
		"the same context produces the same damage twice",
		is_equal_approx(again.shots[0].damage, outcome.shots[0].damage)
	)

	_end()


func _pose() -> void:
	_begin("the pose")

	var pose := ZeeWeaponPose.make(1.0)
	var rest := pose.offset()

	_check("at rest it is near the origin", rest.origin.length() < 0.01)

	# A kick is an impulse into a spring, so it must move and then come back.
	pose.punch(Vector2(3.0, 0.5))
	for i in range(3):
		pose.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true)

	var kicked := pose.offset()
	_check("firing moves the weapon", kicked.origin.length() > 0.001)

	for i in range(240):
		pose.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true)

	var settled := pose.offset()
	_check(
		"and four seconds later it has settled back",
		settled.origin.length() < 0.002
	)

	# Bob is driven by distance travelled, not by time, so a player standing still has
	# none however long they stand there.
	var still := ZeeWeaponPose.make(1.0)
	for i in range(120):
		still.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true)

	_check(
		"standing still produces no bob however long you stand",
		still.offset().origin.length() < 0.002
	)

	var walking := ZeeWeaponPose.make(1.0)
	for i in range(120):
		walking.advance(1.0 / 60.0, Vector2.ZERO, 6.0, true)

	_check("walking does produce bob", walking.offset().origin.length() > 0.002)

	# A holstered weapon drops out of frame. The deploy fraction is the whole animation.
	var switching := ZeeWeaponPose.make(1.0)
	switching.set_deploy(0.0)
	_check(
		"fully holstered, the weapon is well below its resting place",
		switching.offset().origin.y < -0.2
	)

	switching.set_deploy(1.0)
	_check(
		"fully deployed, it is back",
		absf(switching.offset().origin.y) < 0.02
	)

	_end()


func _pose_stability() -> void:
	_begin("pose stability")

	# The one integration bug that takes a few seconds of held fire to show up: explicit
	# Euler adds energy at every step, so a spring that should settle grows instead.
	var pose := ZeeWeaponPose.make(2.0)
	var worst := 0.0

	for i in range(2000):
		if i % 4 == 0:
			pose.punch(Vector2(4.0, 1.0))
		pose.advance(1.0 / 64.0, Vector2(9.0, 3.0), 8.0, true)
		worst = maxf(worst, pose.offset().origin.length())

	_check(
		"thirty seconds of held automatic fire does not make the spring explode",
		worst < 1.0
	)

	var final := pose.offset()
	var finite := (
		is_finite(final.origin.x) and is_finite(final.origin.y)
		and is_finite(final.origin.z)
	)
	_check("and produces no NaN", finite)

	# A frame after a level load can be a whole second long. Unclamped, an exponential
	# step with a one-second delta overshoots and comes back, which reads as a snap.
	var hitching := ZeeWeaponPose.make(1.0)
	hitching.advance(3.0, Vector2(400.0, 120.0), 20.0, true)
	var after := hitching.offset()
	_check(
		"a three-second frame does not throw the weapon off the screen",
		after.origin.length() < 0.5
	)

	# Nothing here may produce a NaN, whatever it is handed.
	var abused := ZeeWeaponPose.make(1.0)
	abused.advance(0.0, Vector2.ZERO, 0.0, true)
	abused.advance(-1.0, Vector2.ZERO, 0.0, true)
	abused.punch(Vector2(NAN, NAN))
	abused.land(NAN)
	abused.set_deploy(NAN)
	abused.advance(1.0 / 60.0, Vector2.ZERO, NAN, true)

	var abused_at := abused.offset().origin
	_check(
		"NaN handed in at every entry point never reaches the transform",
		is_finite(abused_at.x) and is_finite(abused_at.y) and is_finite(abused_at.z)
	)

	# Frame-rate independence: the same second of sway at 60 and at 144 must land in
	# roughly the same place, or a weapon tuned on one machine sways wrong on another.
	var slow := ZeeWeaponPose.make(1.0)
	var fast := ZeeWeaponPose.make(1.0)

	for i in range(60):
		slow.advance(1.0 / 60.0, Vector2(2.0, 0.0), 0.0, true)

	for i in range(144):
		fast.advance(1.0 / 144.0, Vector2(2.0 * 60.0 / 144.0, 0.0), 0.0, true)

	var apart := (slow.offset().origin - fast.offset().origin).length()
	_check("sway lands in the same place at 60 fps and at 144", apart < 0.005)

	_end()


func _recoil() -> void:
	_begin("recoil")

	# Every gun's single-shot climb, at its real weight and its real recoil.
	var climbs := {}

	for def: DotWeaponDef in ZeeWeaponPack.weapons():
		var b := def.tuning as DotWeaponBallistics
		if b == null or b.recoil_pitch <= 0.0:
			continue

		var art := ZeeWeaponArtTable.get_art(def.id)
		var pose := ZeeWeaponPose.make(art.weight if art != null else 1.0)
		pose.punch(Vector2(b.recoil_pitch, b.recoil_yaw))

		var peak := 0.0
		for i in range(144):
			pose.advance(1.0 / 144.0, Vector2.ZERO, 0.0, true)
			peak = maxf(peak, (pose.describe()["kick_rotation"] as Vector3).x)

		climbs[def.id] = peak

	var hardest := 0.0
	var softest := INF
	for id in climbs:
		hardest = maxf(hardest, climbs[id])
		softest = minf(softest, climbs[id])

	# Armed: before the curve, one sniper shot climbed 17 degrees and 13 cm, one minigun
	# shot 0.6, and the ratio between them was 28.
	_check(
		"one sniper shot climbs under eight degrees (%.1f)" % climbs[ZeeWeaponIds.SNIPER],
		climbs[ZeeWeaponIds.SNIPER] < 8.0
	)
	_check(
		"the hardest kick is under fifteen times the softest (%.1f / %.1f)" % [hardest, softest],
		hardest / maxf(0.001, softest) < 15.0
	)
	_check(
		"an automatic's kick is big enough to see (smg %.2f)" % climbs[ZeeWeaponIds.SMG],
		climbs[ZeeWeaponIds.SMG] > 0.75
	)

	# The climb asked for is the climb drawn. A semi-implicit step under critical damping
	# bled a third of every kick away, so the number tuned was never the number seen.
	var asked := ZeeWeaponPose.make(1.0).kick_degrees(2.0)
	var drawn: Array[float] = []
	for rate in [144.0, 30.0]:
		var p := ZeeWeaponPose.make(1.0)
		p.punch(Vector2(2.0, 0.0))
		var top := 0.0
		for i in range(int(rate)):
			p.advance(1.0 / rate, Vector2.ZERO, 0.0, true)
			top = maxf(top, (p.describe()["kick_rotation"] as Vector3).x)
		drawn.append(top)
	_check(
		"the climb drawn is the climb asked for, at 144 fps and at 30 (%.2f: %.2f, %.2f)"
		% [asked, drawn[0], drawn[1]],
		absf(drawn[0] - asked) / asked < 0.05 and absf(drawn[1] - asked) / asked < 0.1
	)

	# Armed: the yaw was applied as the behaviour handed it, always positive, so every
	# shot pushed the gun the same way and a held trigger walked it off to one side.
	var sides := ZeeWeaponPose.make(1.0)
	var left := 0
	var right := 0
	for i in range(20):
		var before := (sides.describe()["kick_rotation"] as Vector3).y
		sides.punch(Vector2(0.0, 1.0))
		sides.advance(1.0 / 120.0, Vector2.ZERO, 0.0, true)
		var moved := (sides.describe()["kick_rotation"] as Vector3).y - before
		if moved > 0.0:
			right += 1
		elif moved < 0.0:
			left += 1
		for j in range(60):
			sides.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true)
	_check(
		"a sideways kick goes both ways over twenty shots (%d left, %d right)" % [left, right],
		left >= 4 and right >= 4
	)

	# About the grip: the muzzle rises and the hand stays where it is, rather than the
	# whole weapon being carried up the screen about the eye.
	var grip := Vector3(0.18, -0.2, -0.4)
	var tipped := ZeeWeaponPose.make(1.0)
	tipped.pivot = grip
	tipped.punch(Vector2(3.0, 0.0))
	for i in range(6):
		tipped.advance(1.0 / 144.0, Vector2.ZERO, 0.0, true)
	var at := tipped.offset()
	var muzzle := grip + Vector3(0.0, 0.0, -0.35)
	var rise := (at * muzzle).y - muzzle.y
	var hand := (at * grip).y - grip.y
	_check(
		"the kick tips the muzzle up about the grip (muzzle %+.3f m, grip %+.3f m)" % [rise, hand],
		rise > 0.01 and absf(hand) < 0.005
	)

	var punch := tipped.view_punch()
	var climb := (tipped.describe()["kick_rotation"] as Vector3).x
	_check(
		"the camera takes a fraction of the climb, upward (%.2f of %.2f)" % [punch.x, climb],
		punch.x > 0.0 and punch.x < climb
	)
	for i in range(144):
		tipped.advance(1.0 / 144.0, Vector2.ZERO, 0.0, true)
	_check(
		"and is back inside a second (%.3f)" % tipped.view_punch().length(),
		tipped.view_punch().length() < 0.05
	)

	var still := ZeeWeaponPose.make(1.0)
	still.feel = 0.0
	still.punch(Vector2(3.0, 1.0))
	for i in range(10):
		still.advance(1.0 / 60.0, Vector2(5.0, 2.0), 6.0, true)
	_check(
		"weapon motion turned off is off",
		still.offset().origin.length() < 0.0001 and still.view_punch().length() < 0.0001
	)

	_end()


func _net() -> void:
	_begin("replication")

	var specs := ZeeWeaponNet.all_specs()
	_check("seven replicated properties", specs.size() == 7)

	var names := ZeeWeaponNet.properties()
	_check("the slot comes from dot-weapon", names.has(&"net_slot"))
	_check("the fire counter is this pack's", names.has(&"net_fire_seq"))

	var public := 0
	for spec in specs:
		if not bool(spec["owner_only"]):
			public += 1

	_check(
		"the magazine and the reserve stay owner-only",
		public == 5 and specs.size() - public == 2
	)

	_check("a carrier costs under 40 bits", ZeeWeaponNet.estimated_bits() < 40)

	# The wrap is the whole reason `uses_between` exists: a plain subtraction goes
	# negative every sixteen shots and a weapon goes silent for a snapshot.
	_check("nothing happened", ZeeWeaponNet.uses_between(4, 4) == 0)
	_check("three shots", ZeeWeaponNet.uses_between(4, 7) == 3)
	_check(
		"and three more across the wrap",
		ZeeWeaponNet.uses_between(14, 1) == 3
	)
	_check(
		"a full lap reads as no shots, which is the honest answer",
		ZeeWeaponNet.uses_between(5, 5) == 0
	)

	# Kinds round-trip, and an unknown one becomes a shot rather than nothing: a watcher
	# seeing the wrong animation beats a watcher seeing none.
	for kind in [
		DotWeaponOutcome.KIND_SHOT, DotWeaponOutcome.KIND_SWING,
		DotWeaponOutcome.KIND_SPAWN, DotWeaponOutcome.KIND_BEAM,
		DotWeaponOutcome.KIND_THROW,
	]:
		_check_quiet(
			"%s survives the wire" % String(kind),
			ZeeWeaponNet.kind_name(ZeeWeaponNet.kind_number(kind)) == kind
		)

	_check(
		"a kind this pack has never heard of travels as a shot",
		ZeeWeaponNet.kind_number(&"grappling_hook") == ZeeWeaponNet.KIND_SHOT
	)

	_check(
		"every kind number fits the field",
		ZeeWeaponNet.KIND_THROW < (1 << ZeeWeaponNet.FIRE_KIND_BITS)
	)

	_end()


func _rig() -> void:
	_begin("the rig")

	var rig := _make_rig()
	var res := rig.setup()
	_check("a headless rig sets up: %s" % _why(res), res.ok)

	var given := rig.give_everything()
	_check("every weapon in the pack can be given", given == 27)
	# Twenty-seven given, five carried: a slot holds one weapon, so each `give` in a
	# slot replaces the last. That is dot-weapon's rule and not a bug here, but it is
	# exactly the sort of thing a reader assumes the other way round.
	_check(
		"and five are carried, because a slot holds one weapon",
		rig.arsenal.slots().size() == 5
	)

	_check("something is in hand", rig.current_def() != null)
	_check("and it has art", rig.current_art() != null)

	# A use goes through the arsenal and comes back out.
	rig.arsenal.select(ZeeWeaponIds.SLOT_PRIMARY, 0)
	_run_rig(rig, 0, 60, 0)

	var before := rig.fire_seq
	_run_rig(rig, 60, 90, DotWeaponCommand.BUTTON_ATTACK)
	_check("firing advances the replication counter", rig.fire_seq > before)

	# A bash is the alt-fire the arsenal has no path for.
	# [b]An Array, not an int.[/b] A GDScript lambda captures the enclosing locals by
	# value, so a counter incremented inside a signal handler stays zero outside it and
	# the check fails for a signal that fired perfectly — or worse, passes, because the
	# value it was initialised with happened to be the answer. A container is shared by
	# reference and is the honest way to count in a handler.
	var bashes: Array[int] = []
	rig.bashed.connect(func(_outcome: DotWeaponOutcome) -> void: bashes.append(1))
	_run_rig(rig, 200, 204, DotWeaponCommand.BUTTON_ALT)
	_check("the alt-fire bashes", bashes.size() == 1)

	# And it has its own cooldown, so holding it does not swing every tick.
	_run_rig(rig, 204, 240, DotWeaponCommand.BUTTON_ALT)
	_check("holding it does not swing every tick", bashes.size() < 4)

	# A reload is heard: out when it starts, in when it ends — on the player's own machine,
	# never on a server, never in a replay. An Array for the reason the bash count is one.
	var reloads := func(role: ZeeWeaponRig.Role, replay: bool) -> Array[StringName]:
		var heard: Array[StringName] = []
		var r := ZeeWeaponRig.new()
		r.role = role
		r.authority = true
		r.tick_rate = ZeeWeaponPack.TICK_RATE
		add_child(r)
		r.setup()
		r.give_everything()
		r.arsenal.select(ZeeWeaponIds.SLOT_PRIMARY, 0)
		r.reload_sound.connect(func(stage: StringName) -> void: heard.append(stage))
		_run_rig(r, 0, 60, 0)
		_run_rig(r, 60, 75, DotWeaponCommand.BUTTON_ATTACK)
		if replay:
			r.begin_replay()
		_run_rig(r, 75, 77, DotWeaponCommand.BUTTON_RELOAD)
		_run_rig(r, 77, 500, 0)
		if replay:
			r.end_replay()
		_cleanup(r)
		return heard

	var local: Array[StringName] = reloads.call(ZeeWeaponRig.Role.LOCAL, false)
	_check(
		"a reload is heard, out then in (%s)" % ", ".join(local),
		local == [ZeeWeaponSound.RELOAD_OUT, ZeeWeaponSound.RELOAD_IN]
	)
	_check("but not on a server", (reloads.call(ZeeWeaponRig.Role.SERVER, false) as Array).is_empty())
	_check("and not in a replay", (reloads.call(ZeeWeaponRig.Role.LOCAL, true) as Array).is_empty())

	_cleanup(rig)
	_end()


## [b]A SERVER rig has to know who is carrying it, and for a long time it did not.[/b]
##
## `player_ref` was resolved inside `_resolve_presentation()`, behind that function's
## `role == SERVER` early return. The view model and the world model belong there — they
## are drawing, and a server draws nothing. The player does not: it is where
## [method DotWeaponPlayerBridge.context_for] takes the muzzle position and the aim
## direction from, so a rig that skipped it built every [DotWeaponContext] with the
## defaults, and every shot on every dedicated server came out of `(0, 0, 0)` pointing
## `(0, 0, -1)`.
##
## **Nothing reported it, and the 133 checks above could not.** The weapon fires, the
## ammunition goes down, the use counter increments and replicates, and the hit
## registration runs and finds nothing, because there is nothing where it looked. What a
## game built on this has is a fight in which nobody can be shot and every number about it
## is correct.
##
## It was found in a game, by running bots against each other for twenty rounds: every
## single round ended with exactly two players alive, one per side, a draw. A number that is
## identical every round is a number nothing is deciding.
##
## The carrier here is a bare [Node3D] with no `component` method, so the bridge falls all
## the way through to the body transform — which is the weakest of its three answers and is
## the right one to test against, because it is the only one every game has.
func _rig_carrier() -> void:
	_begin("the rig knows who is carrying it")

	var carrier := Node3D.new()
	carrier.name = "Carrier"
	add_child(carrier)
	carrier.global_position = Vector3(12.0, 3.0, -45.0)
	carrier.rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)

	var rig := ZeeWeaponRig.new()
	rig.role = ZeeWeaponRig.Role.SERVER
	rig.authority = true
	rig.tick_rate = ZeeWeaponPack.TICK_RATE
	rig.player_ref = DotNodeRef.of_path(^"..")
	carrier.add_child(rig)

	var res := rig.setup()
	_check("a server rig with a carrier sets up: %s" % _why(res), res.ok)

	var _given := rig.give_everything()
	rig.arsenal.select(ZeeWeaponIds.SLOT_PRIMARY, 0)
	_run_rig(rig, 0, 60, 0)

	var shots: Array = []

	for tick in range(60, 120):
		var command := DotWeaponCommand.new()
		command.buttons = DotWeaponCommand.BUTTON_ATTACK
		var outcome := rig.simulate_tick(command, tick)

		if outcome != null and not outcome.shots.is_empty():
			shots.append(outcome.shots[0])
			break

	_check("it fires", not shots.is_empty())

	if shots.is_empty():
		carrier.queue_free()
		_end()
		return

	var shot: DotShot = shots[0]

	# Armed: with the resolution back inside `_resolve_presentation`, this is
	# `(0, 0, 0)` and the next one is `(0, 0, -1)`.
	_check(
		"and the shot leaves the carrier rather than the world origin (%v)" % shot.origin,
		shot.origin.distance_to(carrier.global_position) < 2.5
	)
	_check(
		"and goes where the carrier is facing (%v)" % shot.direction,
		shot.direction.dot(-carrier.global_transform.basis.z) > 0.9
	)

	carrier.queue_free()
	_end()


func _rig_rollback() -> void:
	_begin("rollback")

	var rig := _make_rig()
	rig.setup()
	rig.give(ZeeWeaponIds.RIFLE)
	rig.arsenal.select(ZeeWeaponIds.SLOT_PRIMARY, 0)
	_run_rig(rig, 0, 60, 0)

	var saved := rig.snapshot()
	var magazine := rig.arsenal.slot_at(ZeeWeaponIds.SLOT_PRIMARY).magazine

	_check("a snapshot carries the arsenal", saved.has("arsenal"))
	_check(
		"and the bash cooldown, which lives in the rig rather than the arsenal",
		saved.has("bash_ready")
	)

	# Spend some rounds and bash, then roll back.
	_run_rig(rig, 60, 120, DotWeaponCommand.BUTTON_ATTACK)
	_run_rig(rig, 200, 204, DotWeaponCommand.BUTTON_ALT)

	var spent := rig.arsenal.slot_at(ZeeWeaponIds.SLOT_PRIMARY).magazine
	_check("firing spent rounds", spent < magazine)

	var restored := rig.restore(saved)
	_check("the snapshot restores: %s" % _why(restored), restored.ok)
	_check(
		"the magazine is back where it was",
		rig.arsenal.slot_at(ZeeWeaponIds.SLOT_PRIMARY).magazine == magazine
	)

	# The bug this guards: a snapshot that carried only the arsenal's half hands the
	# player a free bash on every correction, because the cooldown lives in the rig.
	var after: Array[int] = []
	rig.bashed.connect(func(_o: DotWeaponOutcome) -> void: after.append(1))

	# The cooldown was saved before any bash happened, so a bash must now be allowed —
	# proving the restore put a usable number back rather than leaving the spent one.
	_run_rig(rig, 300, 304, DotWeaponCommand.BUTTON_ALT)
	_check("a restored rig can bash again", after.size() == 1)

	# And immediately afterwards it cannot, which is the cooldown actually running.
	_run_rig(rig, 304, 308, DotWeaponCommand.BUTTON_ALT)
	_check("but not twice in four ticks", after.size() == 1)

	_cleanup(rig)
	_end()


func _view_models() -> void:
	_begin("view models")

	# Headless with a null rendering driver still builds a scene tree, which is enough
	# to prove every model loads, parents and measures. What it cannot prove is that any
	# of it looks right — that is tools/screenshot.sh, and it is not optional.
	var view := ZeeViewModel.new()
	view.show_arms = false
	add_child(view)

	var equipped := 0
	var muzzled := 0
	var failures: Array[String] = []

	for art: ZeeWeaponArt in ZeeWeaponArtTable.all():
		var res := view.equip(art)

		if res.ok:
			equipped += 1
		else:
			failures.append("%s: %s" % [String(art.id), res.error.message])

		if art.has_model() and view.muzzle_transform().origin.length() >= 0.0:
			muzzled += 1

	_check(
		"all twenty-seven weapons equip: %s" % ", ".join(failures),
		equipped == 27
	)
	_check("and twenty-six of them have a muzzle to draw from", muzzled == 26)

	_check(
		"the last one equipped is the one reported",
		view.equipped() == ZeeWeaponIds.STICKY
	)

	view.clear()
	_check("clearing leaves nothing in hand", view.equipped() == &"")

	var arms := ZeeViewArms.new()
	add_child(arms)
	var built := arms.build()
	_check("the first-person arms build: %s" % _why(built), built.ok)
	_check("and there are two of them", arms.has_arms())

	view.queue_free()
	arms.queue_free()
	_end()


func _aim() -> void:
	_begin("aiming down")

	var aimable := 0
	for art: ZeeWeaponArt in ZeeWeaponArtTable.all():
		if art.aim_enabled:
			aimable += 1
	# Twenty-seven less seven melee (fists included) and two thrown.
	_check("eighteen weapons aim; melee and throwables do not (%d)" % aimable, aimable == 18)

	var view := ZeeViewModel.new()
	view.show_arms = false
	add_child(view)
	var animated := view.get_node("Animated") as Node3D

	# _process is driven by hand so the easing is the same on every run and every machine.
	var step := func(seconds: float) -> void:
		for _i in range(int(seconds / 0.02)):
			view._process(0.02)

	view.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.SNIPER))
	view.aim(true)
	step.call(0.4)
	_check("the sniper comes fully up in its aim_time (%.2f)" % view.aim_fraction(),
		is_equal_approx(view.aim_fraction(), 1.0))
	_check("and zooms to x0.3 (%.3f)" % view.aim_fov_scale(),
		absf(view.aim_fov_scale() - 0.3) < 0.001)
	_check("and looks through its scope", view.is_scoped())
	_check("which hides the weapon: the scope is the view", not animated.visible)

	view.aim(false)
	step.call(0.4)
	_check("released, the lens is back to x1 (%.3f)" % view.aim_fov_scale(),
		is_equal_approx(view.aim_fov_scale(), 1.0))
	_check("and the weapon is drawn again", animated.visible and not view.is_scoped())

	var rifle := ZeeWeaponArtTable.get_art(ZeeWeaponIds.RIFLE)
	view.equip(rifle)
	view.aim(true)
	step.call(0.4)
	_check("a rifle zooms a little and is not scoped (%.2f)" % view.aim_fov_scale(),
		absf(view.aim_fov_scale() - rifle.aim_zoom) < 0.001 and not view.is_scoped())
	var holder := view.get_node("Animated/Holder") as Node3D
	var at := animated.transform.origin + holder.transform.origin
	_check("and arrives centred at its aim_offset (%.3f m off)" % at.distance_to(rifle.aim_offset),
		at.distance_to(rifle.aim_offset) < 0.01)

	view.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.PISTOL))
	_check("a new weapon starts at the hip, aim held or not", view.aim_fraction() == 0.0)

	view.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.KNIFE))
	view.aim(true)
	step.call(0.4)
	_check("a knife held to aim stays at the hip", view.aim_fraction() == 0.0 and view.aim_fov_scale() == 1.0)

	var overlay := ZeeScopeOverlay.new()
	add_child(overlay)
	overlay.fraction = 2.0
	_check("the scope overlay clamps its fraction", overlay.fraction == 1.0)

	overlay.queue_free()
	view.queue_free()
	_end()


# --- Helpers ----------------------------------------------------------------

func _make_arsenal() -> DotWeaponArsenal:
	var arsenal := DotWeaponArsenal.new()
	arsenal.catalogue = ZeeWeaponPack.catalogue()
	arsenal.tick_rate = ZeeWeaponPack.TICK_RATE
	arsenal.authority = true
	add_child(arsenal)
	return arsenal


func _effects() -> void:
	_begin("shots are seen and heard")

	# --- Sound ---
	var silent: Array[String] = []
	var clicks: Array[String] = []

	for sound_class in ZeeWeaponSound.RECIPES.keys():
		var wav := ZeeWeaponSound.stream(sound_class) as AudioStreamWAV
		if wav == null or wav.data.size() < 200 or _wav_peak(wav) < 0.2:
			silent.append(String(sound_class))
		elif wav.data.decode_s16(wav.data.size() - 2) != 0:
			clicks.append(String(sound_class))

	_check("every sound class bakes something audible: %s" % ", ".join(silent), silent.is_empty())
	_check(
		"and every one ends at exactly zero, so none of them clicks: %s" % ", ".join(clicks),
		clicks.is_empty()
	)

	var rifle := ZeeWeaponSound.stream(ZeeWeaponSound.RIFLE) as AudioStreamWAV
	var again := ZeeWeaponSound.bake(
		ZeeWeaponSound.RECIPES[ZeeWeaponSound.RIFLE], hash(ZeeWeaponSound.RIFLE)
	)
	_check("the same class bakes the same bytes twice", again.data == rifle.data)

	# A gun added to the pack without a sound class falls back to the rifle's, silently.
	var unclassed: Array[String] = []
	for def: DotWeaponDef in ZeeWeaponPack.weapons():
		if def.has_tag(ZeeWeaponIds.TAG_MELEE) or def.has_tag(ZeeWeaponIds.TAG_THROWN):
			continue
		if not ZeeWeaponSound.WEAPONS.has(def.id):
			unclassed.append(String(def.id))
	_check("every gun in the pack names its own sound: %s" % ", ".join(unclassed), unclassed.is_empty())

	_check(
		"a bash from a sniper sounds like a bash, not a sniper",
		ZeeWeaponSound.class_for(ZeeWeaponIds.SNIPER, DotWeaponOutcome.KIND_SWING)
		== ZeeWeaponSound.SWING
	)

	var recorded := AudioStreamWAV.new()
	ZeeWeaponSound.set_stream(ZeeWeaponIds.PISTOL, recorded)
	var used_recording := ZeeWeaponSound.stream_for(
		ZeeWeaponIds.PISTOL, DotWeaponOutcome.KIND_SHOT
	) == recorded
	ZeeWeaponSound.set_stream(ZeeWeaponIds.PISTOL, null)
	_check(
		"a game's own recording outranks the synthesiser, and comes back out",
		used_recording
		and ZeeWeaponSound.stream_for(ZeeWeaponIds.PISTOL, DotWeaponOutcome.KIND_SHOT) != recorded
	)

	# --- A first-person rig ---
	# Armed: before ZeeShotFx, a use drew the gun kicking and nothing else at all.
	var carrier := Node3D.new()
	carrier.name = "FxCarrier"
	add_child(carrier)

	var view := ZeeViewModel.new()
	view.show_arms = false
	carrier.add_child(view)

	var rig := ZeeWeaponRig.new()
	rig.role = ZeeWeaponRig.Role.LOCAL
	rig.authority = true
	rig.tick_rate = ZeeWeaponPack.TICK_RATE
	rig.player_ref = DotNodeRef.of_path(^"..")
	rig.view_model_ref = DotNodeRef.of_path(view.get_path())
	carrier.add_child(rig)

	var res := rig.setup()
	_check("a first-person rig sets up: %s" % _why(res), res.ok)
	_check("and has shot effects", rig.shot_fx() != null)

	rig.give(ZeeWeaponIds.SHOTGUN)
	var shotgun := rig.arsenal.catalogue.get_def(ZeeWeaponIds.SHOTGUN)
	rig.arsenal.select(shotgun.slot, 0)
	_run_rig(rig, 0, 60, 0)

	var pellets := 0
	for tick in range(60, 200):
		var command := DotWeaponCommand.new()
		command.buttons = DotWeaponCommand.BUTTON_ATTACK
		var outcome := rig.simulate_tick(command, tick)
		if outcome != null and outcome.used and not outcome.shots.is_empty():
			pellets = outcome.shots[0].pellets.size()
			break

	var fx := rig.shot_fx()
	var tracers := fx.tracer_count() if fx != null else 0
	var wanted := mini(maxi(1, pellets), ZeeShotFx.MAX_TRACERS_PER_USE)
	_check(
		"a shotgun blast draws a tracer per pellet, up to the cap (%d of %d)" % [tracers, pellets],
		pellets > 0 and tracers == wanted
	)
	_check(
		"and plays a report",
		fx != null and int(fx.describe()["voices"]) >= 1
	)

	# The local player's own world model, driven by the replicated counter the way
	# game-playground drives every player's: it must not play the shot a second time.
	var own := ZeeWorldModel.new()
	carrier.add_child(own)
	own.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.SHOTGUN))
	own.on_fired(Vector2(1.0, 0.1), ZeeWeaponNet.KIND_SHOT)
	_check(
		"the carrier's own world model stays quiet beside its first-person rig",
		own.get_node_or_null(^"ShotFx") == null
	)

	# Somebody else's: nothing on this machine draws their shot but their hand.
	var stranger := Node3D.new()
	add_child(stranger)
	var theirs := ZeeWorldModel.new()
	stranger.add_child(theirs)
	theirs.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.RIFLE))
	theirs.on_fired(Vector2(0.4, 0.1), ZeeWeaponNet.KIND_SHOT)
	var their_fx := theirs.get_node_or_null(^"ShotFx") as ZeeShotFx
	_check(
		"somebody else's shot is drawn from their hand",
		their_fx != null and their_fx.tracer_count() == 1
	)
	# Sounds turned off after the first shot (a settings change) reach the next one.
	theirs.sounds = false
	theirs.on_fired(Vector2(0.4, 0.1), ZeeWeaponNet.KIND_SHOT)
	_check(
		"and turning their sounds off after a shot silences the next one",
		their_fx != null and not their_fx.sounds
	)

	var server := _make_rig()
	server.setup()
	_check("a server rig draws and plays nothing", server.shot_fx() == null)

	_cleanup(server)
	carrier.queue_free()
	stranger.queue_free()
	_end()


## The loudest sample in a 16-bit stream, from 0 to 1.
static func _wav_peak(wav: AudioStreamWAV) -> float:
	var peak := 0
	for i in range(0, wav.data.size() - 1, 2):
		peak = maxi(peak, absi(wav.data.decode_s16(i)))
	return float(peak) / 32767.0


func _make_rig() -> ZeeWeaponRig:
	var rig := ZeeWeaponRig.new()
	rig.role = ZeeWeaponRig.Role.SERVER
	rig.authority = true
	rig.tick_rate = ZeeWeaponPack.TICK_RATE
	add_child(rig)
	return rig


## Runs an arsenal for a range of ticks with one button held, counting the uses.
func _run(arsenal: DotWeaponArsenal, from: int, to: int, buttons: int) -> int:
	var used := 0
	var previous: DotWeaponCommand = null

	for tick in range(from, to):
		var command := DotWeaponCommand.new()
		command.buttons = buttons

		var ctx := DotWeaponContext.make(1, tick, Vector3.ZERO, Vector3.FORWARD)
		ctx.authority = true

		var out := arsenal.simulate_tick(command, ctx, previous)

		if out.used:
			used += 1

		previous = command

	return used


func _run_rig(rig: ZeeWeaponRig, from: int, to: int, buttons: int) -> int:
	var used := 0

	for tick in range(from, to):
		var command := DotWeaponCommand.new()
		command.buttons = buttons

		var ctx := DotWeaponContext.make(1, tick, Vector3.ZERO, Vector3.FORWARD)
		ctx.authority = true

		if rig.simulate_tick(command, tick, ctx).used:
			used += 1

	return used


func _cleanup(node: Node) -> void:
	remove_child(node)
	node.queue_free()


func _why(res: DotResult) -> String:
	return "" if res.ok else res.error.message


func _input_bindings() -> void:
	_begin("input bindings")

	# Every action this could add, removed first so the suite starts from a project
	# that bound none of them, and removed again after so no later scene inherits them.
	var ours: Array[StringName] = []
	for action: StringName in ZeeWeaponInput.DEFAULT_ACTIONS.keys():
		ours.append(action)
	for slot in range(1, 6):
		ours.append(StringName(ZeeWeaponInput.SLOT_ACTION_PREFIX + str(slot)))
	for action in ours:
		if InputMap.has_action(action):
			InputMap.erase_action(action)

	# An Array, not a counter: a lambda captures a scalar by value.
	var heard: Array[Dictionary] = []
	var listen := func(rec: Dictionary) -> void:
		if str(rec.get("channel", "")) == ZeeWeaponInput.CHANNEL:
			heard.append(rec)
	DotLog.signals().record.connect(listen)

	var first := ZeeWeaponInput.register_default_actions()
	_check("registering the defaults adds all thirteen", first == 13)
	_check(
		"and says so once, on zee.input, at INFO (heard %d)" % heard.size(),
		heard.size() == 1 and int(heard[0].get("level", -1)) == DotLog.Level.INFO
	)

	var second := ZeeWeaponInput.register_default_actions()
	_check("a second call adds nothing", second == 0)
	_check("and logs nothing: an edge, not a line per call", heard.size() == 1)

	DotLog.signals().record.disconnect(listen)
	for action in ours:
		if InputMap.has_action(action):
			InputMap.erase_action(action)

	_end()


# --- Counting ---------------------------------------------------------------

func _begin(name: String) -> void:
	_section = name
	_sections_entered += 1
	print("")
	print("-- %s" % name)


func _end() -> void:
	_sections_finished += 1


func _check(label: String, passed: bool) -> void:
	_checks += 1

	if passed:
		print("   ok    %s" % label)
		return

	_failures += 1
	print("   FAIL  %s" % label)


## A check that only prints when it fails. For the ones run in a loop, where twenty-seven
## lines of "ok" buries the one line anybody needs to read.
func _check_quiet(label: String, passed: bool) -> void:
	_checks += 1

	if passed:
		return

	_failures += 1
	print("   FAIL  %s" % label)
