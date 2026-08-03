class_name TransportVehicleVisuals
extends RefCounted

## Canonical authored-sprite catalog for every moving transport kind.
##
## Vehicle topology remains owned by TransportModes and the transport runtime;
## this catalog only maps those authoritative kinds to presentation assets.

const TransportModesCatalog := preload("res://data/catalogs/transport_modes.gd")

const ASSET_PATHS := {
	"car": "res://assets/images/world/transport/vehicles/car.png",
	"motorcycle": "res://assets/images/world/transport/vehicles/motorcycle.png",
	"bus": "res://assets/images/world/transport/vehicles/bus.png",
	"metro_train": "res://assets/images/world/transport/vehicles/metro_train.png",
	"train": "res://assets/images/world/transport/vehicles/train.png",
	"plane": "res://assets/images/world/transport/vehicles/plane.png",
}

const DISPLAY_BOUNDS := {
	"car": Vector2(58, 42),
	"motorcycle": Vector2(56, 46),
	"bus": Vector2(76, 46),
	"metro_train": Vector2(80, 48),
	"train": Vector2(82, 48),
	"plane": Vector2(86, 58),
}


static func asset_path(vehicle_kind: String) -> String:
	return str(ASSET_PATHS.get(vehicle_kind, ""))


static func display_bounds(vehicle_kind: String) -> Vector2:
	return Vector2(DISPLAY_BOUNDS.get(vehicle_kind, Vector2(56, 42)))


static func texture(vehicle_kind: String) -> Texture2D:
	var path := asset_path(vehicle_kind)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func required_vehicle_kinds() -> Array[String]:
	var result: Array[String] = ["car", "motorcycle"]
	for mode: String in TransportModesCatalog.route_modes():
		var kind := str(TransportModesCatalog.route_spec(mode).get("vehicle_kind", ""))
		if not kind.is_empty() and kind not in result:
			result.append(kind)
	result.sort()
	return result


static func validation_snapshot() -> Dictionary:
	var issues: Array[String] = []
	for kind: String in required_vehicle_kinds():
		var path := asset_path(kind)
		if path.is_empty():
			issues.append("vehicle:%s:missing_asset_mapping" % kind)
			continue
		if not ResourceLoader.exists(path):
			issues.append("vehicle:%s:missing_asset:%s" % [kind, path])
		if not DISPLAY_BOUNDS.has(kind):
			issues.append("vehicle:%s:missing_display_bounds" % kind)
	return {
		"valid": issues.is_empty(),
		"issues": issues,
		"required_vehicle_kinds": required_vehicle_kinds(),
		"asset_paths": ASSET_PATHS.duplicate(true),
		"presentation_only": true,
	}
