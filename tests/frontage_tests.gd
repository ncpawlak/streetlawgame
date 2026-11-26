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
## Longest run of street frontage (m) with no building, along any North End street side, unless
## the land behind it is a cross street, water, rail, I-59 (or a freeway buffer where map rule 8
## forbids a lot), a reserved yard or a tagged open space ([method CityGenerator.vacant_areas]).
## About one kit house lot.
const MAX_GAP_M := 18.0
## How deep behind the sidewalk a building still counts as fronting the street (m).
const GAP_DEPTH_M := 26.0
const GAP_STEP_M := 1.0
## A corner lot's side yard along its side street (the street it does not face) is part of a
## built lot, not an empty frontage; up to this much of it (m, about one house lot depth) is
## excused from a gap. Front yards of a house along the street it faces are never excused; a
## shop's or landmark's forecourt / parking is excused on every side.
const MAX_SIDE_YARD_M := 30.0

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
	var gaps := frontage_gaps(city)
	var worst_gap := 0.0
	for gap: Dictionary in gaps:
		worst_gap = maxf(worst_gap, gap["length"])
	var long := gaps.filter(func(g: Dictionary) -> bool: return g["length"] > MAX_GAP_M).map(func(g: Dictionary) -> String: return "%s %.0fm at px %s" % [g["district"], g["length"], g["mid_px"].round()])
	_runner._check(long.is_empty(), "frontage: no unexplained street frontage gap over %.0f m (longest %.0f m; %s)" % [MAX_GAP_M, worst_gap, long])


## Runs of street frontage with no building behind the sidewalk: [{district, length (m), mid_px,
## from_px, to_px}]. Walks both sides of every drivable street in the three North End districts.
static func frontage_gaps(city: CityGenerator) -> Array[Dictionary]:
	var bodies: Array[Rect2] = []
	var yards: Array = []
	for lot: Dictionary in city.building_lots:
		bodies.append((lot.get("body_px", lot["rect_px"]) as Rect2).grow(1.0 / CityGenerator.METERS_PER_PX))
		if lot.has("door"):
			var out3: Vector3 = (lot["door"] as Transform3D).basis.z
			var scene := String(lot.get("kit_scene", ""))
			var house := HOUSE_PREFIXES.any(func(p: String) -> bool: return scene.begins_with(p))
			# Shops, landmarks and yards keep forecourt parking and grounds on any side.
			yards.append([lot["rect_px"], Vector2(out3.x, out3.z).normalized() if house else Vector2.ZERO])
	var excused: Array[Rect2] = city._reserved_rects()
	var vacant: Array[PackedVector2Array] = []
	for area: Dictionary in CityGenerator.vacant_areas():
		vacant.append(area["poly"])
	var corridors: Array = []
	for road: Dictionary in NorthEndLayout.ROADS:
		var pts := PackedVector2Array(road["pts"])
		var half: float = (CityGenerator.ROAD_WIDTHS[road["kind"]] * 0.5 if road["kind"] != &"rail" else 4.0) / CityGenerator.METERS_PER_PX
		for i in pts.size() - 1:
			corridors.append([pts[i], pts[i + 1], half, Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(half + 30.0)])
	var gaps: Array[Dictionary] = []
	var step := GAP_STEP_M / CityGenerator.METERS_PER_PX
	var sidewalk := CityGenerator.SIDEWALK_M / CityGenerator.METERS_PER_PX
	var depth := GAP_DEPTH_M / CityGenerator.METERS_PER_PX
	for road: Dictionary in NorthEndLayout.ROADS:
		if not CityGenerator.DRIVABLE.has(road["kind"]):
			continue
		var pts := PackedVector2Array(road["pts"])
		var half: float = CityGenerator.ROAD_WIDTHS[road["kind"]] * 0.5 / CityGenerator.METERS_PER_PX
		for side: float in [-1.0, 1.0]:
			var run: Array[Vector2] = []
			var yard_m := 0.0
			var district := &""
			for i in pts.size() - 1:
				var a := pts[i]
				var b := pts[i + 1]
				var length := a.distance_to(b)
				if length < 0.01:
					continue
				var dir := (b - a) / length
				var normal := Vector2(-dir.y, dir.x) * side
				var s := 0.0
				while s <= length:
					var kerb := a + dir * s + normal * half
					var here := CityGenerator.district_for_px(kerb + normal * (sidewalk + 1.0))
					var state := _probe(kerb + normal * sidewalk, normal, depth, bodies, excused, corridors, here, yards, vacant)
					if state == 0 or state == 3:
						if run.is_empty():
							district = here
						elif state == 3:
							yard_m += run[-1].distance_to(kerb) * CityGenerator.METERS_PER_PX
						run.append(kerb)
					elif not run.is_empty():
						gaps.append(_gap(run, district, yard_m))
						run.clear()
						yard_m = 0.0
					s += step
			if not run.is_empty():
				gaps.append(_gap(run, district, yard_m))
	return gaps


## 1 = a building fronts here, 2 = excused, 3 = a built lot's side yard, 0 = gap.
static func _probe(from: Vector2, normal: Vector2, depth: float, bodies: Array[Rect2], excused: Array[Rect2], corridors: Array, district: StringName, yards: Array = [], vacant: Array[PackedVector2Array] = []) -> int:
	if district == &"":
		return 2
	# The smallest lot here would break map rule 8 (I-59 / a ramp nearer than the street): a freeway buffer.
	var side := normal.orthogonal() * CityGenerator.MIN_LOT_PX.x * 0.5
	var smallest := Rect2(from + side, Vector2.ZERO).expand(from - side).expand(from + side + normal * CityGenerator.MIN_LOT_PX.y).expand(from - side + normal * CityGenerator.MIN_LOT_PX.y)
	if not CityGenerator.fronts_street_px(smallest):
		return 2
	var yard := false
	var steps := 13
	for k in steps + 1:
		var p := from + normal * depth * k / steps
		if CityGenerator.district_for_px(p) == &"" or CityGenerator._in_water(p, 1.0):
			return 2
		for body in bodies:
			if body.has_point(p):
				return 1
		for rect in excused:
			if rect.has_point(p):
				return 2
		for poly in vacant:
			if Geometry2D.is_point_in_polygon(p, poly):
				return 2
		for seg: Array in corridors:
			if (seg[3] as Rect2).has_point(p) and p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])) <= float(seg[2]):
				return 2
		for entry: Array in yards:
			if not yard and (entry[0] as Rect2).has_point(p):
				if (entry[1] as Vector2) == Vector2.ZERO:
					return 2
				if (entry[1] as Vector2).dot(normal) > -0.7:
					yard = true
	return 3 if yard else 0


## A gap run; up to [constant MAX_SIDE_YARD_M] of its [param yard_m] side yard does not count.
static func _gap(run: Array[Vector2], district: StringName, yard_m := 0.0) -> Dictionary:
	var length := 0.0
	for i in run.size() - 1:
		length += run[i].distance_to(run[i + 1])
	length = maxf(0.0, length * CityGenerator.METERS_PER_PX - minf(yard_m, MAX_SIDE_YARD_M))
	return {"district": district, "length": length, "mid_px": run[run.size() / 2], "from_px": run[0], "to_px": run[-1]}


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
