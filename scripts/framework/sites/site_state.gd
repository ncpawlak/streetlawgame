class_name SiteState
extends RefCounted
## Runtime state of one site: ownership, stash and heat.

var acquired := false
var heat := 0.0
var stash := Inventory.new()


func to_dict() -> Dictionary:
	return {"acquired": acquired, "heat": heat, "stash": stash.to_dict()}


static func from_dict(data: Dictionary) -> SiteState:
	var state := SiteState.new()
	state.acquired = bool(data.get("acquired", false))
	state.heat = float(data.get("heat", 0.0))
	state.stash = Inventory.from_dict(data.get("stash", {}))
	return state
