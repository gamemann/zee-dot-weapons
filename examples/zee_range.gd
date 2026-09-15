extends Node

## A firing range you can walk around, holding every weapon in the pack.
##
## [codeblock]
## godot --path . res://examples/zee_range.tscn
##
## # Exits on its own, so a screenshot sweep can open it:
## godot --path . res://examples/zee_range.tscn -- --seconds 3 --weapon sniper
## [/codeblock]
##
## WASD to move, space to jump, ctrl to crouch, mouse to look, left click to fire, right
## click to bash, R to reload, 1-5 for the slots, Q for the last weapon, wheel to cycle,
## F1 to dump the rig's state, escape to release the mouse.
##
## [b]This is the half of the test suite no assertion reaches.[/b] `zee_selftest.tscn`
## proves every weapon loads, measures and simulates; not one of its 133 checks can tell
## you whether the sniper is held at a sensible angle, whether the arms are in front of
## the gun or through it, or whether a reload reads as a reload. Those are decided by
## opening this and looking, which is what `tools/screenshot.sh` automates.
##
## [b]The controller is wired by nothing.[/b] `zee_range.tscn` sets no [DotNodeRef]s at
## all: the view finds the camera by type, the controller finds the collider and the
## view by type, and the rig finds the view model the same way. An inspector-configured
## project overrides any of them; this is what the defaults cost.

const CHANNEL := "zee.range"

## Where the player stands, far enough back that a target is a shot rather than a poke.
const SPAWN := Vector3(0.0, 0.2, 14.0)

const TARGETS := "res://assets/blaster-kit/"

@onready var _controller: DotFpsController = $Player/Controller
@onready var _camera: Camera3D = $Player/Head/Camera
@onready var _readout: Label = $UI/Readout
@onready var _crosshair: Label = $UI/Crosshair

var _rig: ZeeWeaponRig = null
var _view: ZeeViewModel = null
var _input := ZeeWeaponInput.make()

## The simulation tick. Advanced in `_physics_process`, never read from a clock.
var _tick: int = 0

## Every shot's impact, drawn as a short-lived marker so a hit is visible.
var _markers: Array[Node3D] = []


func _ready() -> void:
	ZeeWeaponInput.register_default_actions()
	_build_world()
	_build_weapons()
	_arm_exit_timer()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_controller.landed.connect(_on_landed)
	_controller.teleport(SPAWN, 0.0, 0.0)

	_crosshair.text = "+"

	print("zee-dot-weapons range — %d weapons" % ZeeWeaponIds.all().size())
	print("1-5 slots · wheel cycles · LMB fire · RMB bash · R reload · F1 state")

	_equip_requested()


# --- Wiring -----------------------------------------------------------------

func _build_weapons() -> void:
	# The view model hangs off the camera, which is what makes it a view model: it
	# inherits the camera's pitch for free and needs no code to follow it.
	_view = ZeeViewModel.new()
	_view.name = "ViewModel"
	_view.arm_skin = "res://assets/arms/Textures/texture-c.png"
	# `--no-arms` draws the weapon alone. Not a debug toggle left in by accident: it is
	# how you tell an arm drawn wrongly from a weapon drawn wrongly, and the two look
	# identical in a screenshot until one of them is switched off.
	_view.show_arms = _argument("--no-arms") == ""
	_camera.add_child(_view)

	_rig = ZeeWeaponRig.new()
	_rig.name = "WeaponRig"
	_rig.role = ZeeWeaponRig.Role.LOCAL
	# A single-player range is its own authority. A client joining a server would set
	# this false and let the server's copy of the same rig decide.
	_rig.authority = true
	_rig.tick_rate = ZeeWeaponPack.TICK_RATE
	_rig.view_model_ref = DotNodeRef.of_path(_view.get_path())
	$Player.add_child(_rig)

	var res := _rig.setup()

	if not res.ok:
		DotLog.error(CHANNEL, "the rig would not set up", {"why": res.error.message})
		return

	_rig.give_everything()
	_rig.used.connect(_on_used)
	_rig.bashed.connect(_on_used)
	_rig.equipped.connect(_on_equipped)


## Honours `--weapon <id>` so a screenshot sweep can ask for one by name.
func _equip_requested() -> void:
	var wanted := _argument("--weapon")

	if wanted == "":
		return

	var def: DotWeaponDef = ZeeWeaponPack.table().get(StringName(wanted), null)

	if def == null:
		DotLog.warn(CHANNEL, "no such weapon", {"asked_for": wanted})
		return

	# Forced rather than requested: a switch takes deploy_ticks to finish, and a
	# screenshot three seconds later of a weapon that is still coming up is a screenshot
	# of the bottom of the screen.
	_rig.arsenal.give(def.id)
	_rig.arsenal.select(def.slot, 0)

	for i in range(200):
		_rig.simulate_tick(DotWeaponCommand.new(), i)


# --- The frame --------------------------------------------------------------

func _process(_delta: float) -> void:
	_input.sample()

	var state := _controller.render_state()

	# [b]The view is driven every render frame, not every tick.[/b] Sway and bob are
	# interpolation between ticks; doing them on the tick quantises them to the tick rate
	# and undoes the point of having them.
	_rig.drive_view(
		Vector2(state.yaw, state.pitch),
		Vector2(state.velocity.x, state.velocity.z).length(),
		state.mode != DotFpsState.Mode.AIR,
		state.crouch_fraction > 0.5
	)

	_draw_readout()


func _physics_process(_delta: float) -> void:
	_tick += 1

	var state := _controller.render_state()

	# [b]Copied from the movement, never sampled again.[/b] Two samples of the same mouse
	# a frame apart differ, and a shot fired along an angle the movement never had is a
	# shot that leaves the muzzle somewhere the player was not looking.
	_input.set_aim(state.yaw, state.pitch)

	var command := _input.take(8)
	var outcome := _rig.simulate_tick(command, _tick)

	# The range is its own authority, so it resolves its own shots. A client would send
	# the command and let the server do this.
	for shot in outcome.shots:
		_trace(shot)

	for spawn in outcome.spawns:
		_launch(spawn)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)

	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).physical_keycode == KEY_F1:
			for line in _rig.describe_lines():
				print(line)


# --- Being told what happened -----------------------------------------------

func _on_used(outcome: DotWeaponOutcome) -> void:
	# Nothing here may run on a replayed tick, and nothing here is replayed: a range is
	# its own authority so there is nothing to reconcile. In a networked game this is
	# where `ctx.replayed` earns its keep.
	if outcome.kind == DotWeaponOutcome.KIND_SWING:
		return


func _on_equipped(id: StringName) -> void:
	var def: DotWeaponDef = ZeeWeaponPack.table().get(id, null)

	if def != null:
		print("equipped %s" % def.name_or_id())


func _on_landed(impact: float) -> void:
	_rig.on_landed(impact)


# --- Resolving --------------------------------------------------------------

## Traces one shot and marks where it landed.
##
## [b]A range, not a combat system.[/b] dot-combat is what resolves a shot properly —
## hitboxes, hit groups, lag compensation, armour — and this pack does not depend on it
## for anything but its [DotShot] type. What this does is put a mark on a wall so you can
## see where the pellets went, which is the only question a firing range asks.
func _trace(shot: DotShot) -> void:
	var space: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state

	for pellet in shot.pellets:
		var query := PhysicsRayQueryParameters3D.create(
			shot.origin, shot.origin + pellet * shot.max_range
		)
		query.collide_with_areas = false

		var hit: Dictionary = space.intersect_ray(query)

		if hit.is_empty():
			continue

		_mark(hit["position"] as Vector3)


## A projectile, as the simplest thing that can possibly fly.
func _launch(spawn: DotWeaponSpawn) -> void:
	var body := RigidBody3D.new()
	var mesh := MeshInstance3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	var ball := SphereMesh.new()

	sphere.radius = maxf(0.05, spawn.radius)
	ball.radius = sphere.radius
	ball.height = sphere.radius * 2.0

	shape.shape = sphere
	mesh.mesh = ball
	mesh.material_override = _material(Color(1.0, 0.55, 0.15))

	body.add_child(shape)
	body.add_child(mesh)
	body.gravity_scale = spawn.gravity_scale
	body.position = spawn.origin
	body.linear_velocity = spawn.velocity

	$World.add_child(body)

	# The spawn's own life is a hard ceiling rather than a hint: a projectile that
	# forgets to free itself is a leak that looks like a slow problem in the game rather
	# than a bug in one weapon.
	var timer := get_tree().create_timer(
		float(spawn.life_ticks) / float(ZeeWeaponPack.TICK_RATE)
	)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(body):
			_mark(body.global_position)
			body.queue_free()
	)


func _mark(at: Vector3) -> void:
	var dot := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.04
	sphere.height = 0.08
	dot.mesh = sphere
	dot.material_override = _material(Color(1.0, 0.85, 0.2))
	dot.position = at
	$World.add_child(dot)

	_markers.append(dot)

	# Bounded rather than timed: at eleven hundred rounds a minute a timed cleanup still
	# leaves a few thousand markers on screen, and the frame rate is what tells you.
	while _markers.size() > 200:
		var oldest: Node3D = _markers.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


# --- The world --------------------------------------------------------------

## A floor, a back wall and the kit's own targets, built in code.
##
## In code because this example is meant to be read top to bottom, and a scene file is
## the one part of a Godot project that cannot be. A real level is a scene an artist
## made; this is a page you can check.
func _build_world() -> void:
	var world := $World

	_add_box(world, Vector3(70.0, 1.0, 70.0), Vector3(0.0, -0.5, 0.0), Color(0.22, 0.24, 0.27))

	# A back wall to catch the pellets, so a shotgun's pattern is visible as a pattern.
	_add_box(world, Vector3(40.0, 8.0, 1.0), Vector3(0.0, 4.0, -18.0), Color(0.3, 0.32, 0.36))
	_add_box(world, Vector3(1.0, 8.0, 36.0), Vector3(-20.0, 4.0, 0.0), Color(0.28, 0.3, 0.34))
	_add_box(world, Vector3(1.0, 8.0, 36.0), Vector3(20.0, 4.0, 0.0), Color(0.28, 0.3, 0.34))

	# Something to jump on, so the airborne spread penalty can be felt.
	for i in range(4):
		_add_box(
			world,
			Vector3(3.0, 0.5 + float(i) * 0.5, 3.0),
			Vector3(-11.0, (0.5 + float(i) * 0.5) * 0.5, 2.0 - float(i) * 3.5),
			Color(0.35, 0.3, 0.26)
		)

	_add_targets(world)


## The kit's targets and crates, at the ranges the weapons are tuned for.
##
## Placed by distance on purpose: the shotgun stops at 26 m and the sniper reaches a
## kilometre, so a range with everything at one distance tells you nothing about either.
func _add_targets(world: Node3D) -> void:
	var rows := [
		{"z": -4.0, "model": "target-large.glb", "count": 3, "spacing": 4.0, "y": 1.4},
		{"z": -10.0, "model": "target-small.glb", "count": 5, "spacing": 3.0, "y": 1.5},
		{"z": -16.0, "model": "target-detail.glb", "count": 7, "spacing": 2.4, "y": 1.6},
	]

	for row: Dictionary in rows:
		var count := int(row["count"])
		var spacing := float(row["spacing"])

		for i in range(count):
			var model := ZeeModelCache.instantiate(TARGETS + str(row["model"]))
			if model == null:
				continue

			# [b]Turned a quarter and lifted off the floor.[/b] The target discs are
			# modelled in the YZ plane — five centimetres thick along X — so dropped in
			# untouched they face sideways and read as saucers lying on the ground. They
			# are also 34 cm across, which is a dinner plate at thirty metres, so they
			# are scaled up to something a sniper can be aimed at.
			model.rotation = Vector3(0.0, PI * 0.5, 0.0)
			model.scale = Vector3.ONE * 3.0
			model.position = Vector3(
				(float(i) - float(count - 1) * 0.5) * spacing,
				float(row["y"]),
				float(row["z"])
			)

			# A body behind the mesh, so a shot at one actually stops there and leaves a
			# mark. A target you can shoot through is a target that teaches nothing.
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.2, 1.0, 1.0)
			shape.shape = box
			body.add_child(shape)
			body.position = model.position
			body.rotation = model.rotation
			world.add_child(body)

			world.add_child(model)

	# Crates for cover, and because a physics prop is the quickest way to see that a
	# launcher's splash is doing something.
	for i in range(6):
		var crate := ZeeModelCache.instantiate(TARGETS + "crate-medium.glb")
		if crate == null:
			continue
		crate.position = Vector3(
			-6.0 + float(i) * 2.4, 0.0, 6.0 - float(i % 3) * 2.0
		)
		world.add_child(crate)


func _add_box(parent: Node3D, size: Vector3, at: Vector3, colour: Color) -> void:
	var body := StaticBody3D.new()
	var mesh := MeshInstance3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var block := BoxMesh.new()

	box.size = size
	block.size = size
	mesh.mesh = block
	mesh.material_override = _material(colour)

	shape.shape = box
	body.add_child(shape)
	body.add_child(mesh)
	body.position = at
	parent.add_child(body)


func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	return material


# --- The readout ------------------------------------------------------------

func _draw_readout() -> void:
	var def := _rig.current_def()

	if def == null:
		_readout.text = "nothing in hand"
		return

	var slot := _rig.arsenal.current()
	var ammo := _rig.arsenal.ammo().count(def.ammo_type)

	var rounds := "∞"

	if def.uses_magazine():
		rounds = "%d / %d" % [slot.magazine, ammo]
	elif def.uses_ammo():
		rounds = str(ammo)

	_readout.text = "%s\n%s\n%s%s" % [
		def.name_or_id(),
		rounds,
		DotWeaponDef.Fire.keys()[def.fire_mode].to_lower(),
		"  ·  reloading" if _rig.arsenal.is_reloading() else "",
	]


# --- Exiting ----------------------------------------------------------------

## Quits after `--seconds N`, so a screenshot sweep can open this without a person.
func _arm_exit_timer() -> void:
	var seconds := _argument("--seconds")

	if seconds == "":
		return

	var after := seconds.to_float()

	if after <= 0.0:
		return

	get_tree().create_timer(after).timeout.connect(func() -> void:
		get_tree().quit()
	)


## One `--name value` argument from the command line, after the bare `--`.
##
## [b]The bare `--` matters.[/b] Everything before it is Godot's and everything after it
## is the project's, and an argument passed without it is swallowed by the engine —
## which presents as the flag being ignored with no error at all.
static func _argument(name: String) -> String:
	var args := OS.get_cmdline_user_args()

	for i in range(args.size()):
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]

	return ""
