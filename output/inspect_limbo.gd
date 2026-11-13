extends SceneTree

func _initialize() -> void:
	var branch := BTDynamicSequence.new()
	branch.add_child(BTAction.new())
	var selector := BTDynamicSelector.new()
	selector.add_child(branch)
	var tree := BehaviorTree.new()
	tree.set_root_task(selector)
	print("SAVE_RESULT=", ResourceSaver.save(tree, "res://output/limbo_example.tres"))
	for property in ProjectSettings.get_property_list():
		if "limbo" in str(property.name).to_lower():
			print(property.name, "=", ProjectSettings.get_setting(property.name))
	quit()
