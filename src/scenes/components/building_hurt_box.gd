extends Area2D

# Listener: parent building on ready
signal area_clicked


func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event.is_action_pressed("left_mouse"):
		#print("area clicked")
		area_clicked.emit()
