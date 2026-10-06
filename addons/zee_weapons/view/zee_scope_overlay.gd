@tool
class_name ZeeScopeOverlay
extends Control

## What a player sees through a scope: the world through a circle, black around it, and a
## reticle. Draws itself, so it ships no texture and a game restyles it from these exports.
##
## [b]A Control a game places, not something the view model adds.[/b] The view model is a
## 3D node under the camera and knows nothing about the HUD's canvas layer, its scaling or
## what else is drawn over the world. The game puts one of these in its HUD, full-rect, and
## sets [member fraction] each frame from [method ZeeViewModel.aim_fraction] whenever
## [method ZeeViewModel.is_scoped] — or from its own rule.

## How visible, 0 to 1. Faded rather than switched so the cut from the weapon to the scope
## is not a flash of black.
@export_range(0.0, 1.0, 0.01) var fraction: float = 0.0:
	set(value):
		fraction = clampf(value, 0.0, 1.0)
		queue_redraw()

## The circle's diameter as a fraction of the screen's shorter side.
@export_range(0.2, 1.0, 0.01) var circle: float = 0.9

@export var surround_colour: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var reticle_colour: Color = Color(0.0, 0.0, 0.0, 0.9)

## Reticle line width in pixels at a 1080-pixel-tall screen; scaled with the screen.
@export_range(0.5, 8.0, 0.5) var reticle_width: float = 2.0

## A soft dark edge inside the circle, as a fraction of its radius. 0 for a hard edge.
@export_range(0.0, 0.5, 0.01) var vignette: float = 0.12


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchors AND offsets: `set_anchors_preset` alone keeps the zero offsets a new Control
	# has, so it fills nothing and the scope never draws (the first render had none).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	if fraction <= 0.0:
		return

	var size_px := size
	var centre := size_px * 0.5
	var radius := minf(size_px.x, size_px.y) * circle * 0.5
	var surround := Color(surround_colour, surround_colour.a * fraction)

	# The surround as four rectangles and a ring of quads around the circle: Godot has no
	# "draw everything but a circle", and a polygon with a hole is not one call either.
	draw_rect(Rect2(0.0, 0.0, centre.x - radius, size_px.y), surround)
	draw_rect(Rect2(centre.x + radius, 0.0, size_px.x - centre.x - radius, size_px.y), surround)
	draw_rect(Rect2(centre.x - radius, 0.0, radius * 2.0, centre.y - radius), surround)
	draw_rect(Rect2(centre.x - radius, centre.y + radius, radius * 2.0, size_px.y - centre.y - radius), surround)
	_draw_corners(centre, radius, surround)

	if vignette > 0.0:
		var steps := 8
		for i in range(steps):
			var inner := radius * (1.0 - vignette * float(i + 1) / float(steps))
			var alpha := surround.a * 0.12
			draw_arc(centre, inner, 0.0, TAU, 96, Color(surround, alpha), radius * vignette / float(steps) + 1.0)

	var width := maxf(1.0, reticle_width * size_px.y / 1080.0)
	var line := Color(reticle_colour, reticle_colour.a * fraction)
	draw_line(centre - Vector2(radius, 0.0), centre + Vector2(radius, 0.0), line, width)
	draw_line(centre - Vector2(0.0, radius), centre + Vector2(0.0, radius), line, width)
	# Heavier posts on the outer half, the way a duplex reticle draws, so the centre is
	# found at a glance and the fine cross does not hide a distant target.
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
		draw_line(centre + direction * radius * 0.5, centre + direction * radius, line, width * 3.0)


## The black between the circle and its bounding square, as a fan per corner.
func _draw_corners(centre: Vector2, radius: float, colour: Color) -> void:
	var segments := 24

	for corner in range(4):
		var start := float(corner) * PI * 0.5
		var square := centre + Vector2(cos(start + PI * 0.25), sin(start + PI * 0.25)) * radius * sqrt(2.0)
		var points := PackedVector2Array([square])

		for i in range(segments + 1):
			var a := start + PI * 0.5 * float(i) / float(segments)
			points.append(centre + Vector2(cos(a), sin(a)) * radius)

		draw_colored_polygon(points, colour)


func describe() -> Dictionary:
	return {"fraction": fraction, "circle": circle}
