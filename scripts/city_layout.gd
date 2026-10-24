## Map data for the fictional Dhaka neighbourhood: roads, districts,
## landmarks and passenger destinations.
##
## Shared by the city builder, the destination manager, the HUD and the
## tests, so everything agrees on where things are. Coordinates are metres on
## the ground plane: Vector2(x, z), with -Z being north.
extends RefCounted

## The whole playable map (x from west to east, z from north to south).
const MAP := Rect2(-340.0, -333.0, 720.0, 666.0)
## Kept for code that only needs a rough half size.
const MAP_HALF := 200.0
## Outer edge of the south ring road (centre 180 + half of 14 m); roads start
## at -RING in the north unless they say otherwise.
const RING := 187.0
## South edge of the new southern ring road (আজিমপুর রোড).
const SOUTH_Z := 320.0
## North edge of Kallyanpur's ring road (দারুস সালাম রোড).
const NORTH_Z := -320.0
## Outer edges of the east ring (রামপুরা-বাড্ডা রোড) and west ring (বেড়িবাঁধ সড়ক).
const EAST_X := 367.0
const WEST_X := -325.0
## Where Mohammadpur ends and the city begins (a strip of buildings between
## নূরজাহান রোড and এলিফ্যান্ট রোড, crossed by only three roads).
const MOHAMMADPUR_EDGE := -187.0
## East edge of Kallyanpur's roads (ইন্দিরা রোড).
const KALLYANPUR_EAST := 65.0
## Hatirjheel lake (হাতিরঝিল), between the city and Badda.
const HATIRJHEEL := Rect2(187.0, -173.0, 106.0, 346.0)

## [centre x, width, Bangla name, (from z, to z)] - roads running north-south
## (west to east). Roads west of ইন্দিরা রোড continue north into Kallyanpur.
const VERTICAL_ROADS := [
	[-318.0, 14.0, "বেড়িবাঁধ সড়ক", NORTH_Z, SOUTH_Z],
	[-270.0, 10.0, "শাহজাহান রোড", NORTH_Z, SOUTH_Z],
	[-222.0, 10.0, "নূরজাহান রোড", NORTH_Z, SOUTH_Z],
	[-180.0, 14.0, "এলিফ্যান্ট রোড", NORTH_Z, SOUTH_Z],
	[-120.0, 10.0, "কাঁঠালবাগান লেন", NORTH_Z, SOUTH_Z],
	[-60.0, 10.0, "সায়েন্স ল্যাব রোড", NORTH_Z, SOUTH_Z],
	[0.0, 16.0, "মিরপুর রোড", NORTH_Z, SOUTH_Z],
	[60.0, 10.0, "ইন্দিরা রোড", NORTH_Z, SOUTH_Z],
	[120.0, 10.0, "তেজগাঁও লিংক রোড", -RING, SOUTH_Z],
	[180.0, 14.0, "হাতিরঝিল রোড", -RING, SOUTH_Z],
	[300.0, 14.0, "প্রগতি সরণি", -RING, SOUTH_Z],  # Badda side, like the real BRAC University campus
	[360.0, 14.0, "রামপুরা-বাড্ডা রোড", -RING, SOUTH_Z],
]
## [centre z, width, Bangla name, from x, to x, (name in Mohammadpur)] -
## roads running east-west. Only three cross from the city into Mohammadpur;
## two more join them up in Kallyanpur.
const HORIZONTAL_ROADS := [
	# Kallyanpur.
	[-313.0, 14.0, "দারুস সালাম রোড", WEST_X, KALLYANPUR_EAST],
	[-250.0, 10.0, "কল্যাণপুর মেইন রোড", WEST_X, KALLYANPUR_EAST],
	[-180.0, 14.0, "বাড্ডা লিংক রোড", WEST_X, EAST_X, "রিং রোড"],
	[-120.0, 10.0, "পান্থপথ", -187.0, 187.0],
	[-120.0, 10.0, "তাজমহল রোড", WEST_X, -217.0],
	[-120.0, 10.0, "মধ্য বাড্ডা রোড", 293.0, EAST_X],
	[-60.0, 10.0, "হাতিরপুল লেন", -187.0, 187.0],
	[-60.0, 10.0, "সলিমুল্লাহ রোড", WEST_X, -217.0],
	[-60.0, 10.0, "মেরুল বাড্ডা লেন", 293.0, EAST_X],
	[0.0, 14.0, "ফার্মগেট রোড", WEST_X, EAST_X, "আসাদ এভিনিউ"],
	[60.0, 10.0, "রাজাবাজার লেন", -187.0, 187.0],
	[60.0, 10.0, "জাকির হোসেন রোড", WEST_X, -217.0],
	[60.0, 10.0, "রামপুরা রোড", 293.0, EAST_X],
	[120.0, 10.0, "সাতমসজিদ রোড", -187.0, 187.0],
	[120.0, 10.0, "হুমায়ুন রোড", WEST_X, -217.0],
	[120.0, 10.0, "আফতাবনগর রোড", 293.0, EAST_X],
	[180.0, 14.0, "ধানমন্ডি ২৭", WEST_X, EAST_X, "বছিলা রোড"],
	# The south: Azimpur, Shahbag, Moghbazar.
	[250.0, 10.0, "কাঁটাবন রোড", WEST_X, EAST_X],
	[313.0, 14.0, "আজিমপুর রোড", WEST_X, EAST_X],
]

## Landmarks. `curb` is a point on a block edge, `facing` points from the
## block towards the road, `width` is measured along the curb. Landmarks with
## a `dest` name are passenger destinations (drop-off zone on the road).
const LANDMARKS := [
	{"kind": "new_market", "curb": Vector2(-8, -35), "facing": Vector2(1, 0), "width": 24.0,
		"title": "নিউ মার্কেট", "dest": "নিউ মার্কেট"},
	{"kind": "footbridge", "curb": Vector2(8, -17), "facing": Vector2(-1, 0), "width": 3.0,
		"title": "ফার্মগেট", "dest": "ফার্মগেট"},
	# BRAC University in Merul Badda, on Pragati Sarani (north-east of Farmgate).
	{"kind": "university", "curb": Vector2(307, -149), "facing": Vector2(-1, 0), "width": 12.0,
		"title": "ব্র্যাক বিশ্ববিদ্যালয়", "dest": "ব্র্যাক বিশ্ববিদ্যালয়"},
	{"kind": "bus_stand", "curb": Vector2(-8, 35), "facing": Vector2(1, 0), "width": 8.0,
		"title": "বাসস্ট্যান্ড", "dest": "বাসস্ট্যান্ড"},
	{"kind": "bazar", "curb": Vector2(-35, 7), "facing": Vector2(0, -1), "width": 22.0,
		"title": "কারওয়ান বাজার", "dest": "কারওয়ান বাজার"},
	{"kind": "tea_stall", "curb": Vector2(55, 30), "facing": Vector2(1, 0), "width": 4.0,
		"title": "ঢাকা টি স্টল", "dest": "চায়ের দোকান"},
	{"kind": "residential_gate", "curb": Vector2(90, 65), "facing": Vector2(0, -1), "width": 9.0,
		"title": "আবাসিক এলাকা", "dest": "আবাসিক এলাকা"},
	{"kind": "mosque", "curb": Vector2(-8, -100), "facing": Vector2(1, 0), "width": 16.0,
		"title": "বায়তুল আমান মসজিদ", "dest": "মিরপুর রোড"},
	{"kind": "bazar", "curb": Vector2(115, 30), "facing": Vector2(1, 0), "width": 18.0,
		"title": "স্থানীয় বাজার", "dest": "স্থানীয় বাজার"},
	# New in the bigger map.
	{"kind": "bazar", "curb": Vector2(-125, 90), "facing": Vector2(1, 0), "width": 18.0,
		"title": "ধানমন্ডি কাঁচাবাজার", "dest": "ধানমন্ডি কাঁচাবাজার"},
	# Aarong (আড়ং), the crafts and clothing store, on Dhanmondi 27.
	{"kind": "aarong", "curb": Vector2(-90, 173), "facing": Vector2(0, 1), "width": 24.0,
		"title": "আড়ং", "dest": "আড়ং ধানমন্ডি"},
	{"kind": "tea_stall", "curb": Vector2(-65, -90), "facing": Vector2(1, 0), "width": 4.0,
		"title": "মামার চায়ের দোকান", "dest": "মামার চা"},
	{"kind": "residential_gate", "curb": Vector2(-90, -125), "facing": Vector2(0, 1), "width": 9.0,
		"title": "লালমাটিয়া আবাসিক এলাকা", "dest": "লালমাটিয়া"},
	# Mohammadpur (মোহাম্মদপুর), across the canal.
	{"kind": "bazar", "curb": Vector2(-227, -90), "facing": Vector2(1, 0), "width": 18.0,
		"title": "টাউন হল বাজার", "dest": "মোহাম্মদপুর টাউন হল"},
	{"kind": "mosque", "curb": Vector2(-265, 30), "facing": Vector2(-1, 0), "width": 16.0,
		"title": "সাত গম্বুজ মসজিদ", "dest": "সাত গম্বুজ মসজিদ"},
	{"kind": "bus_stand", "curb": Vector2(-227, 90), "facing": Vector2(1, 0), "width": 8.0,
		"title": "মোহাম্মদপুর বাসস্ট্যান্ড", "dest": "মোহাম্মদপুর বাসস্ট্যান্ড"},
	# Kallyanpur (কল্যাণপুর), north on Mirpur Road.
	{"kind": "bus_stand", "curb": Vector2(-8, -280), "facing": Vector2(1, 0), "width": 8.0,
		"title": "কল্যাণপুর বাসস্ট্যান্ড", "dest": "কল্যাণপুর বাসস্ট্যান্ড"},
	{"kind": "bazar", "curb": Vector2(-65, -285), "facing": Vector2(1, 0), "width": 18.0,
		"title": "কল্যাণপুর নতুন বাজার", "dest": "কল্যাণপুর বাজার"},
	# Hatirjheel: water taxi jetty on the lake promenade.
	{"kind": "ghat", "curb": Vector2(187, -90), "facing": Vector2(-1, 0), "width": 10.0,
		"title": "হাতিরঝিল ওয়াটার ট্যাক্সি", "dest": "হাতিরঝিল"},
	# Gulshan Lake Park, entrance on the north ring road.
	{"kind": "park_gate", "curb": Vector2(230, -187), "facing": Vector2(0, 1), "width": 8.0,
		"title": "গুলশান লেক পার্ক", "dest": "গুলশান লেক পার্ক"},
	# The south.
	{"kind": "bazar", "curb": Vector2(-8, 216), "facing": Vector2(1, 0), "width": 18.0,
		"title": "শাহবাগ ফুলের বাজার", "dest": "শাহবাগ"},
	{"kind": "bus_stand", "curb": Vector2(-125, 280), "facing": Vector2(1, 0), "width": 8.0,
		"title": "আজিমপুর বাসস্ট্যান্ড", "dest": "আজিমপুর"},
	{"kind": "tea_stall", "curb": Vector2(115, 216), "facing": Vector2(1, 0), "width": 4.0,
		"title": "মগবাজার মোড় চা", "dest": "মগবাজার"},
	# Not a passenger destination: the mechanic where the rickshaw is repaired.
	{"kind": "garage", "curb": Vector2(8, 40), "facing": Vector2(-1, 0), "width": 10.0,
		"title": "রিকশা মেরামত"},
]

## Distance of a drop-off zone centre from the curb (it sits in the lane).
const DEST_OFFSET := 3.2
const FARMGATE_RADIUS := 30.0


static var _road_cache: Array[Rect2] = []


static func v_from(v: Array) -> float:
	return v[3] if v.size() > 3 else -RING


static func v_to(v: Array) -> float:
	return v[4] if v.size() > 4 else RING


static func h_from(h: Array) -> float:
	return h[3] if h.size() > 3 else -RING


static func h_to(h: Array) -> float:
	return h[4] if h.size() > 4 else RING


## The name of an east-west road at x (some are called differently in Mohammadpur).
static func h_name(h: Array, x: float) -> String:
	return h[5] if h.size() > 5 and x < MOHAMMADPUR_EDGE else h[2]


static func road_rects() -> Array[Rect2]:
	if _road_cache.is_empty():
		for r in VERTICAL_ROADS:
			_road_cache.append(Rect2(r[0] - r[1] * 0.5, v_from(r), r[1], v_to(r) - v_from(r)))
		for r in HORIZONTAL_ROADS:
			_road_cache.append(Rect2(h_from(r), r[0] - r[1] * 0.5, h_to(r) - h_from(r), r[1]))
	return _road_cache


static func is_road(x: float, z: float) -> bool:
	for r in road_rects():
		if r.has_point(Vector2(x, z)):
			return true
	return false


static func _on_v(r: Array, x: float, z: float) -> bool:
	return absf(x - r[0]) <= r[1] * 0.5 and z >= v_from(r) and z <= v_to(r)


static func _on_h(r: Array, x: float, z: float) -> bool:
	return absf(z - r[0]) <= r[1] * 0.5 and x >= h_from(r) and x <= h_to(r)


## Directions you can drive along at a point: ±Z on north-south roads,
## ±X on east-west roads, all four inside an intersection.
static func road_directions_at(x: float, z: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for r in VERTICAL_ROADS:
		if _on_v(r, x, z):
			out.append_array([Vector3.FORWARD, Vector3.BACK])
			break
	for r in HORIZONTAL_ROADS:
		if _on_h(r, x, z):
			out.append_array([Vector3.LEFT, Vector3.RIGHT])
			break
	return out


## Name of the road at a point, or "" if not on a road.
static func road_name_at(x: float, z: float) -> String:
	var best := ""
	var best_width := 0.0
	for r in VERTICAL_ROADS:
		if _on_v(r, x, z) and r[1] > best_width:
			best = r[2]
			best_width = r[1]
	for r in HORIZONTAL_ROADS:
		if _on_h(r, x, z) and r[1] > best_width:
			best = h_name(r, x)
			best_width = r[1]
	return best


static func _cuts(roads: Array, lo: float, hi: float) -> Array[float]:
	var cuts: Array[float] = [lo, hi]
	for r in roads:
		cuts.append(r[0] - r[1] * 0.5)
		cuts.append(r[0] + r[1] * 0.5)
	cuts.sort()
	return cuts


## Every rectangle between the roads becomes a city block (raised sidewalk
## with buildings), including the strip outside the ring roads.
static func block_rects() -> Array[Rect2]:
	var xs := _cuts(VERTICAL_ROADS, MAP.position.x, MAP.end.x)
	var zs := _cuts(HORIZONTAL_ROADS, MAP.position.y, MAP.end.y)
	var out: Array[Rect2] = []
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var r := Rect2(xs[i], zs[j], xs[i + 1] - xs[i], zs[j + 1] - zs[j])
			if r.size.x < 0.5 or r.size.y < 0.5:
				continue
			var c := r.get_center()
			if not is_road(c.x, c.y):
				out.append(r)
	return out


## The north-east of the map is Badda (বাড্ডা).
const BADDA := Rect2(293.0, -200.0, 87.0, 400.0)
## The BRAC University campus block, in Badda.
const CAMPUS := Rect2(307.0, -173.0, 46.0, 48.0)
## West of Lalmatia: Mohammadpur (মোহাম্মদপুর), where muggers (ছিনতাইকারী) lurk.
const MOHAMMADPUR := Rect2(-340.0, -173.0, 153.0, 360.0)
## The open north-east: Gulshan Lake Park (গুলশান লেক পার্ক).
const PARK := Rect2(65.0, -333.0, 315.0, 146.0)
const PARK_POND := Rect2(215.0, -298.0, 50.0, 34.0)
## The south band: Azimpur (west), Shahbag (middle), Moghbazar (east).
const SOUTH_BAND := Rect2(-340.0, 187.0, 720.0, 146.0)
## North of everything: Kallyanpur (কল্যাণপুর).
const KALLYANPUR := Rect2(-340.0, -333.0, 405.0, 146.0)
## South-west of Farmgate: Dhanmondi (ধানমন্ডি).
const DHANMONDI := Rect2(-187.0, 60.0, 179.0, 140.0)


## Building style for a block: "market", "residential", "campus", "lake" or "mixed".
static func district_for(center: Vector2) -> String:
	if HATIRJHEEL.has_point(center):
		return "lake"
	if PARK.has_point(center):
		return "park"
	if CAMPUS.has_point(center):
		return "campus"
	if center.x > -120 and center.x < -8 and absf(center.y) < 60:
		return "market"
	if center.x > 8 and center.x < 173 and center.y > 60 and center.y < 173:
		return "residential"
	if center.x > 65 and center.x < 173 and center.y > 7 and center.y < 60:
		return "residential"
	return "mixed"


static func in_mohammadpur(p: Vector3) -> bool:
	return MOHAMMADPUR.has_point(Vector2(p.x, p.z))


## Name of the southern area at x.
static func south_area(x: float) -> String:
	if x < -60.0:
		return "আজিমপুর"
	if x < 120.0:
		return "শাহবাগ"
	return "মগবাজার"


## Bangla area name for the HUD.
static func area_name_at(x: float, z: float) -> String:
	if Vector2(x, z).length() < FARMGATE_RADIUS:
		return "ফার্মগেট"
	if MOHAMMADPUR.has_point(Vector2(x, z)):
		var road := road_name_at(x, z)
		return "মোহাম্মদপুর" + ("" if road == "" else " • " + road)
	if SOUTH_BAND.has_point(Vector2(x, z)) and z > 190.0 and is_road(x, z):
		return south_area(x) + " • " + road_name_at(x, z)
	if KALLYANPUR.has_point(Vector2(x, z)) and z < -190.0:
		var road := road_name_at(x, z)
		return "কল্যাণপুর" + ("" if road == "" else " • " + road)
	if HATIRJHEEL.has_point(Vector2(x, z)) or (HATIRJHEEL.grow(8.0).has_point(Vector2(x, z)) and is_road(x, z)):
		return "হাতিরঝিল সেতু" if is_road(x, z) and absf(z) < 10.0 else "হাতিরঝিল"
	if is_road(x, z):
		return road_name_at(x, z)
	if PARK.has_point(Vector2(x, z)):
		return "গুলশান লেক পার্ক"
	match district_for(Vector2(x, z)):
		"campus":
			return "ব্র্যাক বিশ্ববিদ্যালয়, বাড্ডা"
		"residential":
			return "আবাসিক এলাকা"
		"market":
			return "নিউ মার্কেট" if z < 0 else "কারওয়ান বাজার"
	if BADDA.has_point(Vector2(x, z)):
		return "বাড্ডা"
	if KALLYANPUR.has_point(Vector2(x, z)):
		return "কল্যাণপুর"
	if SOUTH_BAND.has_point(Vector2(x, z)):
		return south_area(x)
	if DHANMONDI.has_point(Vector2(x, z)):
		return "ধানমন্ডি"
	return "ঢাকা"


## Passenger destinations: [{name, position (on the road), landmark, sidewalk (drop-off point)}].
static func destinations() -> Array:
	var out := []
	for lm in LANDMARKS:
		if not lm.has("dest"):
			continue
		var p: Vector2 = lm.curb + lm.facing * DEST_OFFSET
		# Where passengers stand: on the sidewalk's walking line behind the kerb.
		var walk: Vector2 = lm.curb - lm.facing * 1.5
		out.append({"name": lm.dest, "position": Vector3(p.x, 0.0, p.y), "landmark": lm.title,
			"sidewalk": Vector3(walk.x, 0.15, walk.y)})
	return out


## The repair bay on the road in front of the mechanic: [position, facing].
static func repair_bay() -> Array:
	for lm in LANDMARKS:
		if lm.kind == "garage":
			var p: Vector2 = lm.curb + lm.facing * DEST_OFFSET
			return [Vector3(p.x, 0.0, p.y), Vector3(lm.facing.x, 0.0, lm.facing.y)]
	return []


## All intersections as [Vector2 centre, vertical road, horizontal road].
static func intersections() -> Array:
	var out := []
	for v in VERTICAL_ROADS:
		for h in HORIZONTAL_ROADS:
			if v[0] >= h_from(h) and v[0] <= h_to(h) and h[0] >= v_from(v) and h[0] <= v_to(v):
				out.append([Vector2(v[0], h[0]), v, h])
	return out


## Number of traffic lanes: two for each stretch of road between neighbouring
## intersections.
static func lane_count() -> int:
	var count := 0
	for v in VERTICAL_ROADS:
		var n := 0
		for it in intersections():
			if it[1] == v:
				n += 1
		count += maxi(n - 1, 0) * 2
	for h in HORIZONTAL_ROADS:
		var n := 0
		for it in intersections():
			if it[2] == h:
				n += 1
		count += maxi(n - 1, 0) * 2
	return count
