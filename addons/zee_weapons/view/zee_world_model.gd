@tool
class_name ZeeWorldModel
extends Node3D

## The weapon everybody [i]else[/i] sees, hanging off a character's hand.
##
## [b]Not a second copy of [ZeeViewModel], and the difference is the point.[/b] A view
## model is drawn on top of the world at an exaggerated scale, sways with the camera and
## exists for exactly one viewer. A world model is an object in the world: it is
## depth-tested, it casts a shadow, it is the right size, and thirty of them can be on
## screen at once. Sharing one node between the two jobs means either a first-person
## weapon that clips through walls or a third-person weapon somebody can see through a
## floor.
##
## [b]It is attached by duck typing, never by class.[/b] `attach_to` takes any node that
## answers `attachment(point)` — which dot-player-char's visual does and a game's own rig
## can — and this file mentions no character class at all, because a script that
## references a `class_name` the project does not have fails to parse and takes every
## script that references [i]it[/i] down with it.
##
## [b]Recoil is smaller here and that is deliberate.[/b] The kick a player feels in their
## own hands is a feel effect tuned for one viewer; applied at full strength to a
## character twenty metres away it reads as the weapon coming loose. A fraction of it is
## enough to tell a watcher that the gun went off.

# No CHANNEL: a drawer. Its one failure, a model that will not load, is reported once by
# ZeeModelCache and handed back as a DotResult; "nowhere to attach" is headless, not wrong.

## How much of a weapon's recoil a watcher sees.
const RECOIL_SHARE := 0.35

@export_group("Attachment")

## The attachment point on the character to hang from.
##
## Any node answering `attachment(point)`. The name is the character rig's to define;
## `right_hand` is what dot-player-char ships.
@export var mount: StringName = &"right_hand"

@export_group("Behaviour")

## Whether the weapon casts a shadow.
##
## On by default because a weapon with no shadow floats, and a floating weapon is one of
## the few third-person artefacts a player will actually mention.
@export var cast_shadow: bool = true

## Hides the model while the character is switching weapons.
##
## The third-person counterpart of the view model's deploy animation, and much simpler:
## nobody watching can tell a holster from a deploy at range, so it is a visibility
## toggle rather than an animation.
@export var hide_while_switching: bool = true

## Whether a shot is drawn and heard from this hand. See [method on_fired].
@export var effects: bool = true

## Whether the report is heard, when [member effects] draws the shot.
##
## [b]Off for a game that already has a sound for somebody else's shot[/b] — one that plays
## a use by its kind from the replicated counter, before any of this pack's art was drawn.
## Leaving both on is two reports for one shot from the same place; turning [member effects]
## off to stop it throws away the flash and the tracer, which are the part a watcher needs.
## Set with `set(&"sounds", …)` from a delivered game, because a shell built before this
## property existed fails to parse a pack that names it.
@export var sounds: bool = true

var _holder: Node3D = null
var _weapon: Node3D = null
var _attachments: Array[Node3D] = []
var _art: ZeeWeaponArt = null
var _id: StringName = &""
var _fx: ZeeShotFx = null

## Recoil offset in metres and its decay, so a watcher sees the gun move when it fires.
var _kick: float = 0.0

var _built: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_build()


func _build() -> void:
	if _built:
		return

	_holder = Node3D.new()
	_holder.name = "Holder"
	add_child(_holder)
	_built = true


# --- Attaching --------------------------------------------------------------

## Hangs this model off [param character]'s [member mount] point.
##
## [b]Returning false is not an error.[/b] A dedicated server has no character model, a
## 2D game has no hand, and a rig that treats "nowhere to attach" as a failure cannot run
## headless — which is the one place this whole family insists on being able to run.
func attach_to(character: Object) -> bool:
	if character == null or not character.has_method("attachment"):
		return false

	var point: Variant = character.call("attachment", mount)

	if not (point is Node):
		return false

	if get_parent() != null:
		get_parent().remove_child(self)

	(point as Node).add_child(self)
	transform = Transform3D.IDENTITY
	return true


# --- Weapons ----------------------------------------------------------------

## Draws [param art]'s weapon at the hand, replacing whatever was there.
func equip(art: ZeeWeaponArt) -> DotResult:
	_build()
	_clear_models()

	_art = art

	if art == null:
		_id = &""
		return DotResult.fail(DotError.CODE_INVALID, "No art to equip.")

	_id = art.id
	_holder.transform = art.world_transform()

	if not art.has_model():
		return DotResult.success(null)

	_weapon = ZeeModelCache.instantiate(art.model_path)

	if _weapon == null:
		return DotResult.fail(
			DotError.CODE_IO, "No model for %s." % String(art.id), art.model_path
		)

	_weapon.name = "Weapon"
	_holder.add_child(_weapon)

	# Attachments come across, magazines do not: a watcher cannot see a magazine fall
	# out at range, and thirty players each carrying one extra mesh they cannot see is
	# thirty meshes being culled every frame for nothing.
	for entry in art.attachments:
		var part := ZeeModelCache.instantiate(str(entry.get("path", "")))
		if part == null:
			continue
		_holder.add_child(part)
		part.transform = Transform3D(
			Basis.from_euler(_radians(entry.get("rotation", Vector3.ZERO))),
			entry.get("offset", Vector3.ZERO)
		)
		_attachments.append(part)

	_apply_shadows()
	return DotResult.success(null)


func clear() -> void:
	_clear_models()
	_art = null
	_id = &""


func equipped() -> StringName:
	return _id


## Where this weapon's muzzle is in the world, for an effect a watcher can see.
func muzzle_transform() -> Transform3D:
	if _weapon == null or _art == null:
		return global_transform

	var distance := _art.muzzle_distance

	if distance <= 0.0:
		distance = ZeeModelCache.muzzle_distance(_art.model_path, _art.model_forward)

	return _weapon.global_transform * Transform3D(
		Basis.IDENTITY,
		_art.model_forward.normalized() * distance + _art.muzzle_offset
	)


# --- Being told what happened -----------------------------------------------

## The weapon fired. [param recoil] is the pitch and yaw a behaviour asked for, and
## [param kind] a [ZeeWeaponNet] kind number.
##
## [param with_effects] draws the shot from this hand — a flash, a tracer along the barrel
## and the report — and is what a watcher sees of somebody else firing. It stands down by
## itself when the carrier's own first-person rig is on this machine, because that rig has
## already drawn the shot from the view model's muzzle and a second report a few
## centimetres away is the same gun going off twice.
func on_fired(
	recoil: Vector2 = Vector2(0.5, 0.1),
	kind: int = ZeeWeaponNet.KIND_SHOT,
	with_effects: bool = true
) -> void:
	if not is_finite(recoil.x):
		return
	_kick = minf(_kick + recoil.x * 0.008 * RECOIL_SHARE, 0.08)

	if with_effects and effects and is_inside_tree() and not _carrier_draws_its_own():
		_shot_fx().play_remote(kind, muzzle_transform(), muzzle_direction(), _id)


## Which way the barrel points in the world: the art's forward through the model's basis.
func muzzle_direction() -> Vector3:
	if _weapon == null or _art == null:
		return -global_basis.z.normalized()

	return (_weapon.global_basis * _art.model_forward).normalized()


## Whether the character is mid-switch. Hides the model while they are, if asked to.
func on_switching(switching: bool) -> void:
	if hide_while_switching:
		visible = not switching


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _built or _holder == null:
		return

	if _kick <= 0.00001:
		return

	# Decayed rather than sprung. A watcher cannot see an overshoot at twenty metres, so
	# the spring the view model runs would be arithmetic nobody ever sees the result of.
	_kick = move_toward(_kick, 0.0, _kick * 12.0 * delta + 0.0002)

	var rest := _art.world_transform() if _art != null else Transform3D.IDENTITY
	_holder.transform = Transform3D(rest.basis, rest.origin + Vector3(0.0, 0.0, _kick))


# --- Internals --------------------------------------------------------------

## The effects node, built the first time this hand fires.
##
## Lazily, because most world models in a match belong to somebody who has not fired yet,
## and thirty effects nodes waiting to be needed is thirty nodes in every frame's walk.
func _shot_fx() -> ZeeShotFx:
	if _fx != null and is_instance_valid(_fx):
		# Read every shot, not only at creation: a game that turns sounds off after the
		# first shot (a settings change) would otherwise keep hearing them.
		_fx.sounds = sounds
		return _fx

	_fx = ZeeShotFx.new()
	_fx.name = "ShotFx"
	_fx.sounds = sounds
	add_child(_fx)
	_fx.exclude_carrier(_carrier_body())
	return _fx


## The nearest physics body above this hand: the character carrying it, whose own capsule
## the barrel starts inside.
func _carrier_body() -> Node:
	var node := get_parent()
	var depth := 0

	while node != null and depth < 8:
		if node is CollisionObject3D:
			return node
		node = node.get_parent()
		depth += 1

	return null


## Whether a first-person rig with its own effects carries this hand on this machine.
##
## [b]Asked of the tree, not configured, and the configuration was tried in the head
## first.[/b] A game that forgot to switch the local player's world model off would play
## every one of its own shots twice, a few centimetres apart — and the game that would
## forget is the one that drives every player's world model from the replicated counter,
## its own included, which is the simplest way to write it.
func _carrier_draws_its_own() -> bool:
	var node := get_parent()
	var depth := 0

	while node != null and depth < 8:
		for child in node.get_children():
			if child is ZeeWeaponRig and (child as ZeeWeaponRig).shot_fx() != null:
				return true
		node = node.get_parent()
		depth += 1

	return false


func _apply_shadows() -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	for mesh in _meshes(self):
		mesh.cast_shadow = mode


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []

	if node is MeshInstance3D:
		out.append(node)

	for child in node.get_children():
		out.append_array(_meshes(child))

	return out


func _clear_models() -> void:
	if _weapon != null:
		_weapon.queue_free()

	for node in _attachments:
		node.queue_free()

	_weapon = null
	_attachments.clear()
	_kick = 0.0


static func _radians(value: Variant) -> Vector3:
	var v: Vector3 = value if value is Vector3 else Vector3.ZERO
	return Vector3(deg_to_rad(v.x), deg_to_rad(v.y), deg_to_rad(v.z))


func describe() -> Dictionary:
	return {
		"equipped": String(_id),
		"has_model": _weapon != null,
		"attachments": _attachments.size(),
		"attached": get_parent() != null,
		"mount": String(mount),
	}
