extends Node
## Registers default input actions in code so bindings stay readable and reviewable in git.

const KEY_BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"handbrake": [KEY_SPACE],
	"interact": [KEY_E, KEY_F],
	"toggle_map": [KEY_TAB, KEY_M],
	"reload": [KEY_R],
	"weapon_wheel": [KEY_Q],
	"weapon_1": [KEY_1],
	"weapon_2": [KEY_2],
	"weapon_3": [KEY_3],
	"weapon_4": [KEY_4],
	"weapon_5": [KEY_5],
}

const MOUSE_BINDINGS := {
	"shoot": [MOUSE_BUTTON_LEFT],
	"aim": [MOUSE_BUTTON_RIGHT],
	"next_weapon": [MOUSE_BUTTON_WHEEL_DOWN],
	"prev_weapon": [MOUSE_BUTTON_WHEEL_UP],
}

## Number of direct weapon-slot hotkeys (weapon_1..weapon_N).
const WEAPON_HOTKEYS := 5


func _enter_tree() -> void:
	for action: String in KEY_BINDINGS:
		_ensure_action(action)
		for keycode: Key in KEY_BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)
	for action: String in MOUSE_BINDINGS:
		_ensure_action(action)
		for button: MouseButton in MOUSE_BINDINGS[action]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
