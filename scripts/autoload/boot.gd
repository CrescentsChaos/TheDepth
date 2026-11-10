extends Node
## Registers input actions in code and applies saved settings.


func _ready() -> void:
	_setup_inputs()
	apply_settings()
	# Every button that appears (menus, pause, game over) gets the same hover behaviour.
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		var b := n as BaseButton
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.mouse_entered.connect(_on_button_hover.bind(b))
		b.mouse_exited.connect(_on_button_unhover.bind(b))


## Hover == focus, so only the button under the cursor is ever highlighted. Before this a
## clicked button kept its focus outline while you hovered another one, which looked like
## the highlight was in the wrong place.
func _on_button_hover(b: BaseButton) -> void:
	if is_instance_valid(b) and b.is_inside_tree() and not b.disabled and b.focus_mode != Control.FOCUS_NONE:
		b.grab_focus()


func _on_button_unhover(b: BaseButton) -> void:
	if is_instance_valid(b) and b.has_focus():
		b.release_focus()


func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(Save.setting("master_volume")), 0.0001)))
	if bool(Save.setting("fullscreen")):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)


func _keys(action: String, keys: Array) -> void:
	_ensure(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _mouse(action: String, button: int) -> void:
	_ensure(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _joy_button(action: String, button: int) -> void:
	_ensure(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _joy_axis(action: String, axis: int, value: float) -> void:
	_ensure(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


func _setup_inputs() -> void:
	_keys("move_left", [KEY_A, KEY_LEFT])
	_keys("move_right", [KEY_D, KEY_RIGHT])
	_keys("move_up", [KEY_W, KEY_UP])
	_keys("move_down", [KEY_S, KEY_DOWN])
	_keys("bite", [KEY_SPACE])
	_keys("boost", [KEY_SHIFT])
	_keys("pause", [KEY_ESCAPE, KEY_P])
	_mouse("bite", MOUSE_BUTTON_LEFT)
	_mouse("boost", MOUSE_BUTTON_RIGHT)
	_joy_button("bite", JOY_BUTTON_A)
	_joy_button("boost", JOY_BUTTON_RIGHT_SHOULDER)
	_joy_button("pause", JOY_BUTTON_START)
	_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_joy_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_joy_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
