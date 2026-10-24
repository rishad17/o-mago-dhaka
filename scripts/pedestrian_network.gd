## Sidewalk graph for pedestrians, generated from CityLayout.
##
## Every road-facing block edge gets a walking line 1.5 m in from the kerb
## (clear of poles, trees, stalls and shop fronts). Lines meet at block
## corners, and at every intersection the corners are joined across the road
## by crossings. Pedestrians walk along these edges, so they never walk
## through buildings.
extends RefCounted

const CityLayout := preload("res://scripts/city_layout.gd")

const WALK_INSET := 1.5
const SIDEWALK_Y := 0.15

## Each edge: {a, b, pa, pb, length, cross (bool), inward (towards buildings; walk edges)}
var edges: Array[Dictionary] = []
var node_pos: Array[Vector3] = []
var node_edges: Array = []
var _node_index := {}


func _init() -> void:
	_build()


func _node(p: Vector3) -> int:
	var key := Vector2i(roundi(p.x * 10.0), roundi(p.z * 10.0))
	if _node_index.has(key):
		return _node_index[key]
	var id := node_pos.size()
	node_pos.append(p)
	node_edges.append([])
	_node_index[key] = id
	return id


func _has_node(x: float, z: float) -> bool:
	return _node_index.has(Vector2i(roundi(x * 10.0), roundi(z * 10.0)))


func _add_edge(pa: Vector3, pb: Vector3, inward: Vector3) -> void:
	var a := _node(pa)
	var b := _node(pb)
	if a == b:
		return
	var mid := (pa + pb) * 0.5
	var id := edges.size()
	edges.append({"a": a, "b": b, "pa": pa, "pb": pb, "length": pa.distance_to(pb),
		"cross": CityLayout.is_road(mid.x, mid.z), "inward": inward})
	node_edges[a].append(id)
	node_edges[b].append(id)


func _build() -> void:
	var y := SIDEWALK_Y
	var s := WALK_INSET
	for r in CityLayout.block_rects():
		if CityLayout.district_for(r.get_center()) == "lake":
			continue
		var x0 := r.position.x + s
		var x1 := r.end.x - s
		var z0 := r.position.y + s
		var z1 := r.end.y - s
		if x1 - x0 < 1.0 or z1 - z0 < 1.0:
			continue
		var c := r.get_center()
		if CityLayout.is_road(c.x, r.position.y - 1.0):
			_add_edge(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3.BACK)
		if CityLayout.is_road(c.x, r.end.y + 1.0):
			_add_edge(Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3.FORWARD)
		if CityLayout.is_road(r.position.x - 1.0, c.y):
			_add_edge(Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3.RIGHT)
		if CityLayout.is_road(r.end.x + 1.0, c.y):
			_add_edge(Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3.LEFT)
	# Crossings at intersections, from corner to corner.
	for it in CityLayout.intersections():
		var cen: Vector2 = it[0]
		var hx: float = it[1][1] * 0.5 + s
		var hz: float = it[2][1] * 0.5 + s
		var nw := Vector3(cen.x - hx, y, cen.y - hz)
		var ne := Vector3(cen.x + hx, y, cen.y - hz)
		var sw := Vector3(cen.x - hx, y, cen.y + hz)
		var se := Vector3(cen.x + hx, y, cen.y + hz)
		for pair in [[nw, ne], [sw, se], [nw, sw], [ne, se]]:
			var pa: Vector3 = pair[0]
			var pb: Vector3 = pair[1]
			if _has_node(pa.x, pa.z) and _has_node(pb.x, pb.z):
				_add_edge(pa, pb, Vector3.ZERO)


## Ground height at a point: sidewalk slab or road.
static func ground_y(x: float, z: float) -> float:
	return 0.0 if CityLayout.is_road(x, z) else SIDEWALK_Y


func point_on(edge_id: int, t: float) -> Vector3:
	var e: Dictionary = edges[edge_id]
	return (e.pa as Vector3).lerp(e.pb, clampf(t / maxf(e.length, 0.001), 0.0, 1.0))


## Nearest point on a walking (non-crossing) edge: [edge_id, t, distance].
func nearest_walk_point(p: Vector3) -> Array:
	var best := [-1, 0.0, 1e9]
	for id in edges.size():
		var e: Dictionary = edges[id]
		if e.cross:
			continue
		var ab: Vector3 = e.pb - e.pa
		var f := clampf((p - e.pa).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var q: Vector3 = (e.pa as Vector3) + ab * f
		var d := Vector2(p.x - q.x, p.z - q.z).length()
		if d < best[2]:
			best = [id, f * e.length, d]
	return best


## For a mid-block crossing: walks straight across the road from `p`
## (on a walking line, `inward` pointing to the buildings) and returns the
## matching point on the opposite sidewalk as [edge_id, t], or [] if none.
func opposite_point(p: Vector3, inward: Vector3) -> Array:
	var dir := -inward
	var d := 0.5
	var left_sidewalk := false
	while d < 25.0:
		var q := p + dir * d
		var road := CityLayout.is_road(q.x, q.z)
		if road:
			left_sidewalk = true
		elif left_sidewalk:
			var target := q + dir * (WALK_INSET - 0.2)
			var hit := nearest_walk_point(target)
			if hit[0] >= 0 and hit[2] < 0.6:
				return [hit[0], hit[1]]
			return []
		d += 0.5
	return []
