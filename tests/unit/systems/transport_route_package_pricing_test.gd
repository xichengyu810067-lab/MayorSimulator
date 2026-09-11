extends SceneTree

const TransportModesScript = preload("res://data/catalogs/transport_modes.gd")

var _failed := false
var _checks := 0


func _initialize() -> void:
	var legacy_fixtures := {
		0: [0, 0],
		1: [1_000, 300],
		10: [10_000, 3_000],
		11: [11_020, 3_306],
		12: [12_081, 3_625],
	}
	for tile_count_variant: Variant in legacy_fixtures.keys():
		var tile_count := int(tile_count_variant)
		var expected: Array = legacy_fixtures[tile_count]
		var legacy_quote: Dictionary = TransportModesScript.route_package_v1_price_quote(tile_count)
		_check(int(legacy_quote.get("construction_cost", -1)) == int(expected[0]), "legacy construction fixture L=%d" % tile_count)
		_check(int(legacy_quote.get("monthly_maintenance", -1)) == int(expected[1]), "legacy maintenance fixture L=%d" % tile_count)
		_check(str(legacy_quote.get("price_model", "")) == "route_package_v1", "legacy quote stays versioned L=%d" % tile_count)
		var current_quote: Dictionary = TransportModesScript.route_package_price_quote(tile_count)
		_check(bool(current_quote.get("ok", false)), "known v2 road quote succeeds L=%d" % tile_count)
		_check(int(current_quote.get("construction_cost", -1)) == tile_count * 520, "v2 road construction follows the segment catalog L=%d" % tile_count)
		_check(int(current_quote.get("monthly_maintenance", -1)) == tile_count * 18, "v2 road maintenance follows the segment catalog L=%d" % tile_count)
		_check(int(current_quote.get("route_tile_count", -1)) == tile_count, "v2 quote retains route tile count L=%d" % tile_count)
		_check(str(current_quote.get("price_model", "")) == "route_package_v2", "current quote is v2 L=%d" % tile_count)
		_check(str(current_quote.get("price_provenance", "")) == TransportModesScript.ROUTE_PACKAGE_PRICE_PROVENANCE, "v2 quote identifies its authoritative source L=%d" % tile_count)
	_check(TransportModesScript.route_package_construction_cost(-1) == 0, "negative construction length clamps to zero")
	_check(TransportModesScript.route_package_monthly_maintenance(-1) == 0, "negative maintenance length clamps to zero")
	_check(TransportModesScript.is_route_package_price_model("route_package_v1"), "v1 remains a supported historical model")
	_check(TransportModesScript.is_route_package_price_model("route_package_v2"), "v2 is supported for new packages")
	_check(TransportModesScript.is_route_package_price_model("route_package_v3"), "v3 is supported for reuse-aware corridor quotes")
	_check(not TransportModesScript.is_route_package_price_model("route_package_v4"), "unknown models fail closed")
	var mixed_contract := {
		"schema_version": TransportModesScript.ROUTE_PACKAGE_CORRIDOR_SCHEMA_VERSION,
		"mode": "bus",
		"segment_kind": "road",
		"classification": "mixed",
		"route_tile_ids": [0, 1, 2, 3],
		"reused_segment_refs": [{"id": "segment_a", "kind": "road", "tile_ids": [0, 1]}],
		"new_runs": [{"kind": "road", "tile_path": [2, 3]}],
		"total_units": 4,
		"reused_units": 2,
		"new_units": 2,
	}
	var mixed_quote := TransportModesScript.route_package_corridor_price_quote(mixed_contract)
	_check(bool(mixed_quote.get("ok", false)), "valid reuse-aware corridor quote succeeds")
	_check(str(mixed_quote.get("price_model", "")) == "route_package_v3", "reuse-aware corridor quote uses price model v3")
	_check(int(mixed_quote.get("total_cost", -1)) == 1_040, "v3 charges only two new road units")
	_check(int(mixed_quote.get("monthly_maintenance", -1)) == 36, "v3 maintenance charges only two new road units")
	_check(int(mixed_quote.get("price_breakdown", {}).get("reused_corridor", -1)) == 0, "v3 reused corridor construction is never charged")
	_check(int(mixed_quote.get("maintenance_breakdown", {}).get("reused_corridor", -1)) == 0, "v3 reused corridor maintenance is never charged")
	_check(bool(TransportModesScript.validate_route_package_corridor_price_quote(mixed_quote).get("valid", false)), "v3 quote checksum and version validate")
	for field_name: String in ["total_cost", "checksum_version", "quote_schema_version"]:
		var tampered := mixed_quote.duplicate(true)
		tampered[field_name] = int(tampered.get(field_name, 0)) + 1
		_check(not bool(TransportModesScript.validate_route_package_corridor_price_quote(tampered).get("valid", true)), "tampered v3 %s fails closed" % field_name)
	var tampered_breakdown := mixed_quote.duplicate(true)
	tampered_breakdown["price_breakdown"]["reused_corridor"] = 1
	_check(not bool(TransportModesScript.validate_route_package_corridor_price_quote(tampered_breakdown).get("valid", true)), "reused corridor charge fails closed")
	var tampered_checksum := mixed_quote.duplicate(true)
	tampered_checksum["checksum"] = "0".repeat(64)
	_check(not bool(TransportModesScript.validate_route_package_corridor_price_quote(tampered_checksum).get("valid", true)), "forged v3 checksum fails closed")
	var all_reuse_contract := mixed_contract.duplicate(true)
	all_reuse_contract["classification"] = "all_reuse"
	all_reuse_contract["reused_segment_refs"] = [{"id": "segment_a", "kind": "road", "tile_ids": [0, 1, 2, 3]}]
	all_reuse_contract["new_runs"] = []
	all_reuse_contract["reused_units"] = 4
	all_reuse_contract["new_units"] = 0
	var all_reuse_quote := TransportModesScript.route_package_corridor_price_quote(all_reuse_contract)
	_check(bool(all_reuse_quote.get("ok", false)) and int(all_reuse_quote.get("total_cost", -1)) == 0, "all-reuse v3 corridor is a deterministic zero-cost quote")
	var unknown_quote: Dictionary = TransportModesScript.route_package_price_quote(3, "hover_lane")
	_check(not bool(unknown_quote.get("ok", true)), "unknown network kind fails closed")
	_check(str(unknown_quote.get("error", "")) == "invalid_network_kind", "unknown network kind reports a stable error")
	_check(not unknown_quote.has("construction_cost") and not unknown_quote.has("monthly_maintenance"), "unknown network kind exposes no zero-cost price fields")
	if not _failed:
		print("Transport route package pricing test passed. Checks=%d" % _checks)
	quit(1 if _failed else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Transport route package pricing test failed: %s" % label)
