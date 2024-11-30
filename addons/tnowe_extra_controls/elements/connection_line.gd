@tool
class_name ConnectionLine
extends Control

## A line that connects between two [Control]s or [Node2D]s. Targets do not need have the same parent, only be in the same [Viewport].

const _style_offsets : Array[float] = [0.0, 1.0, 0.5, 0.5]

## Node that will connect to the beginning of the line.
@export var connect_node1 : CanvasItem:
	set(v):
		connect_node1 = v
		queue_redraw()
		set_process(redraw_every_frame)
## Node that will connect to the end of the line.
@export var connect_node2 : CanvasItem:
	set(v):
		connect_node2 = v
		queue_redraw()
		set_process(redraw_every_frame)
## The beginning of the line, in parent's local coordinates. If a [member connect_node1] is provided, this will be the calculated beginning point.
@export var connect_point1 := Vector2()
## The end of the line, in parent's local coordinates. If a [member connect_node2] is provided, this will be the calculated end point.
@export var connect_point2 := Vector2()

@export_group("Behaviour")
## Allow dragging the beginning (point 1) of the line to connect it to another node, changing [member connect_node1]. Only works on [Control] targets.
@export var allow_drag_pt1 := false
## Allow dragging the end (point 2) of the line to connect it to another node, changing [member connect_node2]. Only works on [Control] targets.
@export var allow_drag_pt2 := false
## Allow dragging the middle of a segment between points to create a new point, as well as dragging a point onto another to remove all points in between.
@export var allow_point_creation := false
## Whether to redraw the line every [code]_process()[/code]. Otherwise, update it with [method CanvasItem.queue_redraw].
@export var redraw_every_frame := true:
	set(v):
		redraw_every_frame = v
		set_process(v)
## Expression to test for [member allow_drag_pt1] and [member allow_drag_pt2] to know if a node can be attached to, executed on that target node. If [code]true[/code], the node will be attached to.[br]
## The [code]from[/code] parameter will be the previously attached node, [code]other[/code] will be the node attached to the opposite end, and [code]line[/code] will be this node. [br]
## For example, expression [code](get_class() == "Button" and other.has_method(&"attach_button_node"))[/code] tests if the new target is a [code]Button[/code] and the other connected node has method [code]attach_button_node[/code]. [br][br]
## [b]Warning: [/b] Some operators are unsupported in expressions, such as [code]is[/code] and ternary [code]if[/code]. Consider calling node's script methods after checking [code]has_method[/code].
@export var drag_reattach_condition := ""
## Expression to execute on the target after reattachment succeeds. Same parameters as [member drag_reattach_condition].
@export var drag_reattach_call_on_success := ""

@export_group("Style")
## The line's color.
@export var line_color := Color.BLACK
## Line width, affecting the clickable area.
@export var line_width := 4.0
## Texture stretching along the line.
@export var line_texture : Texture2D
## If [code]true[/code], [member texture] will repeat along the line. [member CanvasItem.texture_repeat] of the [ConnectionLine] node must be CanvasItem.TEXTURE_REPEAT_ENABLED or CanvasItem.TEXTURE_REPEAT_MIRROR for it to work properly.
@export var line_texture_tile := false
## The spacing between this connection's edge and the node's rect.
@export var connection_margin := 4.0
## Minimum line length. If a redraw of the line would make it shorter than this, it extends back to this length.
@export var line_min_length := 0.0
## The style of the end touching [member connect_node1].
@export_enum("None", "Arrow", "Circle", "Line") var end_style1 := 0
## The style of the end touching [member connect_node2].
@export_enum("None", "Arrow", "Circle", "Line") var end_style2 := 1
## The size of the arrow at the tip of the line. Affects [member end_style1] and [member end_style2] differently.
@export var line_arrow_size := Vector2(6.0, 8.0)
## When a drag via [member allow_drag_pt1] or [member allow_drag_pt2] is possible, this is the color of the hint circle.
@export var drag_hint_color := Color(1.0, 1.0, 1.0, 0.75)
## When a drag via [member allow_drag_pt1] or [member allow_drag_pt2] is possible, this is the radius of the hint circle.
@export var drag_hint_radius := 8.0

var _mouse_over := false
var _mouse_dragging := 0
var _label_clickable_rect := Rect2()
var _path_curve : Curve2D
var _last_rect1 := Rect2()
var _last_rect2 := Rect2()


func _init():
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _process(delta : float):
	if !is_instance_valid(connect_node1) || !is_instance_valid(connect_node2):
		set_process(false)
		return

	# Redraw, but only if positions changed.
	if connect_node1 is Control && _last_rect1 != connect_node1.get_global_rect():
		_last_rect1 = connect_node1.get_global_rect()
		queue_redraw()
		return

	if connect_node1 is Node2D && connect_node1.position != _last_rect1.position:
		_last_rect1.position = connect_node1.position
		queue_redraw()
		return

	if connect_node2 is Control && _last_rect2 != connect_node2.get_global_rect():
		_last_rect2 = connect_node2.get_global_rect()
		queue_redraw()
		return

	if connect_node2 is Node2D && connect_node2.position != _last_rect2.position:
		_last_rect2.position = connect_node2.position
		queue_redraw()
		return


func _has_point(point : Vector2) -> bool:
	if !Rect2(Vector2.ZERO, size).grow(drag_hint_radius).has_point(point):
		return false

	if allow_drag_pt1 && _is_in_radius(connect_point1 - position, point):
		return true

	if allow_drag_pt2 && _is_in_radius(connect_point2 - position, point):
		return true

	if _path_curve != null:
		if _get_overlapped_path_point(point + global_position) != -1:
			return true

		if (point + global_position).distance_squared_to(_path_curve.get_closest_point(point + position)) <= line_width * line_width:
			return true

	if allow_point_creation && _get_overlapped_path_midpoint(point + global_position) != -1:
		return true

	return false


func _draw():
	var xform_start := Transform2D(Vector2(1.0, 0.0), Vector2(0.0, 1.0), connect_point1 + global_position)
	var xform_end := Transform2D(Vector2(1.0, 0.0), Vector2(0.0, 1.0), connect_point2 + global_position)
	if connect_node1 != null:
		xform_start = connect_node1.get_global_transform()

	if connect_node2 != null:
		xform_end = connect_node2.get_global_transform()

	var parent_xform_inv : Transform2D = Transform2D.IDENTITY
	if get_parent() is CanvasItem:
		parent_xform_inv = get_parent().get_global_transform().affine_inverse()
		xform_start = parent_xform_inv * xform_start
		xform_end = parent_xform_inv * xform_end

	# Determine line endpoints
	var line_start := xform_start.origin
	var line_end := xform_end.origin
	if connect_node1 is Control:
		line_start += xform_start.basis_xform_inv(connect_node1.size * 0.5)

	if connect_node2 is Control:
		line_end += xform_end.basis_xform_inv(connect_node2.size * 0.5)

	var line_direction_forward := (line_end - line_start).normalized()
	var line_direction_backward := (line_start - line_end).normalized()
	if _path_curve != null:
		line_direction_forward = (line_end - _path_curve.get_point_position(_path_curve.point_count - 1)).normalized()
		line_direction_backward = (line_start - _path_curve.get_point_position(0)).normalized()

	# Turn center positions into edge positions (if applicable)
	if connect_node1 is Control && !(connect_node1 is ConnectionLine):
		line_start = xform_start * get_rect_edge_position(
			Rect2(Vector2.ZERO, connect_node1.size),
			xform_start.basis_xform_inv(-line_direction_backward).normalized(),
			connection_margin,
		)

	if connect_node2 is Control && !(connect_node2 is ConnectionLine):
		line_end = xform_end * get_rect_edge_position(
			Rect2(Vector2.ZERO, connect_node2.size),
			xform_end.basis_xform_inv(-line_direction_forward).normalized(),
			connection_margin,
		)

	# Correction if resulting path is too short
	if line_start.distance_squared_to(line_end) < line_min_length * line_min_length:
		var line_start_plus_end := line_start + line_end
		line_start = (line_start_plus_end - line_direction_backward * line_min_length) * 0.5
		line_end = (line_start_plus_end + line_direction_forward * line_min_length) * 0.5

	# Define render rect
	var result_rect := Rect2(line_start, Vector2.ZERO).expand(line_end)
	if _path_curve != null:
		for i in _path_curve.point_count:
			result_rect = result_rect.expand(_path_curve.get_point_position(i))

	result_rect = result_rect.grow(drag_hint_radius)
	position = result_rect.position
	size = result_rect.size

	# Save endpoint positions in parent's local space
	connect_point1 = line_start
	connect_point2 = line_end

	# Finally draw
	var mouse_point := get_local_mouse_position() + position
	if _mouse_dragging == -2: line_start = mouse_point
	if _mouse_dragging == -3: line_end = mouse_point

	draw_set_transform(-position)
	if line_texture == null:
		_draw_line_untextured(line_start, line_end, line_direction_backward, line_direction_forward)

	else:
		_draw_line_textured(line_start, line_end, line_direction_backward, line_direction_forward)

	_draw_arrow(line_end, line_start, end_style1)
	_draw_arrow(line_start, line_end, end_style2)

	# Drag Area Hint
	if allow_drag_pt1 && _is_in_radius(line_start, mouse_point):
		draw_circle(line_start, drag_hint_radius, drag_hint_color)

	if allow_drag_pt2 && _is_in_radius(line_end, mouse_point):
		draw_circle(line_end, drag_hint_radius, drag_hint_color)

	if _path_curve != null:
		var pt_under_mouse := _get_overlapped_path_point(get_global_mouse_position())
		if pt_under_mouse != -1:
			draw_circle(_path_curve.get_point_position(pt_under_mouse), drag_hint_radius, drag_hint_color)
			return

		pt_under_mouse = _get_overlapped_path_midpoint(get_global_mouse_position())
		if pt_under_mouse != -1:
			var prev_point_pos := line_start
			var next_point_pos := line_end
			if pt_under_mouse != 0:
				prev_point_pos = _path_curve.get_point_position(pt_under_mouse - 1)

			if pt_under_mouse < _path_curve.point_count:
				next_point_pos = _path_curve.get_point_position(pt_under_mouse)

			draw_circle((prev_point_pos + next_point_pos) * 0.5, drag_hint_radius, drag_hint_color)

	elif _is_in_radius((line_start + line_end) * 0.5, mouse_point):
		draw_circle((line_start + line_end) * 0.5, drag_hint_radius, drag_hint_color)

## Add a point to the path, in this node's parent's local coordinates. Index 0 is the first point [b]after[/b] the start point.
func path_add(new_index : int, new_position : Vector2):
	if _path_curve == null:
		_path_curve = Curve2D.new()

	_path_curve.add_point(new_position, Vector2.ZERO, Vector2.ZERO, new_index)
	queue_redraw()

## Set a point's position, in this node's parent's local coordinates. Index 0 is the first point [b]after[/b] the start point.
func path_set(point_index : int, new_position : Vector2):
	if _path_curve == null:
		return

	_path_curve.set_point_position(point_index, new_position)
	queue_redraw()

## Remove a point from the path.
func path_remove(index : int):
	if _path_curve == null: return
	if _path_curve.point_count == 1:
		_path_curve = null
		return

	_path_curve.remove_point(index)
	queue_redraw()

## Clear all path points, reverting the path to a straight line.
func path_clear():
	_path_curve = null
	queue_redraw()

## Returns the number of points in the path, not including end points.
func path_get_count(index : int) -> int:
	return 0 if _path_curve == null else _path_curve.point_count

## Utility function to get a point on the intersection of the [code]rect[/code]'s border and the ray cast from its center in [code]direction[/code].
static func get_rect_edge_position(rect : Rect2, direction : Vector2, margin : float = 0.0) -> Vector2:
	var rect_size := rect.size + Vector2(margin, margin)
	var use_vertical := absf(direction.y) > rect_size.y / rect_size.length()
	if use_vertical:
		direction *= 1.0 / absf(direction.y) * rect_size.y * 0.5

	else:
		direction *= 1.0 / absf(direction.x) * rect_size.x * 0.5

	return rect.position + rect.size * 0.5 + direction


func _draw_line_textured(line_start : Vector2, line_end : Vector2, line_direction_backward : Vector2, line_direction_forward : Vector2):
	var line_start_poly := line_start - line_direction_backward * line_arrow_size.y * _style_offsets[end_style1]
	var line_end_poly := line_end - line_direction_forward * line_arrow_size.y * _style_offsets[end_style2]
	if _path_curve == null:
		var length_in_textures := 1.0
		if line_texture_tile:
			length_in_textures = (line_end_poly - line_start_poly).length() * (float(line_texture.get_height()) / line_texture.get_width()) / line_width

		var line_direction_rotated := Vector2(-line_direction_forward.y, line_direction_forward.x) * line_width * 0.5
		draw_colored_polygon(
			[
				line_end_poly - line_direction_rotated,
				line_end_poly + line_direction_rotated,
				line_start_poly + line_direction_rotated,
				line_start_poly - line_direction_rotated,
			], line_color, [
				Vector2(length_in_textures, 0.0),
				Vector2(length_in_textures, 1.0),
				Vector2(0.0, 1.0),
				Vector2(0.0, 0.0),
			], line_texture
		)

	else:
		# TODO: textured line if there is a path 
		_draw_line_untextured(line_start, line_end, line_direction_backward, line_direction_forward)


func _draw_line_untextured(line_start : Vector2, line_end : Vector2, line_direction_backward : Vector2, line_direction_forward : Vector2):
	if _path_curve == null:
		draw_line(
			line_start - line_direction_backward * line_arrow_size.y * _style_offsets[end_style1],
			line_end - line_direction_forward * line_arrow_size.y * _style_offsets[end_style2],
			line_color,
			line_width,
		)

	else:
		draw_line(
			line_start - line_direction_backward * line_arrow_size.y * _style_offsets[end_style1],
			_path_curve.get_point_position(0),
			line_color,
			line_width,
		)
		draw_circle(_path_curve.get_point_position(0), line_width * 0.5, line_color)
		for i in _path_curve.point_count - 1:
			draw_line(
				_path_curve.get_point_position(i),
				_path_curve.get_point_position(i + 1),
				line_color,
				line_width,
			)
			draw_circle(_path_curve.get_point_position(i + 1), line_width * 0.5, line_color)

		draw_line(
			_path_curve.get_point_position(_path_curve.point_count - 1),
			line_end - line_direction_forward * line_arrow_size.y * _style_offsets[end_style2],
			line_color,
			line_width,
		)


func _draw_arrow(line_start : Vector2, line_end : Vector2, style : int):
	var line_direction := (line_end - line_start).normalized()
	match style:
		1:
			draw_colored_polygon(
				[
					line_end + line_direction,
					line_end - line_direction * line_arrow_size.y + line_arrow_size.x * Vector2(
						line_direction.y,
						-line_direction.x,
					),
					line_end - line_direction * line_arrow_size.y + line_arrow_size.x * Vector2(
						-line_direction.y,
						line_direction.x,
					),
				],
				line_color,
			)
		2:
			draw_circle(
				line_end - line_direction * line_arrow_size.y * 0.5,
				line_arrow_size.y * 0.5,
				line_color,
			)
		3:
			draw_line(
				line_end - line_direction * line_width + line_arrow_size.x * Vector2(
					line_direction.y,
					-line_direction.x,
				),
				line_end - line_direction * line_width + line_arrow_size.x * Vector2(
					-line_direction.y,
					line_direction.x,
				),
				line_color,
				line_width,
			)


func _is_in_radius(circle_center : Vector2, point : Vector2):
	return circle_center.distance_squared_to(point) <= drag_hint_radius * drag_hint_radius


func _get_overlapped_path_point(point_global : Vector2) -> int:
	if get_parent() is CanvasItem:
		point_global = get_parent().get_global_transform().affine_inverse() * point_global

	if _path_curve == null:
		return -1

	for i in _path_curve.point_count:
		if _is_in_radius(_path_curve.get_point_position(i), point_global):
			return i

	return -1


func _get_overlapped_path_midpoint(point_global : Vector2) -> int:
	if get_parent() is CanvasItem:
		point_global = get_parent().get_global_transform().affine_inverse() * point_global

	if _path_curve == null:
		return 0 if _is_in_radius((connect_point1 + connect_point2) * 0.5, point_global) else -1

	var prev_position := connect_point1
	var next_position := Vector2.ZERO
	for i in _path_curve.point_count:
		next_position = _path_curve.get_point_position(i)
		if _is_in_radius((prev_position + next_position) * 0.5, point_global):
			return i

		prev_position = next_position

	next_position = connect_point2
	if _is_in_radius((prev_position + next_position) * 0.5, point_global):
		return _path_curve.point_count

	return -1


func _gui_input(event : InputEvent):
	queue_redraw()
	if event is InputEventMouseMotion:
		if _mouse_dragging >= 0:
			path_set(_mouse_dragging, event.position + position)

	if event is InputEventMouseButton && event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_point : Vector2 = event.position
		if !event.pressed && _mouse_dragging != -1:
			mouse_point += position
			var succeeded_on : Control
			var drag_reattach_condition_expr := Expression.new()
			var expr_params : Array = [
				connect_node1 if _mouse_dragging == -2 else connect_node2,
				connect_node2 if _mouse_dragging == -2 else connect_node1,
				self
			]
			if drag_reattach_condition_expr.parse(drag_reattach_condition, [&"from", &"other", &"line"]) != OK:
				# Couldn't parse expression, so don't call it.
				drag_reattach_condition_expr = null

			if _mouse_dragging == -2:
				for x in connect_node1.get_parent().get_children():
					if x == connect_node2 || !(x is Control) || !x.get_rect().has_point(mouse_point):
						continue

					if drag_reattach_condition_expr != null && !drag_reattach_condition_expr.execute(expr_params, x):
						continue

					connect_node1 = x
					succeeded_on = x
					break

			elif _mouse_dragging == -3:
				for x in connect_node2.get_parent().get_children():
					if x == connect_node1 || !(x is Control) || !x.get_rect().has_point(mouse_point):
						continue

					if drag_reattach_condition_expr != null && !drag_reattach_condition_expr.execute(expr_params, x):
						continue

					connect_node2 = x
					succeeded_on = x
					break

			else:
				# TODO: Grid Snap
				path_set(_mouse_dragging, event.position + position)

			if succeeded_on != null:
				var drag_reattach_call_on_success_expr := Expression.new()
				drag_reattach_call_on_success_expr.parse(drag_reattach_call_on_success, [&"from", &"other", &"line"])
				drag_reattach_call_on_success_expr.execute(expr_params, succeeded_on)

			_mouse_dragging = -1
			return

		_mouse_dragging = -1
		if allow_drag_pt1 && _is_in_radius(connect_point1 - position, mouse_point):
			_mouse_dragging = -2

		elif allow_drag_pt2 && _is_in_radius(connect_point2 - position, mouse_point):
			_mouse_dragging = -3

		else:
			var pt_overlapping := _get_overlapped_path_point(event.global_position)
			if pt_overlapping != -1:
				_mouse_dragging = pt_overlapping
				return

			pt_overlapping = _get_overlapped_path_midpoint(event.global_position)
			if pt_overlapping != -1:
				path_add(pt_overlapping, event.position + position)
				_mouse_dragging = pt_overlapping


func _on_mouse_entered():
	_mouse_over = true
	queue_redraw()


func _on_mouse_exited():
	_mouse_over = false
	queue_redraw()
