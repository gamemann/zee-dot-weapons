@tool
class_name ZeeWeaponArt
extends Resource

## How one weapon looks and where it sits, in the hand and on the screen.
##
## [b]Separate from [DotWeaponDef] on purpose, and the separation is the point of this
## addon.[/b] A definition is what a server validates at boot with none of the content
## installed: a slot, a cadence, a magazine. None of that has a mesh in it, and a
## dedicated server must never need one. This resource is everything a server can
## happily not have — a model path, two offsets and a scale — and a headless build
## never loads a single one.
##
## [b]Paths, never [PackedScene] references.[/b] Same rule dot-weapon's
## [member DotWeaponDef.behaviour_path] follows and for the same reason: a game
## delivered as a dot-cloud content pack is mounted at runtime and a mounted pack's
## `class_name` globals are not registered in the host, so a preloaded resource could
## only ever ship inside the build. A path is resolved when the model is first drawn,
## by [ZeeModelCache], which is the moment the content is definitely mounted.
##
## [b]Two transforms, not one.[/b] A weapon held at arm's length in front of a camera
## and the same weapon in a character's fist are different objects at different scales:
## the first-person one is deliberately oversized and pulled close so it reads at a
## 90-degree field of view, and using one transform for both gives you either a
## world model the size of a car or a view model nobody can see.

@export_group("Identity")

## The weapon id this art belongs to. Must match a [member DotWeaponDef.id].
@export var id: StringName = &""

@export_group("Model")

## The weapon mesh. Empty is legal and means the weapon draws nothing — which is what
## bare fists are, and is why this is not required.
@export_file("*.glb", "*.gltf", "*.tscn", "*.scn") var model_path: String = ""

## Which way the mesh points in its own space, before any rotation below.
##
## [b]Kenney's blasters point along +Z and Godot's forward is -Z[/b], so every one of
## them needs turning around. Expressed as a vector rather than as a rotation baked into
## [member view_rotation] because the muzzle is derived from it too: get this wrong and
## the shots come out of the stock, which is a bug that looks like bad netcode.
@export var model_forward: Vector3 = Vector3.BACK

## Metres from the mesh origin to the muzzle, along [member model_forward].
##
## [b]Zero means "measure it", and measuring it is almost always right.[/b]
## [ZeeModelCache] takes the far end of the mesh's own bounding box along the forward
## axis, which is the end of the barrel on every model in this kit — including
## `blaster-e`, whose origin is at the stock rather than the centre and which a
## hand-written offset would therefore have had wrong. Override it only for a mesh whose
## barrel is not its longest feature.
@export_range(0.0, 4.0, 0.001, "or_greater") var muzzle_distance: float = 0.0

## Sideways and vertical nudge of the muzzle from the barrel line, in metres.
@export var muzzle_offset: Vector3 = Vector3.ZERO

@export_group("First person")

## Where the weapon sits relative to the camera, in metres. +X is right, +Y is up,
## -Z is forward.
@export var view_offset: Vector3 = Vector3(0.22, -0.2, -0.45)

@export var view_rotation: Vector3 = Vector3.ZERO

@export_range(0.05, 8.0, 0.01) var view_scale: float = 1.0

## Which way the hands hold it. Drives the arm pose, nothing else.
##
## A [StringName] rather than an enum because an enum is a list this addon would own,
## and a game adding a two-handed launcher pose should not have to edit a file here.
## [ZeeViewArms] falls back to [constant POSE_RIFLE] for a pose it does not know.
@export var pose: StringName = &"rifle"

## How much this weapon sways and bobs, as a multiple of the rig's own settings.
##
## A heavy weapon that moves exactly as much as a pistol reads as weightless. One
## number rather than a set of them, because the alternative is six sliders per weapon
## that nobody will ever tune individually.
@export_range(0.0, 3.0, 0.05) var weight: float = 1.0

@export_group("Third person")

## Where the weapon sits relative to the character's hand attachment point.
@export var world_offset: Vector3 = Vector3.ZERO

@export var world_rotation: Vector3 = Vector3.ZERO

@export_range(0.05, 8.0, 0.01) var world_scale: float = 1.0

@export_group("Magazine")

## The magazine mesh, dropped and replaced during a reload. Empty means the reload is
## the weapon tipping out of frame and back, with nothing leaving it.
##
## [b]This kit ships the clip as a separate model[/b], which is the whole reason the
## reload animation is worth having: a magazine that visibly falls away and a fresh one
## that slides in is the difference between a reload the player can read and a gun that
## waggles for two seconds.
@export_file("*.glb", "*.gltf", "*.tscn", "*.scn") var magazine_path: String = ""

## Where the magazine sits in the weapon, in the weapon's own space.
@export var magazine_offset: Vector3 = Vector3.ZERO

@export var magazine_rotation: Vector3 = Vector3.ZERO

@export_group("Attachments")

## Extra meshes parented to the weapon: a scope, a silencer, a drum.
##
## Each entry is `{"path": String, "offset": Vector3, "rotation": Vector3}`. A
## dictionary rather than a resource per attachment because an attachment is three
## values and a resource per scope would be sixty files to say what sixty lines say.
@export var attachments: Array[Dictionary] = []


static func make(p_id: StringName, p_model: String = "") -> ZeeWeaponArt:
	var art := ZeeWeaponArt.new()
	art.id = p_id
	art.model_path = p_model
	return art


## Adds an attachment and returns self, so a table can be written as a chain.
func with_attachment(
	path: String, offset: Vector3 = Vector3.ZERO, rotation: Vector3 = Vector3.ZERO
) -> ZeeWeaponArt:
	attachments.append({"path": path, "offset": offset, "rotation": rotation})
	return self


## Sets the magazine and returns self.
func with_magazine(path: String, offset: Vector3 = Vector3.ZERO) -> ZeeWeaponArt:
	magazine_path = path
	magazine_offset = offset
	return self


## The first-person transform, before any animation the rig applies.
func view_transform() -> Transform3D:
	return _transform(view_offset, view_rotation, view_scale)


## The third-person transform, relative to the hand it hangs off.
func world_transform() -> Transform3D:
	return _transform(world_offset, world_rotation, world_scale)


func magazine_transform() -> Transform3D:
	return _transform(magazine_offset, magazine_rotation, 1.0)


## The rotation that turns [member model_forward] into Godot's -Z.
##
## [b]Derived rather than authored[/b], so a table only ever states which way the mesh
## points and never also states the rotation that fixes it — the two drifting apart is
## how a weapon ends up pointing backwards in the world and forwards on the screen.
func orientation() -> Basis:
	var forward := model_forward.normalized()

	# Already pointing the way Godot does. Nothing to correct.
	if forward.is_equal_approx(Vector3.FORWARD):
		return Basis.IDENTITY

	# Pointing exactly backwards, which is every blaster in this kit. Handled before the
	# general case rather than by it: two opposite vectors have a zero cross product, so
	# the axis below would be the zero vector and the basis would come out full of NaN —
	# and a NaN transform draws nothing at all, with no error anywhere.
	if forward.is_equal_approx(Vector3.BACK):
		return Basis(Vector3.UP, PI)

	# Anything else: the shortest rotation taking the model's forward onto -Z.
	var axis := forward.cross(Vector3.FORWARD)

	if axis.length_squared() < 0.000001:
		return Basis(Vector3.UP, PI)

	return Basis(axis.normalized(), forward.angle_to(Vector3.FORWARD))


func has_model() -> bool:
	return model_path != ""


func has_magazine() -> bool:
	return magazine_path != ""


func _transform(offset: Vector3, rotation: Vector3, scale: float) -> Transform3D:
	var basis := orientation() * Basis.from_euler(
		Vector3(
			deg_to_rad(rotation.x), deg_to_rad(rotation.y), deg_to_rad(rotation.z)
		)
	)
	return Transform3D(basis.scaled(Vector3.ONE * scale), offset)


## Checks the document without loading a single mesh.
##
## [b]Loads nothing, for [DotWeaponDef.validate]'s reason[/b]: this has to be runnable
## on a dedicated server that has no art installed and never will have, so that a typo
## in a scale or a zeroed forward vector is caught at boot rather than the first time
## somebody with a screen joins.
func validate() -> DotResult:
	if id == &"":
		return DotResult.fail(DotError.CODE_INVALID, "Weapon art needs an id.")

	var where := String(id)

	if model_forward.length_squared() < 0.000001:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"model_forward is zero, so there is no way to tell which end the muzzle is.",
			where
		)

	if view_scale <= 0.0 or world_scale <= 0.0:
		return DotResult.fail(
			DotError.CODE_INVALID, "A scale of zero draws nothing at all.", where
		)

	if magazine_path != "" and not has_model():
		return DotResult.fail(
			DotError.CODE_INVALID,
			"A magazine with no weapon to come out of.",
			where
		)

	for i in range(attachments.size()):
		var entry: Dictionary = attachments[i]
		if str(entry.get("path", "")) == "":
			return DotResult.fail(
				DotError.CODE_INVALID,
				"Attachment %d has no path." % i,
				where
			)

	return DotResult.success(null)


func describe() -> Dictionary:
	return {
		"id": String(id),
		"model": model_path,
		"pose": String(pose),
		"weight": weight,
		"attachments": attachments.size(),
		"magazine": magazine_path,
	}


func _to_string() -> String:
	return "ZeeWeaponArt(%s, %s)" % [
		String(id), model_path.get_file() if model_path != "" else "no model"
	]
