class_name CameraStep
extends CutsceneStep
## Moves the cutscene camera. Markers are any Node3D (Marker3D recommended) whose transform is the
## shot; with [member look_at] the camera keeps aiming at that actor's head (or node) instead.

enum Mode {
	## Jump straight to [member marker].
	CUT,
	## Ease from wherever the camera is to [member marker] over [member duration].
	BLEND,
	## Linear track from [member from_marker] (or the current camera) to [member marker].
	DOLLY,
	## Circle around [member look_at] (or [member marker]) at [member orbit_radius].
	ORBIT,
}

@export var mode := Mode.CUT
@export var marker: StringName
@export var from_marker: StringName
## Actor / node to keep the camera aimed at (persists for later shots until another CameraStep).
@export var look_at: StringName
## Added to the look target (heads by default for characters).
@export var look_offset := Vector3.ZERO
@export var duration := 1.0
## 0 keeps the current field of view.
@export var fov := 0.0
@export_group("Orbit")
@export var orbit_radius := 3.0
@export var orbit_height := 1.6
@export var orbit_from_degrees := 0.0
@export var orbit_to_degrees := 90.0


func begin(director: CutsceneDirector, state: Dictionary) -> void:
	var camera := director.take_camera()
	director.look_node = director.resolve_3d(look_at)
	director.look_offset = look_offset
	state["t"] = 0.0
	state["fov0"] = camera.fov
	var from := director.resolve_3d(from_marker) if mode == Mode.DOLLY else null
	state["from"] = from.global_transform if from != null else camera.global_transform
	if mode == Mode.CUT:
		_apply(director, 1.0, state)


func tick(director: CutsceneDirector, state: Dictionary, delta: float) -> bool:
	if mode == Mode.CUT:
		return true
	state["t"] += delta
	var k := clampf(state["t"] / maxf(duration, 0.001), 0.0, 1.0)
	_apply(director, k, state)
	return k >= 1.0


func skip(director: CutsceneDirector, state: Dictionary) -> void:
	if state.is_empty():
		begin(director, state)
	_apply(director, 1.0, state)


func validate() -> PackedStringArray:
	var issues := PackedStringArray()
	if mode == Mode.ORBIT and marker == &"" and look_at == &"":
		issues.append("orbit needs look_at or marker")
	elif mode != Mode.ORBIT and marker == &"" and look_at == &"":
		issues.append("needs marker or look_at")
	return issues


func _apply(director: CutsceneDirector, k: float, state: Dictionary) -> void:
	var camera := director.camera
	if fov > 0.0:
		camera.fov = lerpf(state["fov0"], fov, k)
	if mode == Mode.ORBIT:
		var center_node: Node3D = director.look_node if director.look_node != null else director.resolve_3d(marker)
		if center_node == null:
			return
		var angle := deg_to_rad(lerpf(orbit_from_degrees, orbit_to_degrees, k))
		var center := center_node.global_position
		camera.global_position = center + Vector3(sin(angle) * orbit_radius, orbit_height, cos(angle) * orbit_radius)
		var focus := Narrative.focus_point(center_node) + look_offset
		if camera.global_position.distance_to(focus) > 0.01:
			camera.look_at(focus, Vector3.UP)
		return
	var target_node := director.resolve_3d(marker)
	if target_node == null:
		return
	var to := target_node.global_transform.orthonormalized()
	var from: Transform3D = state["from"]
	var eased := k if mode == Mode.DOLLY else ease(k, -1.8)
	camera.global_transform = to if k >= 1.0 else from.interpolate_with(to, eased)
