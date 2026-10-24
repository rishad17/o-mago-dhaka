## Lane graph for traffic, generated from CityLayout.
##
## Every road segment between two intersections has one lane per direction.
## Bangladesh drives on the LEFT, so each lane runs along the left half of
## the road (seen in the direction of travel). Inside intersections vehicles
## follow curved "turn" pieces from one lane to the next. Vehicles only ever
## move along these pieces, so they cannot wander into buildings.
extends RefCounted

const CityLayout := preload("res://scripts/city_layout.gd")


## A drivable polyline: a lane between intersections, or a turn through one.
class Piece:
	var points := PackedVector3Array()
	var cum := PackedFloat32Array()  # distance along the piece at each point
	var length := 0.0
	var edge := -1                   # lane id, or -1 for a turn
	var road_width := 7.0            # width of the road this piece is on

	func _init(pts: PackedVector3Array, edge_id := -1, width := 7.0) -> void:
		points = pts
		edge = edge_id
		road_width = width
		cum.resize(pts.size())
		cum[0] = 0.0
		for i in range(1, pts.size()):
			cum[i] = cum[i - 1] + pts[i].distance_to(pts[i - 1])
		length = cum[cum.size() - 1]

	func is_turn() -> bool:
		return edge < 0

	## Position at distance s along the piece.
	func position_at(s: float) -> Vector3:
		s = clampf(s, 0.0, length)
		for i in range(1, points.size()):
			if s <= cum[i] or i == points.size() - 1:
				var seg := cum[i] - cum[i - 1]
				var f := 0.0 if seg <= 0.0001 else (s - cum[i - 1]) / seg
				return points[i - 1].lerp(points[i], clampf(f, 0.0, 1.0))
		return points[points.size() - 1]

	## Unit direction of travel at distance s.
	func tangent_at(s: float) -> Vector3:
		s = clampf(s, 0.0, length)
		for i in range(1, points.size()):
			if s <= cum[i] or i == points.size() - 1:
				return (points[i] - points[i - 1]).normalized()
		return Vector3.FORWARD


## Each lane: {from, to, start, end, dir, road_width, piece}
var edges: Array[Dictionary] = []
## For each intersection node: ids of lanes leaving it.
var node_out: Array = []
var node_pos: Array[Vector2] = []
var _turns := {}


func _init() -> void:
	_build()


func _build() -> void:
	# One node per real intersection (not every road crosses every other one:
	# only three roads cross the canal into Mohammadpur).
	var its: Array = CityLayout.intersections()
	for it in its:
		node_pos.append(it[0])
		node_out.append([])
	# North-south roads: link neighbouring intersections along each road.
	for v in CityLayout.VERTICAL_ROADS:
		var on: Array = []
		for i in its.size():
			if its[i][1] == v:
				on.append(i)
		on.sort_custom(func(a, b): return its[a][0].y < its[b][0].y)
		var x: float = v[0]
		var w: float = v[1]
		for k in on.size() - 1:
			var north: int = on[k]
			var south: int = on[k + 1]
			var z_n: float = its[north][0].y + its[north][2][1] * 0.5
			var z_s: float = its[south][0].y - its[south][2][1] * 0.5
			_add_edge(north, south, Vector3(x + w * 0.25, 0, z_n), Vector3(x + w * 0.25, 0, z_s), w)
			_add_edge(south, north, Vector3(x - w * 0.25, 0, z_s), Vector3(x - w * 0.25, 0, z_n), w)
	# East-west roads.
	for h in CityLayout.HORIZONTAL_ROADS:
		var on: Array = []
		for i in its.size():
			if its[i][2] == h:
				on.append(i)
		on.sort_custom(func(a, b): return its[a][0].x < its[b][0].x)
		var z: float = h[0]
		var w: float = h[1]
		for k in on.size() - 1:
			var west: int = on[k]
			var east: int = on[k + 1]
			var x_w: float = its[west][0].x + its[west][1][1] * 0.5
			var x_e: float = its[east][0].x - its[east][1][1] * 0.5
			_add_edge(west, east, Vector3(x_w, 0, z - w * 0.25), Vector3(x_e, 0, z - w * 0.25), w)
			_add_edge(east, west, Vector3(x_e, 0, z + w * 0.25), Vector3(x_w, 0, z + w * 0.25), w)


func _add_edge(from: int, to: int, start: Vector3, end: Vector3, width: float) -> void:
	var id := edges.size()
	var pts := PackedVector3Array([start, end])
	edges.append({
		"from": from, "to": to, "start": start, "end": end,
		"dir": (end - start).normalized(), "road_width": width,
		"piece": Piece.new(pts, id, width),
	})
	node_out[from].append(id)


func edge_piece(id: int) -> Piece:
	return edges[id].piece


## Picks the lane to take after `edge_id` (never a U-turn).
## Going straight is the most likely choice.
func next_edge(edge_id: int, rng: RandomNumberGenerator) -> int:
	var e: Dictionary = edges[edge_id]
	var options: Array[int] = []
	var weights: Array[float] = []
	for out in node_out[e.to]:
		var o: Dictionary = edges[out]
		if o.to == e.from:
			continue
		options.append(out)
		weights.append(2.0 if (o.dir as Vector3).dot(e.dir) > 0.9 else 1.0)
	if options.is_empty():
		# Dead end (not expected in this map): turn back.
		return node_out[e.to][0]
	var total := 0.0
	for wgt in weights:
		total += wgt
	var r := rng.randf() * total
	for k in options.size():
		r -= weights[k]
		if r <= 0.0:
			return options[k]
	return options[options.size() - 1]


## The path through the intersection from lane a into lane b.
func turn_piece(a: int, b: int) -> Piece:
	var key := a * 10000 + b
	if _turns.has(key):
		return _turns[key]
	var ea: Dictionary = edges[a]
	var eb: Dictionary = edges[b]
	var p0: Vector3 = ea.end
	var p2: Vector3 = eb.start
	var da: Vector3 = ea.dir
	var db: Vector3 = eb.dir
	var pts := PackedVector3Array()
	if da.dot(db) > 0.9:
		pts.append(p0)
		pts.append(p2)
	else:
		# Corner where the two lane lines meet = Bezier control point.
		var c := Vector3(p0.x, 0, p2.z) if absf(da.z) > 0.5 else Vector3(p2.x, 0, p0.z)
		var n := 8
		for i in n + 1:
			var t := float(i) / n
			pts.append(p0 * (1 - t) * (1 - t) + c * 2.0 * (1 - t) * t + p2 * t * t)
	var piece := Piece.new(pts, -1, minf(ea.road_width, eb.road_width))
	_turns[key] = piece
	return piece


## A random lane and distance along it, for spawning.
func random_spot(rng: RandomNumberGenerator, margin := 4.0) -> Array:
	for attempt in 50:
		var id := rng.randi() % edges.size()
		var piece: Piece = edges[id].piece
		if piece.length > margin * 2.0 + 1.0:
			return [id, rng.randf_range(margin, piece.length - margin)]
	return [0, 1.0]
