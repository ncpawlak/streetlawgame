extends RefCounted
## North End street frontage: every populated building faces a drivable street and its front edge
## (the front of the kit body) sits within a setback tolerance of that street's kerb. Kerbs are
## measured independently of the populator, from NorthEndLayout.ROADS and the drawn road widths.

## Kerb to front edge (m): sidewalk (2.5) + the deepest house front yard in the kit (2F-05, 12 m),
## plus the 0.5 m probe step.
const HOUSE_SETBACK_M := 16.0
## Commercial lots may keep a parking / pump forecourt (gas station canopy ~22 m).
const COMMERCIAL_SETBACK_M := 26.0
## The faced street must be the nearest one (within this slack, m).
const FACING_SLACK_M := 3.0
const HOUSE_PREFIXES := ["1F-", "2F-", "T-"]

var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


func run(city: CityGenerator) -> void:
	var far: Array[String] = []
	var away: Array[String] = []
	var worst_house := 0.0
	var worst := 0.0
	var checked := 0
	for lot: Dictionary in city.building_lots:
		if not lot.has("front_edge"):
			continue
		checked += 1
		var edge: Vector3 = lot["front_edge"]
		var out3: Vector3 = (lot["door"] as Transform3D).basis.z
		var px := CityGenerator.world_to_px(edge)
		var out := Vector2(out3.x, out3.z).normalized()
		var segments := _segments_near(px, 40.0 / CityGenerator.METERS_PER_PX)
		var nearest := INF
		for seg: Array in segments:
			nearest = minf(nearest, _kerb_distance(px, seg))
		var ahead := INF
		var t := 0.0
		while t <= COMMERCIAL_SETBACK_M + 1.0:
			var probe := px + out * (t / CityGenerator.METERS_PER_PX)
			if segments.any(func(seg: Array) -> bool: return _kerb_distance(probe, seg) <= 0.0):
				ahead = t
				break
			t += 0.5
		var scene := String(lot.get("kit_scene", ""))
		var house := HOUSE_PREFIXES.any(func(p: String) -> bool: return scene.begins_with(p))
		var limit := HOUSE_SETBACK_M if house else COMMERCIAL_SETBACK_M
		var label := "%s %s" % [scene, NorthEndCensus.rect_key(lot["rect_px"])]
		if ahead > limit:
			far.append("%s %.1fm" % [label, ahead])
		elif house:
			worst_house = maxf(worst_house, ahead)
		if ahead < INF:
			worst = maxf(worst, ahead)
		if ahead > nearest + FACING_SLACK_M:
			away.append("%s faces %.1fm, nearest %.1fm" % [label, ahead, nearest])
	_runner._check(checked > 300, "frontage: %d populated lots checked" % checked)
	_runner._check(far.is_empty(), "frontage: every building front is within %.0f m (houses) / %.0f m (commercial) of its street kerb; worst house %.1f m, worst %.1f m (%s)" % [HOUSE_SETBACK_M, COMMERCIAL_SETBACK_M, worst_house, worst, far])
	_runner._check(away.is_empty(), "frontage: every building faces its nearest street (%s)" % [away])


## Drivable road segments [a, b, half_width_px] with any part within [param radius_px] of [param px].
static func _segments_near(px: Vector2, radius_px: float) -> Array:
	var out: Array = []
	for road: Dictionary in NorthEndLayout.ROADS:
		if not CityGenerator.DRIVABLE.has(road["kind"]):
			continue
		var pts := PackedVector2Array(road["pts"])
		var half: float = CityGenerator.ROAD_WIDTHS[road["kind"]] * 0.5 / CityGenerator.METERS_PER_PX
		for i in pts.size() - 1:
			if px.distance_to(Geometry2D.get_closest_point_to_segment(px, pts[i], pts[i + 1])) <= radius_px + half:
				out.append([pts[i], pts[i + 1], half])
	return out


## Distance (m) from [param px] to the kerb of a segment; <= 0 on the carriageway.
static func _kerb_distance(px: Vector2, seg: Array) -> float:
	var closest := Geometry2D.get_closest_point_to_segment(px, seg[0], seg[1])
	return (px.distance_to(closest) - float(seg[2])) * CityGenerator.METERS_PER_PX
