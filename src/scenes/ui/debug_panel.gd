extends PanelContainer

@onready var fps_label: Label = $FpsLabel

func _process(_delta: float) -> void:
	var frame_rate: float = Engine.get_frames_per_second()
	fps_label.text = "FPS: " + str(frame_rate)
