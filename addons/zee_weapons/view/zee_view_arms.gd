class_name ZeeViewArms
extends Node3D

## The hands holding the weapon, in first person.
##
## [b]Two meshes lifted out of a whole character, not an arms model.[/b] Kenney's blocky
## characters are six rigid parts — head, torso, two arms, two legs — and the two arms
## are usable on their own, which is the only reason this pack has first-person hands at
## all without anybody modelling any. Everything else in the character is deleted on
## load, because a torso at the camera's own position fills the screen with somebody's
## chest.
##
## [b]All eighteen characters share byte-identical arm geometry and differ only by a
## texture atlas[/b], so a game changing whose hands these are changes one texture path
## and no mesh. That is why [member skin] is a path and not a model.
##
## [b]Poses are hand-authored numbers, and they are numbers because there is no rig.[/b]
## These arms have no skeleton and no animation track — they are rigid boxes on a
## transform each. So a "pose" here is a position and a rotation per arm, which is
## enough for the four ways this pack holds things and is honestly all the kit can
## support. A game with a skinned first-person rig replaces this node entirely; the
## view model only requires that something answers [method set_pose].

const CHANNEL := "zee.arms"

## The nodes worth keeping out of a blocky character. Everything else is thrown away.
const ARM_LEFT := "arm-left"
const ARM_RIGHT := "arm-right"

@export_group("Model")

## The character the arms come from.
@export_file("*.glb", "*.gltf", "*.tscn", "*.scn") var model_path: String = \
	"res://assets/arms/character-a.glb"

## The atlas painted onto them. Empty keeps whatever the model shipped with.
##
## [b]This is how the hands match the player.[/b] Every atlas in the kit shares one UV
## layout, so swapping it recolours the sleeves and the skin and nothing else needs
## touching — which is what lets a game hand a player's own avatar texture straight in.
@export_file("*.png", "*.jpg", "*.webp") var skin: String = ""

@export_group("Placement")

## Scale of the arms.
##
## [b]0.20, and it is set by reach rather than by taste.[/b] Measured, the blocky
## character is **2.7 m tall** — a stylised giant, not a person — and one arm is a
## 0.4 x 1.1 x 0.4 box. The shoulders below sit about 0.35 m out and 0.35 m down; the
## weapon's grip is about 0.45 m out and 0.17 m down. A fifth of a metre is the distance
## between those two points, so it is the length the arm has to be.
##
## [b]Thickness is why this cannot simply be made bigger.[/b] The box is 0.4 wide in its
## own units, so the scale sets the forearm's thickness as well as its length: at 0.20 an
## arm is 8 cm across, which at a third of a metre from a 90-degree camera is about a
## seventh of the screen. At 0.36 it was 14 cm at 0.1 m out — the whole screen — and the
## render was two cream slabs with the rifle somewhere behind them.
@export_range(0.05, 5.0, 0.01) var arm_scale: float = 0.20

## Nudge applied to both arms after the pose, for a game with a different camera height.
@export var arm_offset: Vector3 = Vector3.ZERO

var _left: Node3D = null
var _right: Node3D = null
var _pose: StringName = &"rifle"
var _built: bool = false


# --- Building ---------------------------------------------------------------

## Loads the model and keeps the two arms.
##
## [b]Failing to find an arm is not an error.[/b] A game substituting its own model may
## name the nodes anything, and hands that do not appear are a visual disappointment
## rather than a broken weapon — the gun still fires. It is logged once, at WARN,
## because it is also not something anybody meant.
func build() -> DotResult:
	if _built:
		return DotResult.success(null)

	var model := ZeeModelCache.instantiate(model_path)

	if model == null:
		return DotResult.fail(
			DotError.CODE_IO, "No arms model at %s." % model_path
		)

	_left = _find_named(model, ARM_LEFT)
	_right = _find_named(model, ARM_RIGHT)

	# [b]The arms are lifted out and the rest of the character is thrown away whole.[/b]
	# Deleting the other parts in place looks equivalent and is not: the arms can be
	# nested any number of levels down, so "remove every child that is not an arm" also
	# removes the node an arm is sitting inside. Reparenting first and freeing the
	# remains afterwards cannot get that wrong at any depth.
	for arm in [_left, _right]:
		if arm != null:
			arm.get_parent().remove_child(arm)
			# Cleared before reparenting: an imported scene stamps every node's `owner`
			# with the scene root, and adding a node whose owner is a tree it is no
			# longer in warns on every single load.
			arm.owner = null
			add_child(arm)

	model.queue_free()

	if _left == null or _right == null:
		DotLog.warn(
			CHANNEL,
			"could not find both arms in the model; first person will show fewer hands "
			+ "than it should",
			{"model": model_path, "left": _left != null, "right": _right != null}
		)

	if skin != "":
		_apply_skin(self)

	# The arms are drawn on top of the world, the same as the weapon: an arm that
	# clips into a wall the player is standing against is the single most common
	# first-person artefact, and the fix is the one every game in this genre uses.
	_set_on_top(self)

	_built = true
	set_pose(_pose)
	return DotResult.success(null)


## How the arms are held. Unknown names fall back to the rifle pose.
func set_pose(pose: StringName) -> void:
	_pose = pose

	if not _built:
		return

	var placement := _placement_for(pose)

	if _left != null:
		_left.transform = _arm_transform(placement["left"], placement["left_rotation"])

	if _right != null:
		_right.transform = _arm_transform(
			placement["right"], placement["right_rotation"]
		)


func current_pose() -> StringName:
	return _pose


func has_arms() -> bool:
	return _left != null or _right != null


# --- Poses ------------------------------------------------------------------

## Where each arm's SHOULDER sits, and which way the arm points from it.
##
## [b]These are shoulders, not hands, and the mesh is why.[/b] Measured, an arm in this
## kit is a 0.4 x 1.1 x 0.4 box whose origin sits at the [i]top[/i] of it: the mesh runs
## from y=0 down to y=-1. So the transform below places the shoulder and the hand follows
## an arm's length away in whatever direction the rotation points.
##
## [b]The pitch is positive, and that is the whole of the first attempt being wrong.[/b]
## Rotating the arm by +90 degrees about X takes its local "down" onto Godot's forward,
## which is an arm held out in front of you. Negative takes it onto backward — an arm
## pointing behind the camera. Seventy-odd degrees is forward and slightly down, which is
## where a hand on a grip actually is.
##
## [b]Every shoulder is in FRONT of the camera, and anatomy is the trap.[/b] A real
## shoulder is behind the eye, so the natural z here is positive — and a positive z puts
## the shoulder behind the near clip plane, which does not hide the arm. It slices it,
## and what draws is the cut face: a pale slab across the lower half of the screen that
## reads as a broken model rather than as a clipping plane. Every z below is negative,
## and the arm simply starts where the player can see it.
##
## [b]The yaws are mirrored, and getting the signs the wrong way round splays the arms
## outward across the gun[/b] instead of bringing them in under it. The left arm reaches
## right (negative yaw) and the right arm reaches left (positive), because both hands are
## converging on one weapon held slightly right of centre.
##
## [b]How these were derived, so the next person can redo them rather than nudge them.[/b]
## Each pair is a shoulder and a hand: the hand is where the weapon's grip and fore-end
## actually are (see [method ZeeWeaponArtTable.pose_offset]), the shoulder is placed low
## and about 0.3 m out, and the rotation is the one that points the arm from the first at
## the second — pitch from the vertical rise, yaw from the sideways offset.
## [member arm_scale] is then the distance between them.
##
## [b]The pitches are past 90 degrees, and that is a forearm, not a mistake.[/b] The
## shoulder is below the weapon and the hand is above it, so the arm rises as it goes
## forward — which is what a hand coming up from the bottom of the screen onto a grip
## looks like. Under 90 the arm would go forward and down, out of frame.
##
## [b]The right hand is on the grip and the left is further out on the fore-end[/b],
## which is what makes a two-handed weapon read as two-handed. A pistol brings the left
## hand in to meet the right rather than removing it, because a single floating arm reads
## as a bug rather than as a stance.
func _placement_for(pose: StringName) -> Dictionary:
	match pose:
		&"pistol":
			return {
				"left": Vector3(0.00, -0.30, -0.42),
				"left_rotation": Vector3(140.0, -44.0, 0.0),
				"right": Vector3(0.19, -0.34, -0.32),
				"right_rotation": Vector3(146.0, 42.0, 0.0),
			}
		&"heavy":
			return {
				"left": Vector3(0.02, -0.30, -0.56),
				"left_rotation": Vector3(140.0, -44.0, 0.0),
				"right": Vector3(0.21, -0.34, -0.34),
				"right_rotation": Vector3(146.0, 42.0, 0.0),
			}
		&"melee":
			return {
				"left": Vector3(-0.16, -0.32, -0.34),
				"left_rotation": Vector3(132.0, -34.0, 0.0),
				"right": Vector3(0.19, -0.34, -0.30),
				"right_rotation": Vector3(144.0, 40.0, 0.0),
			}
		&"thrown":
			return {
				"left": Vector3(-0.16, -0.32, -0.32),
				"left_rotation": Vector3(130.0, -32.0, 0.0),
				"right": Vector3(0.17, -0.34, -0.28),
				"right_rotation": Vector3(140.0, 40.0, 0.0),
			}
		_:
			return {
				"left": Vector3(0.02, -0.30, -0.50),
				"left_rotation": Vector3(142.0, -45.0, 0.0),
				"right": Vector3(0.20, -0.36, -0.34),
				"right_rotation": Vector3(148.0, 45.0, 0.0),
			}


func _arm_transform(position: Vector3, rotation: Vector3) -> Transform3D:
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(rotation.x), deg_to_rad(rotation.y), deg_to_rad(rotation.z)
	))
	return Transform3D(
		basis.scaled(Vector3.ONE * arm_scale), position + arm_offset
	)


# --- Internals --------------------------------------------------------------

func _find_named(node: Node, wanted: String) -> Node3D:
	if node.name == wanted and node is Node3D:
		return node

	for child in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found

	return null


func _apply_skin(root: Node) -> void:
	if not ResourceLoader.exists(skin):
		DotLog.warn(CHANNEL, "no arm skin at that path", {"skin": skin})
		return

	var texture: Variant = load(skin)

	if not (texture is Texture2D):
		DotLog.warn(CHANNEL, "the arm skin is not a texture", {"skin": skin})
		return

	for mesh in _meshes(root):
		# An override on the instance rather than an edit to the material: the material
		# came off a shared imported mesh, and writing to it would recolour every other
		# instance of the same model in the scene, including the third-person one.
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mesh.material_override = material


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


func describe() -> Dictionary:
	return {
		"built": _built,
		"pose": String(_pose),
		"left": _left != null,
		"right": _right != null,
		"model": model_path,
		"skin": skin,
	}
