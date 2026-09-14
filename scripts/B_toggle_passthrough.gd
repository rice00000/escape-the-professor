class_name XRTogglePassthrough extends Node

@export var passthrough_controller_node: XRPassthrough
@export var button_action_name: StringName = "by_button"

var _controller: XRController3D

func _ready() -> void:
	_controller = get_parent() as XRController3D
	
	# If this script is not actually parented to a controller.
	if _controller == null or passthrough_controller_node == null:
		push_error("XRTogglePassthrough|ERROR: Not parented to controller or no assigned passthrough node.")
		return

	_controller.button_pressed.connect(_on_button_press)


func _on_button_press(action: StringName) -> void:
	if action != button_action_name:
		return
	
	# Toggle passthrough. The XRPassthrough setter will dynamically update it. You can do this in your own scripts!
	passthrough_controller_node.enabled = not passthrough_controller_node.enabled
	
