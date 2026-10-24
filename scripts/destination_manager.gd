## Creates and manages the passenger drop-off zones defined in CityLayout.
##
## The passenger system (Milestone 4) asks this manager for a destination and
## activates its marker; it never makes up positions of its own, so every
## destination is a reachable spot on the road.
extends Node3D

const CityLayout := preload("res://scripts/city_layout.gd")
const DestinationZone := preload("res://scripts/destination_zone.gd")

## Show every zone marker (handy for testing the map layout).
@export var show_all_markers := false
@export var zone_radius := 5.0

var zones: Array[DestinationZone] = []


func _ready() -> void:
	for d in CityLayout.destinations():
		var zone := DestinationZone.new()
		add_child(zone)
		zone.setup(d.name, d.position, zone_radius)
		zone.sidewalk_point = d.sidewalk
		zone.set_active(show_all_markers)
		zones.append(zone)


func get_zone(zone_name: String) -> DestinationZone:
	for z in zones:
		if z.zone_name == zone_name:
			return z
	return null


## The zone whose circle contains `pos` (ignoring height), or null.
func zone_at(pos: Vector3) -> DestinationZone:
	for z in zones:
		var d := Vector2(pos.x - z.global_position.x, pos.z - z.global_position.z)
		if d.length() <= z.radius:
			return z
	return null


## A random destination at least `min_distance` metres from `from_pos`,
## never the excluded zone. Falls back to the farthest zone.
func pick_destination(from_pos: Vector3, min_distance := 60.0, exclude: DestinationZone = null) -> DestinationZone:
	var candidates: Array[DestinationZone] = []
	var farthest: DestinationZone = null
	var best := -1.0
	for z in zones:
		if z == exclude:
			continue
		var dist := from_pos.distance_to(z.global_position)
		if dist >= min_distance:
			candidates.append(z)
		if dist > best:
			best = dist
			farthest = z
	if candidates.is_empty():
		return farthest
	return candidates[randi() % candidates.size()]


func set_active_zone(zone: DestinationZone) -> void:
	for z in zones:
		z.set_active(z == zone or show_all_markers)
