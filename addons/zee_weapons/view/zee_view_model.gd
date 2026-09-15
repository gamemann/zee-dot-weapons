@tool
class_name ZeeViewModel
extends Node3D

## The weapon you see in your own hands, and everything it does while you hold it.
##
## Parent it to the camera. It builds the arms once, swaps the weapon model whenever the
## arsenal switches, and every render frame asks [ZeeWeaponPose] where the thing should
## actually be.
##
## [b]It is told what happened; it never asks.[/b] Nothing here reads an input device, a
## clock or the arsenal's internals — a game calls [method on_used],
## [method on_reload_started] and the rest from the signals it is already handling. That
## is what lets exactly the same node draw a remote player's weapon in third person,
## driven by replicated events rather than by local ones, with no branch anywhere in it.
##
## [b]Nothing here is part of the netcode contract.[/b] It runs on render frames, never
## writes to the simulation, and a player who turns it off simulates identically to one
## who does not — which is the whole reason dot-player-controller keeps its view in a
## separate node, and this is the same line drawn in the same place.
##
## [b]Structure, and why it is four nodes deep.[/b]
## [codeblock]
## ZeeViewModel          at the camera, identity
##   Arms                the hands, posed per weapon
##   Animated            the pose's transform: sway, bob, kick, deploy
##     Holder            the art's resting transform: offset, orientation, scale
##       Weapon          the mesh, in its own +Z-forward space
##       Magazine        a sibling, so a reload can animate it independently
##       Attachment(s)   siblings too, in the same model space
## [/codeblock]
## The split between Animated and Holder is what lets the art's placement and the frame's
## animation be authored independently: fold them together and every weapon's resting
## offset has to be re-derived every time the sway changes.

const CHANNEL := "zee.view"

## Emitted once the weapon model for [param id] is in the tree and placed.
##
## For a game hanging a muzzle flash, a laser sight or a scope overlay off it, which
## cannot be done until the model exists.
signal model_ready(id: StringName, weapon: Node3D)

@export_group("Wiring")

## The arms. Left null, the view model builds its own on first use.
##
## A [DotNodeRef] rather than a path, family-wide rule: the host decides per instance,
## in the inspector, and nothing in this addon hardcodes a scene path.
@export var arms_ref: DotNodeRef = null

@export_group("Behaviour")

## Whether to build and show hands at all.
##
## Off is a real configuration, not a debug switch: a game whose characters are not
## humanoid, or one drawing a weapon with no holder at all, wants the model and not the
## arms.
@export var show_arms: bool = true

## Which skin the hands wear. Passed to [ZeeViewArms] when this builds its own.
@export_file("*.png", "*.jpg", "*.webp") var arm_skin: String = ""

## Hides the whole rig. What a "view model" video setting toggles.
@export var visible_model: bool = true:
	set(value):
		visible_model = value
		visible = value

@export_group("Feel")

## Scales sway, bob and kick for everything this rig draws.
@export_range(0.0, 3.0, 0.05) var feel: float = 1.0

var _arms: ZeeViewArms = null
var _animated: Node3D = null
var _holder: Node3D = null
var _weapon: Node3D = null
var _magazine: Node3D = null
var _attachments: Array[Node3D] = []

var _pose := ZeeWeaponPose.make()
var _art: ZeeWeaponArt = null
var _id: StringName = &""

## Where the muzzle sits in the weapon's own space, measured when the model was built.
var _muzzle := Vector3.ZERO

## The look angles last frame, so sway can be driven by how far the view moved.
var _last_look := Vector2.ZERO
var _look_seen := false

var _built: bool = false

## Posture for this frame, written by whoever is driving the rig.
##
## [b]Plain fields rather than a call into the controller.[/b] The rig has to work for a
## remote player, a bot and a replay, none of which have a controller to ask — so the
## driver pushes what it knows, and the default is somebody standing still looking
## straight ahead, which draws correctly rather than not at all.
var _speed: float = 0.0
var _on_floor: bool = true
var _crouched: bool = false
var _look := Vector2.ZERO


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_build_structure()


# --- Building ---------------------------------------------------------------

func _build_structure() -> void:
	if _built:
		return

	_animated = Node3D.new()
	_animated.name = "Animated"
	add_child(_animated)

	_holder = Node3D.new()
	_holder.name = "Holder"
	_animated.add_child(_holder)

	if show_arms:
		_build_arms()

	_built = true


func _build_arms() -> void:
	if arms_ref != null:
		var found := arms_ref.resolve(self)
		if found.ok and found.value is ZeeViewArms:
			_arms = found.value
			_arms.build()
			return

	_arms = ZeeViewArms.new()
	_arms.name = "Arms"
	_arms.skin = arm_skin
	add_child(_arms)

	var res := _arms.build()

	if not res.ok:
		# Not fatal, and not even an error: a rig with no hands still draws the weapon,
		# which is what a great many games in this genre ship anyway.
		DotLog.info(
			CHANNEL, "no first-person hands; drawing the weapon alone",
			{"why": res.error.message}
		)


# --- Weapons ----------------------------------------------------------------

## Draws [param art]'s weapon, replacing whatever was in hand.
##
## [b]Rebuilds rather than hides.[/b] Keeping every weapon in the tree and toggling
## visibility is the obvious optimisation and it costs more than it saves here:
## twenty-seven models, their magazines and their attachments is a hundred-odd nodes per
## player, all of them being culled and sorted every frame to draw one.
func equip(art: ZeeWeaponArt) -> DotResult:
	_build_structure()

	if art == null:
		clear()
		return DotResult.fail(DotError.CODE_INVALID, "No art to equip.")

	_clear_models()

	_art = art
	_id = art.id
	_pose.weight = art.weight * maxf(0.0, feel)

	_holder.transform = art.view_transform()

	if _arms != null:
		_arms.set_pose(art.pose)

	if not art.has_model():
		# Legitimate, and the fists are exactly this: a weapon with hands and no object
		# in them. Not a failure and not worth a log line.
		_muzzle = Vector3.ZERO
		model_ready.emit(_id, null)
		return DotResult.success(null)

	_weapon = ZeeModelCache.instantiate(art.model_path)

	if _weapon == null:
		return DotResult.fail(
			DotError.CODE_IO, "No model for %s." % String(art.id), art.model_path
		)

	_weapon.name = "Weapon"
	_holder.add_child(_weapon)
	_set_on_top(_weapon)

	_muzzle = _measure_muzzle(art)

	if art.has_magazine():
		_magazine = _add_part(art.magazine_path, art.magazine_transform())

	for entry in art.attachments:
		var part := _add_part(
			str(entry.get("path", "")),
			Transform3D(
				Basis.from_euler(_radians(entry.get("rotation", Vector3.ZERO))),
				entry.get("offset", Vector3.ZERO)
			)
		)
		if part != null:
			_attachments.append(part)

	model_ready.emit(_id, _weapon)
	return DotResult.success(null)


## Removes whatever is in hand.
func clear() -> void:
	_clear_models()
	_art = null
	_id = &""
	_muzzle = Vector3.ZERO


## The weapon currently drawn, or an empty name.
func equipped() -> StringName:
	return _id


## Where the muzzle is right now, in world space.
##
## [b]What a muzzle flash, a tracer and a shell ejection hang off, and nothing the
## simulation ever reads.[/b] A shot's real origin is the player's eye, decided on the
## server; this is where the effect should be drawn so that it comes out of the barrel
## rather than out of the player's face. Using this as a shot origin would mean a
## weapon's reach depended on its model, and a player with the view model turned off
## would shoot from somewhere else.
func muzzle_transform() -> Transform3D:
	if _weapon == null:
		return global_transform

	return _weapon.global_transform * Transform3D(Basis.IDENTITY, _muzzle)


# --- Being told what happened -----------------------------------------------

## A use produced [param outcome].
func on_used(outcome: DotWeaponOutcome) -> void:
	if outcome == null or not outcome.used:
		return

	_pose.punch(outcome.recoil)


## Recoil with no outcome to hand, for a remote player whose shots arrive as a counter.
func on_fired(recoil: Vector2 = Vector2(0.5, 0.1)) -> void:
	_pose.punch(recoil)


## How far through a switch, 1 fully in hand and 0 fully out of frame.
func on_deploy(fraction: float) -> void:
	_pose.set_deploy(fraction)


## How far through a reload, 0 to 1.
##
## The magazine is animated from the same number, so a game driving one drives both.
func on_reload(fraction: float) -> void:
	_pose.set_reload(_reload_curve(fraction))
	_animate_magazine(fraction)


## A charged weapon's draw, 0 to 1.
func on_charge(fraction: float) -> void:
	_pose.set_charge(fraction)


## A landing, with the downward speed in metres a second.
func on_landed(impact: float) -> void:
	_pose.land(impact)


## Everything back to rest. A respawn, a teleport, a correction.
func on_reset() -> void:
	_pose.reset()
	_look_seen = false


# --- The frame --------------------------------------------------------------

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _built:
		return

	_pose.advance(delta, _look_delta(), _speed, _on_floor, _crouched)
	_animated.transform = _pose.offset()


## Tells the rig how the holder is moving and looking this frame.
##
## [param look] is absolute yaw and pitch in degrees; the rig takes the difference
## itself, because the difference is what sway is made of and two callers computing it
## independently is two chances to compute it differently.
func drive(look: Vector2, speed: float, on_floor: bool, crouched: bool = false) -> void:
	_look = look
	_speed = speed
	_on_floor = on_floor
	_crouched = crouched


func _look_delta() -> Vector2:
	if not _look_seen:
		_look_seen = true
		_last_look = _look
		return Vector2.ZERO

	# Yaw wraps, and the wrap is the bug: turning from 179 to -179 degrees is two
	# degrees of movement and reads as 358 without this, which throws the weapon clear
	# off the screen once per full turn.
	var delta := Vector2(
		wrapf(_look.x - _last_look.x, -180.0, 180.0), _look.y - _last_look.y
	)
	_last_look = _look
	return delta


# --- Internals --------------------------------------------------------------

## Where in the reload the weapon is at its lowest.
##
## [b]A curve rather than the raw fraction[/b], because a reload that tips further and
## further over for two and a half seconds and then snaps upright is the single most
## obviously wrong thing a view model can do. This goes down, holds, and comes back.
static func _reload_curve(fraction: float) -> float:
	var f := clampf(fraction, 0.0, 1.0)

	if f < 0.25:
		return f / 0.25

	if f > 0.75:
		return maxf(0.0, (1.0 - f) / 0.25)

	return 1.0


## Drops the magazine out and slides a fresh one in, if there is one to animate.
func _animate_magazine(fraction: float) -> void:
	if _magazine == null or _art == null:
		return

	var f := clampf(fraction, 0.0, 1.0)
	var rest := _art.magazine_transform()

	# Out in the first third, absent through the middle, back in over the last third.
	# The middle is where the hand would be fetching the next one, and a magazine
	# visible throughout is a reload that reads as the gun shaking.
	var drop := 0.0
	if f < 0.34:
		drop = f / 0.34
	elif f < 0.62:
		drop = 1.0
	else:
		drop = maxf(0.0, (1.0 - f) / 0.38)

	_magazine.visible = drop < 0.98
	_magazine.transform = Transform3D(
		rest.basis, rest.origin + Vector3(0.0, -0.35 * drop, 0.0)
	)


func _add_part(path: String, at: Transform3D) -> Node3D:
	if path == "":
		return null

	var part := ZeeModelCache.instantiate(path)

	if part == null:
		return null

	_holder.add_child(part)
	part.transform = at
	_set_on_top(part)
	return part


## Measures the muzzle, honouring an override on the art.
func _measure_muzzle(art: ZeeWeaponArt) -> Vector3:
	var distance := art.muzzle_distance

	if distance <= 0.0:
		distance = ZeeModelCache.muzzle_distance(art.model_path, art.model_forward)

	return art.model_forward.normalized() * distance + art.muzzle_offset


## Draws a part so it reads as a view model without breaking its own depth.
##
## [b]Depth testing stays ON, and switching it off is the obvious mistake.[/b] The
## tempting fix for a weapon poking through a wall is `no_depth_test`, and it works —
## right up until the hands and the gun are drawn against each other, at which point
## neither can occlude the other and whichever sorts last wins. The first render of this
## rig had a forearm painted flat over the rifle it was supposed to be holding.
##
## What is set instead is a sorting offset, which biases the draw order without throwing
## the depth buffer away, so the arms and the weapon occlude each other correctly.
##
## [b]The cost, stated plainly:[/b] a view model can still clip into a wall the player is
## pressed against. The pack's offsets keep everything within about 0.6 m of the camera
## and a player capsule is 0.35 m across, so it is rare rather than impossible. A game
## that wants it gone renders the view model through its own [SubViewport] with its own
## camera and composites the result — which is the real fix, is more machinery than a
## weapons pack should impose, and needs no change here to adopt.
func _set_on_top(root: Node) -> void:
	for mesh in _meshes(root):
		mesh.sorting_offset = 100.0

		# [b]A view model casts no shadow.[/b] It is drawn half a metre from the camera at
		# well under life size, so the shadow it casts is a large dark smear on the ground
		# a couple of metres ahead of the player — an object-shaped shadow with no object,
		# because the thing casting it is only visible to one viewer. The third-person
		# world model is what casts the shadow other people see.
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var material: Material = mesh.material_override

		if material == null:
			# Duplicated from the imported material rather than replaced by a fresh one:
			# a new StandardMaterial3D turns the model flat white, and the imported one is
			# shared with the third-person copy of the same mesh, which must not be edited.
			var source := mesh.get_active_material(0)
			material = (source as StandardMaterial3D).duplicate() \
				if source is StandardMaterial3D else StandardMaterial3D.new()
			mesh.material_override = material


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []

	if node is MeshInstance3D:
		out.append(node)

	for child in node.get_children():
		out.append_array(_meshes(child))

	return out


func _clear_models() -> void:
	for node in [_weapon, _magazine]:
		if node != null:
			node.queue_free()

	for node in _attachments:
		node.queue_free()

	_weapon = null
	_magazine = null
	_attachments.clear()


static func _radians(value: Variant) -> Vector3:
	var v: Vector3 = value if value is Vector3 else Vector3.ZERO
	return Vector3(deg_to_rad(v.x), deg_to_rad(v.y), deg_to_rad(v.z))


func describe() -> Dictionary:
	return {
		"equipped": String(_id),
		"has_model": _weapon != null,
		"magazine": _magazine != null,
		"attachments": _attachments.size(),
		"arms": _arms.describe() if _arms != null else {},
		"pose": _pose.describe(),
		"muzzle": _muzzle,
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("view model: %s%s" % [
		String(_id) if _id != &"" else "(nothing)",
		"" if _weapon != null else " (no mesh)",
	])
	out.append("  muzzle %.3f m out, %d attachment(s)" % [
		_muzzle.length(), _attachments.size()
	])
	out.append("  %s" % str(_pose.describe()))
	return out
