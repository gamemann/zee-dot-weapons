extends Node

## Every weapon in the pack, laid out on a rack with a marker on each muzzle.
##
## [codeblock]
## tools/screenshot.sh --rack
## godot --path . res://tools/rack.tscn -- --seconds 20
## [/codeblock]
##
## [b]This is art documentation and a test at the same time.[/b] The suite can prove a
## model loads and that its muzzle measured a plausible number; it cannot prove the
## number is at the end of the barrel rather than at the stock, and it cannot prove that
## the thing which loaded is the weapon anybody meant. A picture of all twenty-seven with
## a red pip on every muzzle answers both at a glance, and it was how the first
## orientation bug in this repository was found.
##
## Each weapon is drawn through [ZeeWorldModel], so what is on the rack is exactly what
## another player sees in somebody's hands — not a separate preview path that could be
## right while the real one is wrong.

const CHANNEL := "zee.rack"

## Weapons per row. Four rows of seven, near enough, at a readable size.
const COLUMNS := 7

## [b]Rows are further apart than columns, and by more than looks necessary.[/b] The
## longest weapon in the kit is 1.39 m and the widest is 0.25 m, so a square grid either
## wastes half the frame or lets the sniper lie across the row behind it — which reads as
## a model in the wrong place rather than as a spacing mistake.
const SPACING := Vector3(2.0, 0.0, 2.55)


func _ready() -> void:
	_arm_exit_timer()
	_build()


func _build() -> void:
	var all := ZeeWeaponArtTable.all()

	for i in range(all.size()):
		var art := all[i]
		var at := Vector3(
			(float(i % COLUMNS) - float(COLUMNS - 1) * 0.5) * SPACING.x,
			0.0,
			float(i / COLUMNS) * SPACING.z
		)

		var model := ZeeWorldModel.new()
		model.name = "Rack_%s" % String(art.id)
		$Rack.add_child(model)
		model.position = at

		var res := model.equip(art)

		if not res.ok:
			DotLog.warn(
				CHANNEL, "nothing to rack", {"id": String(art.id), "why": res.error.message}
			)
			continue

		if art.has_model():
			# Lifted clear of the weapon. A pip at the muzzle's exact position is inside
			# the barrel, which is the same picture as no pip at all — and "no pip" is
			# what a muzzle measured at the wrong end also looks like.
			_pip(
				model.muzzle_transform().origin + Vector3(0.0, 0.22, 0.0),
				Color(1.0, 0.2, 0.15)
			)

		_label(art, at)

	# [b]The reference mark: three green pips running along Godot's forward.[/b] Every
	# weapon's red muzzle pip must sit on the same side of its own body as these sit of
	# the rack's origin. That is the whole check, and it is the one that found every
	# blaster in this pack facing backwards on the first render.
	for i in range(3):
		_pip(Vector3(-6.4, 0.22, -0.7 - float(i) * 0.5), Color(0.2, 1.0, 0.35))


## A small sphere, so a position can be seen rather than trusted.
func _pip(at: Vector3, colour: Color) -> void:
	var dot := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	dot.mesh = sphere

	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	dot.material_override = material

	dot.position = at
	$Rack.add_child(dot)


func _label(art: ZeeWeaponArt, at: Vector3) -> void:
	var text := Label3D.new()
	text.text = String(art.id)
	text.font_size = 96
	text.pixel_size = 0.0018
	text.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	text.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	text.position = at + Vector3(0.0, 0.01, 0.85)
	text.modulate = Color(0.9, 0.93, 1.0)
	$Rack.add_child(text)


func _arm_exit_timer() -> void:
	var args := OS.get_cmdline_user_args()

	for i in range(args.size()):
		if args[i] == "--seconds" and i + 1 < args.size():
			var after := args[i + 1].to_float()
			if after > 0.0:
				get_tree().create_timer(after).timeout.connect(func() -> void:
					get_tree().quit()
				)
