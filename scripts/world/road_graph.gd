class_name RoadGraph
extends RefCounted
## Drivable street graph built from [constant NorthEndLayout.ROADS] for map GPS routes. Roads are
## split into nodes every [constant SPACING_PX] and linked where they meet: T-junctions (an end
## within the other road's half-width) and crossings. Junction rules match the generator: ramps only
## join I-59 and arterials, I-59 only joins ramps, and rail is ignored. Positions are wireframe px.

const SPACING_PX := 20.0
const HALF_WIDTH_PX := {&"loc": 3.75, &"ave": 5.0, &"art": 6.67, &"highway": 10.83, &"ramp": 3.33}

static var _shared: RoadGraph

var astar := AStar2D.new()

## Per road: Array of Vector2(arc length, point id), the cut points along it.
var _cuts: Array = []
## Per road: cumulative arc length at each polyline vertex.
var _arc: Array = []


## The North End graph, built once.
static func shared() -> RoadGraph:
	if _shared == null:
		_shared = RoadGraph.new()
		_shared.build(NorthEndLayout.ROADS)
	return _shared


static func may_join(a: StringName, b: StringName) -> bool:
	if a == &"ramp" or b == &"ramp":
		return (a == &"highway" or b == &"highway" or a == &"art" or b == &"art") and a != b
	return a != &"highway" and b != &"highway"


func build(all_roads: Array) -> void:
	astar.clear()
	_cuts.clear()
	_arc.clear()
	var roads := all_roads.filter(func(road: Dictionary) -> bool: return road["kind"] != &"rail")
	for road: Dictionary in roads:
		var pts: Array = road["pts"]
		var arc := PackedFloat32Array([0.0])
		for k in range(1, pts.size()):
			arc.append(arc[k - 1] + (pts[k] as Vector2).distance_to(pts[k - 1]))
		_arc.append(arc)
		_cuts.append([])
	for r in roads.size():
		var pts: Array = roads[r]["pts"]
		var arc: PackedFloat32Array = _arc[r]
		for k in pts.size() - 1:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			var steps := maxi(1, ceili(a.distance_to(b) / SPACING_PX))
			for step in steps:
				var t := float(step) / steps
				_add_cut(r, arc[k] + a.distance_to(b) * t, a.lerp(b, t))
		_add_cut(r, arc[arc.size() - 1], pts[pts.size() - 1])
	for i in roads.size():
		var pi: Array = roads[i]["pts"]
		for j in roads.size():
			if i == j or not may_join(roads[i]["kind"], roads[j]["kind"]):
				continue
			var reach: float = HALF_WIDTH_PX.get(roads[j]["kind"], 5.0) + 1.0
			for end_index in [0, pi.size() - 1]:
				var end: Vector2 = pi[end_index]
				var hit := _closest_on(j, roads[j]["pts"], end)
				if hit.x <= reach:
					var on_i := _add_cut(i, (_arc[i] as PackedFloat32Array)[end_index], end)
					var on_j := _add_cut(j, hit.y, Vector2(hit.z, hit.w))
					astar.connect_points(on_i, on_j)
			if j <= i:
				continue
			var pj: Array = roads[j]["pts"]
			for a in pi.size() - 1:
				for b in pj.size() - 1:
					var crossing: Variant = Geometry2D.segment_intersects_segment(pi[a], pi[a + 1], pj[b], pj[b + 1])
					if crossing == null:
						continue
					var at: Vector2 = crossing
					var on_i := _add_cut(i, (_arc[i] as PackedFloat32Array)[a] + at.distance_to(pi[a]), at)
					var on_j := _add_cut(j, (_arc[j] as PackedFloat32Array)[b] + at.distance_to(pj[b]), at)
					astar.connect_points(on_i, on_j)
	for cuts: Array in _cuts:
		cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		for k in cuts.size() - 1:
			var from := int((cuts[k] as Vector2).y)
			var to := int((cuts[k + 1] as Vector2).y)
			if from != to:
				astar.connect_points(from, to)


## Shortest street route between two world positions, as world points (start and end included).
## Empty when the graph has no nodes.
func route(from_world: Vector3, to_world: Vector3) -> PackedVector3Array:
	var result := PackedVector3Array()
	var start := astar.get_closest_point(CityGenerator.world_to_px(from_world))
	var goal := astar.get_closest_point(CityGenerator.world_to_px(to_world))
	if start < 0 or goal < 0:
		return result
	result.append(Vector3(from_world.x, 0.0, from_world.z))
	for px: Vector2 in astar.get_point_path(start, goal):
		result.append(CityGenerator.px_to_world(px))
	result.append(Vector3(to_world.x, 0.0, to_world.z))
	return result


func _add_cut(road: int, arc_length: float, at: Vector2) -> int:
	var id := astar.get_available_point_id()
	astar.add_point(id, at)
	(_cuts[road] as Array).append(Vector2(arc_length, id))
	return id


## Vector4(distance, arc length, closest x, closest y) from [param p] to road [param road].
func _closest_on(road: int, pts: Array, p: Vector2) -> Vector4:
	var best := Vector4(INF, 0.0, 0.0, 0.0)
	var arc: PackedFloat32Array = _arc[road]
	for k in pts.size() - 1:
		var closest := Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1])
		var distance := p.distance_to(closest)
		if distance < best.x:
			best = Vector4(distance, arc[k] + closest.distance_to(pts[k]), closest.x, closest.y)
	return best
