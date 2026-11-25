extends Node
## Focused runner for the carjack driver tests only.
## Run: godot --headless --path . res://tests/carjack_test_runner.tscn

var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await CarjackTests.new(self).run()
	print("\n%s (%d failure(s))" % ["FAILED" if _failures > 0 else "ALL TESTS PASSED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)
		print("FAIL: ", description)