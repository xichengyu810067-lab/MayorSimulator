extends SceneTree

const TransportModesScript = preload("res://data/catalogs/transport_modes.gd")

var _failed := false
var _checks := 0


func _initialize() -> void:
	var fixtures := {
		0: [0, 0],
		1: [1_000, 300],
		10: [10_000, 3_000],
		11: [11_020, 3_306],
		12: [12_081, 3_625],
	}
	for tile_count_variant: Variant in fixtures.keys():
		var tile_count := int(tile_count_variant)
		var expected: Array = fixtures[tile_count]
		var quote: Dictionary = TransportModesScript.route_package_price_quote(tile_count)
		_check(int(quote.get("construction_cost", -1)) == int(expected[0]), "construction fixture L=%d" % tile_count)
		_check(int(quote.get("monthly_maintenance", -1)) == int(expected[1]), "maintenance fixture L=%d" % tile_count)
		_check(int(quote.get("route_tile_count", -1)) == tile_count, "quote retains route tile count L=%d" % tile_count)
		_check(str(quote.get("price_model", "")) == "route_package_v1", "quote is versioned L=%d" % tile_count)
	_check(TransportModesScript.route_package_construction_cost(-1) == 0, "negative construction length clamps to zero")
	_check(TransportModesScript.route_package_monthly_maintenance(-1) == 0, "negative maintenance length clamps to zero")
	if not _failed:
		print("Transport route package pricing test passed. Checks=%d" % _checks)
	quit(1 if _failed else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Transport route package pricing test failed: %s" % label)
