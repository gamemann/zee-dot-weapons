class_name ZeeModelCache
extends RefCounted

## Loads a weapon mesh once, measures it once, and hands out copies.
##
## [b]Why a cache at all.[/b] Thirty players holding the same rifle is thirty
## instances of one [PackedScene], not thirty loads of one file. `load()` is cached by
## the engine, so the loading half of this is a convenience; the measuring half is not,
## and that is the part that earns the file. Walking a scene tree to merge mesh bounding
## boxes costs an instantiate, and doing it every time somebody switches weapons is a
## hitch on every switch.
##
## [b]Measuring is how the muzzle is found.[/b] The alternative is a hand-authored
## offset per weapon, and eighteen hand-authored offsets are eighteen chances to be
## quietly wrong — including on `blaster-e`, whose mesh origin is at the stock rather
## than at the centre, so the offset that is correct for the other seventeen puts its
## muzzle somewhere behind the player's ear. A measurement cannot drift from the model
## it measured.
##
## [b]Nothing here is called on a dedicated server.[/b] A server resolves weapons,
## damage and hit registration without ever asking what a weapon looks like; if this
## file is reached in a headless build, something has asked a simulation question of
## the art layer.

const CHANNEL := "zee.models"

## Path -> PackedScene.
static var _scenes: Dictionary = {}

## Path -> AABB in the model's own space.
static var _bounds: Dictionary = {}

## Paths already reported as missing, so a model that is not there is logged once
## rather than once per frame for as long as somebody is holding it.
static var _complained: Dictionary = {}


## The scene at [param path], loaded at most once.
static func scene(path: String) -> DotResult:
	if path == "":
		return DotResult.fail(DotError.CODE_INVALID, "No model path.")

	if _scenes.has(path):
		return DotResult.success(_scenes[path])

	if not ResourceLoader.exists(path):
		return DotResult.fail(
			DotError.CODE_IO,
			"No model at %s. A weapon delivered in a content pack needs that pack " % path
			+ "mounted before it can be drawn."
		)

	var loaded: Variant = load(path)

	if not (loaded is PackedScene):
		return DotResult.fail(
			DotError.CODE_INVALID, "%s is not a scene." % path
		)

	_scenes[path] = loaded
	return DotResult.success(loaded)


## A fresh instance of the model at [param path], or null.
##
## [b]Returns null rather than failing loudly for a missing model[/b], because a missing
## mesh must not stop a weapon from working. The gun still fires, still costs
## ammunition and still kills; it is invisible, which is a visual bug and not a
## simulation one. It is logged once per path, at WARN, because somebody should
## eventually look.
static func instantiate(path: String) -> Node3D:
	var res := scene(path)

	if not res.ok:
		if not _complained.has(path):
			_complained[path] = true
			DotLog.warn(
				CHANNEL,
				"could not load a weapon model; the weapon will be invisible",
				{"path": path, "why": res.error.message}
			)
		return null

	var made: Node = (res.value as PackedScene).instantiate()

	if made is Node3D:
		return made

	# A .glb always instantiates as a Node3D. A .tscn a game substituted might not, and
	# adding a Control to a 3D rig is a crash several frames later rather than here.
	made.queue_free()
	DotLog.warn(
		CHANNEL, "a weapon model is not a Node3D and was discarded", {"path": path}
	)
	return null


## The merged bounding box of every mesh in the model, in the model's own space.
##
## Measured once per path. An empty box for a model that could not be loaded, which is
## the right answer: no mesh, no bounds, and a muzzle at the origin.
static func bounds(path: String) -> AABB:
	if _bounds.has(path):
		return _bounds[path]

	var box := AABB()
	var node := instantiate(path)

	if node != null:
		var boxes: Array[AABB] = []
		_collect_bounds(node, Transform3D.IDENTITY, boxes)
		for i in range(boxes.size()):
			box = boxes[i] if i == 0 else box.merge(boxes[i])
		node.queue_free()

	_bounds[path] = box
	return box


## Metres from the model origin to the far end of the mesh along [param forward].
##
## The end of the barrel on every model in this kit. Uses the bounding box corner that
## is furthest along the axis, so it is correct for a mesh centred on its origin and for
## one whose origin sits at the stock — which this kit contains one of.
static func muzzle_distance(path: String, forward: Vector3) -> float:
	var box := bounds(path)

	if box.size.length_squared() <= 0.0:
		return 0.0

	var axis := forward.normalized()
	var best := -INF

	for i in range(8):
		var corner := box.get_endpoint(i)
		best = maxf(best, corner.dot(axis))

	return maxf(0.0, best)


## Drops everything. For a test, and for a game unmounting content it will not remount.
static func clear() -> void:
	_scenes.clear()
	_bounds.clear()
	_complained.clear()


## How many models are held. For a console command and the self-test.
static func describe() -> Dictionary:
	return {
		"scenes": _scenes.keys().size(),
		"measured": _bounds.keys().size(),
		"missing": _complained.keys().size(),
	}


## Every mesh's bounding box, each already in the root's space.
##
## [b]Collected into a list and merged by the caller rather than merged as it goes.[/b]
## [method AABB.merge] with a default-constructed box does not give the other box back —
## it gives a box stretched to include the origin — so a model sitting entirely to one
## side of its origin measures as reaching the origin, and its muzzle comes out at the
## wrong end. Starting from the first real box instead is the whole fix, and it needs
## the boxes in hand to know which one is first.
static func _collect_bounds(node: Node, at: Transform3D, into: Array[AABB]) -> void:
	var here := at

	if node is Node3D:
		here = at * (node as Node3D).transform

	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			into.append(here * mesh.get_aabb())

	for child in node.get_children():
		_collect_bounds(child, here, into)
