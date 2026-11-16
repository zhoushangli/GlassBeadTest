extends SceneTree

func _initialize() -> void:
	var data := AnimalData.new()
	data.append_slot()
	var positions := data.motion_position
	positions[0] = Vector2(2, 3)
	print("LOCAL_PACKED_WRITE ", data.motion_position[0])
	quit()
