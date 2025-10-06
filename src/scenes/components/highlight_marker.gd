class_name HighLightMarker
extends Area2D

var size : Vector2 = Vector2(16, 16)
var color : Color = Color(1.0, 1.0, 0.0, 0.5)

@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D

signal is_placeable(value: bool)

var overlapping_areas: Array[Area2D] = []

func _ready() -> void:
	self.visible = false

func _draw():
	collision_shape_2d.shape.size = size
	draw_rect(Rect2(-size / 2.0, size), color)


func update_marker(new_size: Vector2, new_visible: bool):
	self.size = new_size
	self.visible = new_visible
	queue_redraw()

func _on_area_entered(area: Area2D) -> void:
	overlapping_areas.append(area)
	color = Color(1.0, 0.0, 0.0, 0.502)
	queue_redraw()
	is_placeable.emit(false)
	#print("Building detected")

func _on_area_exited(area: Area2D) -> void:
	overlapping_areas.erase(area)
	if overlapping_areas.is_empty():
		color = Color(1.0, 1.0, 0.0, 0.5)
		queue_redraw()
		is_placeable.emit(true)
