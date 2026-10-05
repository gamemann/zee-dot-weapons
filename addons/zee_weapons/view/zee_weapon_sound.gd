class_name ZeeWeaponSound
extends RefCounted

## What each weapon sounds like, baked from arithmetic the first time it is asked for.
##
## [b]Baked, because the pack ships no audio and every game built on it was silent.[/b] The
## art is CC0 and vendored; there is no CC0 set of twenty-seven matched weapon sounds to
## vendor beside it, and a pack that left sound to each game got none in any of them. A
## synthesised shot is a stand-in, but it is the stand-in that tells a player the trigger
## did something — the one thing a silent weapon cannot.
##
## [b]Why not dot-audio's synthesiser.[/b] It is one sine sweep with unfiltered noise and
## three shot voices, which is right for what it is (a placeholder for every kind of sound
## a game makes) and wrong for this: twenty-seven weapons need a crack, a body and a tail
## that can be told apart, and white noise with nothing filtered out of it is a hiss rather
## than a report. So the layers here are filtered, and the pack depends on nothing new.
##
## [b]Replaced one id at a time.[/b] [method set_stream] puts a real recording in front of
## the synthesiser, so a game that gets audio for its rifle does not have to re-record the
## rest before it can use it.
##
## [b]Deterministic.[/b] The grit is [method DotRandomStream.mix4] rather than [method
## @GlobalScope.randf], so every machine bakes the same bytes, which is what lets the suite
## assert about a sound instead of listening to one.

## 22 kHz mono, for the reason dot-audio gives: short noises with nothing worth keeping
## above a few kilohertz, at half the memory of 44.
const RATE := 22050

## Sound classes. A weapon names one; a game can override per weapon id instead.
const LIGHT := &"light"
const MAGNUM := &"magnum"
const RIFLE := &"rifle"
const HEAVY := &"heavy"
const SNIPER := &"sniper"
const SHOTGUN := &"shotgun"
const MINIGUN := &"minigun"
const LAUNCHER := &"launcher"
const BEAM := &"beam"
const CHARGE := &"charge"
const SWING := &"swing"
const BASH := &"bash"
const THROW := &"throw"
const IMPACT := &"impact"

## How each class is built. Every field is optional; the defaults are silence.
##
## [code]crack[/code] is the supersonic snap: band-passed noise, [code]crack_hz[/code] its
## top, decaying over [code]crack_s[/code]. [code]body[/code] is the thump the chest hears:
## a sine swept from [code]body_hz[/code] down to [code]body_to[/code] over
## [code]body_s[/code]. [code]tail[/code] is the room: darker noise that rings out over
## [code]tail_s[/code]. [code]tone[/code] is a pitched zap, for the energy weapons, swept
## [code]tone_hz[/code] to [code]tone_to[/code]. [code]whoosh[/code] is air: noise whose
## brightness rises and falls over the whole sound, for anything swung or thrown.
##
## [b]One table, so the classes can be read against each other.[/b] Whether a sniper is
## louder than a pistol is a question about two rows, and two rows side by side is the
## only way it gets checked.
const RECIPES := {
	LIGHT: {
		"length": 0.32, "gain": 0.70,
		"crack": 0.85, "crack_hz": 5200.0, "crack_s": 0.010,
		"body": 0.55, "body_hz": 230.0, "body_to": 80.0, "body_s": 0.035,
		"tail": 0.30, "tail_hz": 1600.0, "tail_s": 0.070,
	},
	MAGNUM: {
		"length": 0.55, "gain": 0.85,
		"crack": 1.00, "crack_hz": 5600.0, "crack_s": 0.014,
		"body": 0.85, "body_hz": 170.0, "body_to": 50.0, "body_s": 0.060,
		"tail": 0.45, "tail_hz": 1400.0, "tail_s": 0.140,
	},
	RIFLE: {
		"length": 0.50, "gain": 0.80,
		"crack": 0.95, "crack_hz": 6400.0, "crack_s": 0.013,
		"body": 0.65, "body_hz": 190.0, "body_to": 58.0, "body_s": 0.045,
		"tail": 0.42, "tail_hz": 2000.0, "tail_s": 0.110,
	},
	HEAVY: {
		"length": 0.70, "gain": 0.88,
		"crack": 1.00, "crack_hz": 6800.0, "crack_s": 0.016,
		"body": 0.85, "body_hz": 150.0, "body_to": 46.0, "body_s": 0.065,
		"tail": 0.50, "tail_hz": 1700.0, "tail_s": 0.190,
	},
	SNIPER: {
		"length": 1.20, "gain": 0.95,
		"crack": 1.00, "crack_hz": 7600.0, "crack_s": 0.020,
		"body": 1.00, "body_hz": 120.0, "body_to": 38.0, "body_s": 0.090,
		"tail": 0.55, "tail_hz": 1300.0, "tail_s": 0.380,
	},
	SHOTGUN: {
		"length": 0.85, "gain": 0.95,
		"crack": 0.80, "crack_hz": 3800.0, "crack_s": 0.026,
		"body": 1.00, "body_hz": 115.0, "body_to": 40.0, "body_s": 0.095,
		"tail": 0.65, "tail_hz": 1100.0, "tail_s": 0.260,
	},
	MINIGUN: {
		"length": 0.16, "gain": 0.62,
		"crack": 0.80, "crack_hz": 5800.0, "crack_s": 0.008,
		"body": 0.55, "body_hz": 210.0, "body_to": 85.0, "body_s": 0.022,
		"tail": 0.25, "tail_hz": 1800.0, "tail_s": 0.040,
	},
	LAUNCHER: {
		"length": 0.80, "gain": 0.90,
		"crack": 0.35, "crack_hz": 1500.0, "crack_s": 0.030,
		"body": 1.00, "body_hz": 95.0, "body_to": 34.0, "body_s": 0.120,
		"tail": 0.55, "tail_hz": 800.0, "tail_s": 0.300,
	},
	BEAM: {
		"length": 0.10, "gain": 0.40,
		"tone": 0.90, "tone_hz": 1900.0, "tone_to": 1100.0, "tone_s": 0.060,
		"crack": 0.15, "crack_hz": 7000.0, "crack_s": 0.006,
	},
	CHARGE: {
		"length": 0.75, "gain": 0.85,
		"tone": 0.70, "tone_hz": 1300.0, "tone_to": 160.0, "tone_s": 0.160,
		"crack": 0.75, "crack_hz": 6800.0, "crack_s": 0.012,
		"body": 0.70, "body_hz": 140.0, "body_to": 45.0, "body_s": 0.070,
		"tail": 0.35, "tail_hz": 2400.0, "tail_s": 0.220,
	},
	SWING: {
		"length": 0.24, "gain": 0.45,
		"whoosh": 1.00, "whoosh_lo": 500.0, "whoosh_hi": 2600.0,
	},
	BASH: {
		"length": 0.26, "gain": 0.60,
		"whoosh": 0.70, "whoosh_lo": 400.0, "whoosh_hi": 1800.0,
		"body": 0.60, "body_hz": 160.0, "body_to": 70.0, "body_s": 0.040,
	},
	THROW: {
		"length": 0.30, "gain": 0.40,
		"whoosh": 1.00, "whoosh_lo": 350.0, "whoosh_hi": 1500.0,
	},
	IMPACT: {
		"length": 0.09, "gain": 0.45,
		"crack": 0.90, "crack_hz": 3600.0, "crack_s": 0.007,
		"body": 0.40, "body_hz": 420.0, "body_to": 190.0, "body_s": 0.012,
	},
}

## Which class each weapon in the pack sounds like. A weapon missing from here is
## classed by what its use was — see [method class_for].
const WEAPONS := {
	ZeeWeaponIds.PISTOL: LIGHT,
	ZeeWeaponIds.MACHINE_PISTOL: LIGHT,
	ZeeWeaponIds.SMG: LIGHT,
	ZeeWeaponIds.REVOLVER: MAGNUM,
	ZeeWeaponIds.DERRINGER: MAGNUM,
	ZeeWeaponIds.CARBINE: RIFLE,
	ZeeWeaponIds.RIFLE: RIFLE,
	ZeeWeaponIds.BULLPUP: RIFLE,
	ZeeWeaponIds.BURST_RIFLE: RIFLE,
	ZeeWeaponIds.BATTLE_RIFLE: HEAVY,
	ZeeWeaponIds.MARKSMAN: HEAVY,
	ZeeWeaponIds.SNIPER: SNIPER,
	ZeeWeaponIds.SHOTGUN: SHOTGUN,
	ZeeWeaponIds.DRUM_SHOTGUN: SHOTGUN,
	ZeeWeaponIds.MINIGUN: MINIGUN,
	ZeeWeaponIds.LAUNCHER: LAUNCHER,
	ZeeWeaponIds.BEAMER: BEAM,
	ZeeWeaponIds.CHARGE_RIFLE: CHARGE,
}

## Baked streams by class, and a game's own by weapon id or class.
static var _baked: Dictionary = {}
static var _overrides: Dictionary = {}


## The class [param id]'s use of [param kind] sounds like.
##
## [b]The kind wins for melee and throws.[/b] Every blaster can bash, and a bash from a
## sniper must not sound like a sniper going off.
static func class_for(id: StringName, kind: StringName) -> StringName:
	match kind:
		DotWeaponOutcome.KIND_SWING:
			return SWING
		DotWeaponOutcome.KIND_THROW:
			return THROW
		DotWeaponOutcome.KIND_BEAM:
			return BEAM

	if WEAPONS.has(id):
		return WEAPONS[id]

	return LAUNCHER if kind == DotWeaponOutcome.KIND_SPAWN else RIFLE


## The stream to play for [param id] using [param kind]: an override if a game set one,
## otherwise the class's bake.
static func stream_for(id: StringName, kind: StringName) -> AudioStream:
	if _overrides.has(id):
		return _overrides[id]

	return stream(class_for(id, kind))


## One class's stream, an override if there is one, baked on first use and kept.
static func stream(sound_class: StringName) -> AudioStream:
	if _overrides.has(sound_class):
		return _overrides[sound_class]

	if not _baked.has(sound_class):
		_baked[sound_class] = bake(RECIPES.get(sound_class, RECIPES[RIFLE]), hash(sound_class))

	return _baked[sound_class]


## Puts [param audio] in front of the synthesiser for a weapon id or a class name. Null
## takes it back out.
##
## [b]Static, and a game that sets one should clear it when it goes[/b] — the same rule
## as [method ZeeModelCache.set_asset_root], for the same reason: a static outlives one
## game in a shell that loads the next.
static func set_stream(id_or_class: StringName, audio: AudioStream) -> void:
	if audio == null:
		_overrides.erase(id_or_class)
	else:
		_overrides[id_or_class] = audio


## Bakes one recipe into a 16-bit mono stream.
static func bake(recipe: Dictionary, salt: int = 0) -> AudioStreamWAV:
	var length := clampf(float(recipe.get("length", 0.3)), 0.02, 2.0)
	var frames := int(length * float(RATE))
	var gain := clampf(float(recipe.get("gain", 0.7)), 0.0, 1.0)

	var crack := float(recipe.get("crack", 0.0))
	var crack_a := _pole(float(recipe.get("crack_hz", 5000.0)))
	var crack_hp := _pole(320.0)
	var crack_s := maxf(0.001, float(recipe.get("crack_s", 0.01)))

	var body := float(recipe.get("body", 0.0))
	var body_hz := maxf(1.0, float(recipe.get("body_hz", 150.0)))
	var body_to := maxf(1.0, float(recipe.get("body_to", 50.0)))
	var body_s := maxf(0.001, float(recipe.get("body_s", 0.05)))

	var tail := float(recipe.get("tail", 0.0))
	var tail_a := _pole(float(recipe.get("tail_hz", 1500.0)))
	var tail_s := maxf(0.001, float(recipe.get("tail_s", 0.1)))

	var tone := float(recipe.get("tone", 0.0))
	var tone_hz := maxf(1.0, float(recipe.get("tone_hz", 1500.0)))
	var tone_to := maxf(1.0, float(recipe.get("tone_to", 800.0)))
	var tone_s := maxf(0.001, float(recipe.get("tone_s", 0.05)))

	var whoosh := float(recipe.get("whoosh", 0.0))
	var whoosh_lo := float(recipe.get("whoosh_lo", 400.0))
	var whoosh_hi := float(recipe.get("whoosh_hi", 2000.0))

	var samples := PackedFloat32Array()
	samples.resize(frames)

	var crack_low := 0.0
	var crack_high := 0.0
	var tail_low := 0.0
	var whoosh_low := 0.0
	var body_phase := 0.0
	var tone_phase := 0.0
	var peak := 0.0

	for i in range(frames):
		var t := float(i) / float(RATE)
		var noise := DotRandomStream.unit_from(
			DotRandomStream.mix4(i, salt, frames, 0x5EED)
		) * 2.0 - 1.0

		var sample := 0.0

		if crack > 0.0:
			# Band-passed: a low-pass for the top, minus a low-pass for the bottom. Noise
			# with its lows left in is a thud; with its highs left in it is a hiss. The
			# band between is what reads as a snap.
			crack_low += crack_a * (noise - crack_low)
			crack_high += crack_hp * (crack_low - crack_high)
			sample += (crack_low - crack_high) * 2.2 * crack * exp(-t / crack_s)

		if body > 0.0:
			# Exponential sweep, because pitch is heard logarithmically: a linear one spends
			# its length near the top and arrives as a click with a tail.
			var hz := body_hz * pow(body_to / body_hz, minf(1.0, t / (body_s * 3.0)))
			body_phase += TAU * hz / float(RATE)
			sample += sin(body_phase) * body * exp(-t / body_s)

		if tail > 0.0:
			tail_low += tail_a * (noise - tail_low)
			sample += tail_low * 1.8 * tail * exp(-t / tail_s)

		if tone > 0.0:
			var thz := tone_hz * pow(tone_to / tone_hz, minf(1.0, t / (tone_s * 2.0)))
			tone_phase += TAU * thz / float(RATE)
			# Two odd harmonics over the fundamental: a sine alone is a test tone, a
			# square is harsh, and this is between them.
			var wave := sin(tone_phase) + sin(tone_phase * 3.0) / 3.0 + sin(tone_phase * 5.0) / 5.0
			sample += wave * 0.8 * tone * exp(-t / tone_s)

		if whoosh > 0.0:
			# Air: the noise's brightness and level rise and fall together over the whole
			# sound, which is the shape of something passing the ear.
			var through := t / length
			var bell := sin(PI * through)
			whoosh_low += _pole(lerpf(whoosh_lo, whoosh_hi, bell)) * (noise - whoosh_low)
			sample += whoosh_low * 2.4 * whoosh * bell * bell

		samples[i] = sample
		peak = maxf(peak, absf(sample))

	var data := PackedByteArray()
	data.resize(frames * 2)

	# Normalised to the recipe's gain, then shaped so the attack is a few samples rather
	# than one and the end reaches zero exactly. A stream that stops mid-cycle is a click,
	# and a click on the end of every shot is the thing that makes synthesised audio
	# unbearable rather than merely rough.
	var scale := gain / maxf(0.0001, peak)
	var attack := maxi(1, int(0.0008 * RATE))
	var release := maxi(1, int(0.012 * RATE))

	for i in range(frames):
		var shaped := samples[i] * scale
		shaped *= minf(1.0, float(i) / float(attack))
		shaped *= minf(1.0, float(frames - 1 - i) / float(release))
		var value := clampi(int(shaped * 32767.0), -32768, 32767)
		data[i * 2] = value & 0xFF
		data[i * 2 + 1] = (value >> 8) & 0xFF

	var out := AudioStreamWAV.new()
	out.format = AudioStreamWAV.FORMAT_16_BITS
	out.mix_rate = RATE
	out.stereo = false
	out.data = data
	return out


## A one-pole low-pass coefficient for a cutoff of [param hz].
static func _pole(hz: float) -> float:
	return 1.0 - exp(-TAU * clampf(hz, 1.0, RATE * 0.45) / float(RATE))


## Forgets every bake. For a suite measuring the cost of one.
static func clear_cache() -> void:
	_baked.clear()
