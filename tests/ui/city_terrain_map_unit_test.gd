extends SceneTree

const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")
const CityTerrainLayoutScript = preload("res://data/catalogs/city_terrain_layout.gd")
const CityBackdropTerrainCatalog = preload("res://data/catalogs/city_backdrop_terrain.gd")
const TERRAIN_STEP01_FIXTURE := "res://tests/fixtures/terrain_step01_ground_truth.json"
const TERRAIN_STEP01_DIAGNOSTIC_ENV := "MAYOR_TERRAIN_STEP01_DIAGNOSTIC"
const TERRAIN_STEP01_OUTPUT_ROOT_ENV := "MAYOR_TERRAIN_STEP01_OUTPUT_ROOT"
const TERRAIN_STEP01_FIXTURE_OVERRIDE_ENV := "MAYOR_TERRAIN_STEP01_FIXTURE_PATH"
const TERRAIN_STEP01_NEGATIVE_CONTROL_ENV := "MAYOR_TERRAIN_STEP01_NEGATIVE_CONTROL"
const TERRAIN_STEP01_UNION_TOLERANCE := 0.001

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var terrain = CityTerrainMapScript.new()
	_check(terrain.grid_size() == Vector2i(10, 10), "terrain grid is not 10x10")
	_check(terrain.cell_count() == 100, "terrain grid does not expose 100 logical tiles")
	_check(terrain.coordinate_for_tile_id(0) == Vector2i(1, 1), "legacy tile 0 moved")
	_check(terrain.coordinate_for_tile_id(7) == Vector2i(8, 1), "legacy tile 7 moved")
	_check(terrain.coordinate_for_tile_id(8) == Vector2i(1, 2), "legacy tile 8 moved")
	_check(terrain.coordinate_for_tile_id(63) == Vector2i(8, 8), "legacy tile 63 moved")
	_check(terrain.coordinate_for_tile_id(64) == Vector2i(0, 0), "outer-ring tile 64 is unstable")
	_check(terrain.coordinate_for_tile_id(73) == Vector2i(9, 0), "outer-ring top-right id is unstable")
	_check(terrain.coordinate_for_tile_id(74) == Vector2i(0, 1), "outer-ring left id is unstable")
	_check(terrain.coordinate_for_tile_id(75) == Vector2i(9, 1), "outer-ring right id is unstable")
	_check(terrain.coordinate_for_tile_id(90) == Vector2i(0, 9), "outer-ring bottom-left id is unstable")
	_check(terrain.coordinate_for_tile_id(99) == Vector2i(9, 9), "outer-ring tile 99 is unstable")

	var seen_coordinates: Dictionary = {}
	for tile_id in range(terrain.cell_count()):
		var coordinate: Vector2i = terrain.coordinate_for_tile_id(tile_id)
		_check(not seen_coordinates.has(coordinate), "duplicate coordinate %s" % coordinate)
		seen_coordinates[coordinate] = true
		_check(terrain.tile_id_for_coordinate(coordinate) == tile_id, "tile/coordinate round trip failed for %d" % tile_id)
	_check(seen_coordinates.size() == 100, "coordinate map does not cover all 100 cells")
	_check(terrain.tile_ids_in_display_order()[0] == 64, "display order does not start at coordinate (0,0)")
	_check(terrain.tile_id_for_coordinate(Vector2i(1, 1)) == 0, "legacy center coordinate no longer resolves to tile 0")

	var expected_kinds := PackedStringArray([
		"flat_grass", "trees", "hill_cliff", "river_lake", "road_path", "rail_track"
	])
	for kind: String in expected_kinds:
		_check(terrain.terrain_kinds().has(kind), "terrain catalog omits %s" % kind)

	var backdrop_terrain = CityTerrainMapScript.new()
	backdrop_terrain.apply_default_city_layout()
	_check(backdrop_terrain.base_kind(12) == "river_lake", "square tile 12 is not classified as river/lake")
	_check(not backdrop_terrain.is_buildable(12) and not backdrop_terrain.is_walkable(12), "square tile 12 is not blocked")
	var modeled_count := 0
	for state_variant: Variant in backdrop_terrain.all_tile_states():
		var state: Dictionary = state_variant
		if str(state.get("base_kind", "")) == "flat_grass":
			continue
		modeled_count += 1
		_check(str(state.get("terrain_source", "")) == "background_image", "natural plot is not background-derived")
		_check(str(state.get("source_asset", "")).ends_with("city-map-background.png"), "natural plot lost source backdrop")
		_check(not Array(state.get("backdrop_feature_ids", [])).is_empty(), "natural plot lacks backdrop feature ids")
	_check(modeled_count > 0 and modeled_count < 100, "backdrop model did not produce a mixed buildable/non-buildable grid")

	for fixture: Dictionary in [
		{"tile": 0, "kind": "trees"},
		{"tile": 1, "kind": "hill_cliff"},
		{"tile": 2, "kind": "river_lake"},
		{"tile": 3, "kind": "road_path"},
		{"tile": 4, "kind": "rail_track"},
	]:
		var tile_id := int(fixture["tile"])
		_check(terrain.set_tile_kind(tile_id, str(fixture["kind"])), "could not configure terrain fixture")
		_check(not terrain.is_buildable(tile_id), "%s terrain is buildable before flattening" % fixture["kind"])
		_check(not terrain.is_walkable(tile_id), "%s terrain is walkable before flattening" % fixture["kind"])
		_check(terrain.is_flattenable(tile_id), "%s terrain is not flattenable" % fixture["kind"])

	var flattened: Dictionary = terrain.flatten_tile(0)
	_check(bool(flattened.get("ok", false)) and bool(flattened.get("changed", false)), "tree tile did not flatten")
	_check(terrain.base_kind(0) == "trees", "flattening destroyed the backdrop-authoritative base terrain")
	_check(terrain.effective_kind(0) == "flat_grass", "flattening did not resolve to flat grass")
	_check(terrain.is_buildable(0) and terrain.is_walkable(0), "flattened tile did not become buildable/walkable")
	_check(not terrain.is_flattenable(0), "already flattened tile remains flattenable")
	_check(terrain.restore_base_terrain(0), "base terrain could not be restored")
	_check(not terrain.is_walkable(0) and terrain.effective_kind(0) == "trees", "restoring base terrain did not restore its blocker")
	var flat_tile_id := -1
	for tile_id in terrain.cell_count():
		if terrain.base_kind(tile_id) == "flat_grass":
			flat_tile_id = tile_id
			break
	_check(flat_tile_id >= 0, "terrain fixture has no flat grass tile")
	_check(bool(terrain.flatten_tile(flat_tile_id).get("ok", false)) and not bool(terrain.flatten_tile(flat_tile_id).get("changed", true)), "flat grass flatten is not idempotent")
	_check(not terrain.set_tile_kind(5, "lava"), "unknown terrain kind was accepted")
	_check(not bool(terrain.flatten_tile(100).get("ok", true)), "out-of-range tile flattened")

	terrain.flatten_tile(0)
	var serialized: Dictionary = terrain.to_dict()
	_check(int(serialized.get("layout_version", -1)) == 4, "fresh terrain snapshot does not write layout 4")
	_check(str(serialized.get("classification_provenance", "")) == "backdrop_square_layout_4", "fresh terrain snapshot lost layout 4 provenance")
	_check(bool(CityTerrainMapScript.validate_snapshot(serialized).get("valid", false)), "canonical full terrain snapshot was rejected")
	var legacy_layout_two := serialized.duplicate(true)
	legacy_layout_two["layout_version"] = 2
	legacy_layout_two.erase("classification_provenance")
	var legacy_tiles_json := JSON.stringify(legacy_layout_two["tiles"])
	_check(not bool(CityTerrainMapScript.validate_snapshot(legacy_layout_two).get("valid", true)), "strict current validation accepted legacy layout 2 directly")
	var migrated_layout_four := CityTerrainMapScript.migrate_snapshot_to_current(legacy_layout_two)
	_check(int(migrated_layout_four.get("layout_version", -1)) == 4, "layout 2 did not migrate to layout 4")
	_check(str(migrated_layout_four.get("classification_provenance", "")) == "preserved_layout_2", "layout 2 migration lost provenance")
	_check(JSON.stringify(migrated_layout_four.get("tiles", [])) == legacy_tiles_json, "layout migration changed one or more of the 100 tile records")
	_check(Array(migrated_layout_four.get("tiles", [])).size() == 100, "layout migration did not retain 100 tile records")
	_check(
		CityTerrainMapScript.migrate_snapshot_to_current(migrated_layout_four) == migrated_layout_four,
		"layout migration is not re-entrant on an already-current snapshot"
	)
	var missing_provenance := serialized.duplicate(true)
	missing_provenance.erase("classification_provenance")
	_check(not bool(CityTerrainMapScript.validate_snapshot(missing_provenance).get("valid", true)), "current terrain without provenance was accepted")
	var unknown_provenance := serialized.duplicate(true)
	unknown_provenance["classification_provenance"] = "unknown"
	_check(not bool(CityTerrainMapScript.validate_snapshot(unknown_provenance).get("valid", true)), "unknown terrain provenance was accepted")
	var duplicate_tile_snapshot: Dictionary = serialized.duplicate(true)
	duplicate_tile_snapshot["tiles"][99]["tile_id"] = 98
	_check(not bool(CityTerrainMapScript.validate_snapshot(duplicate_tile_snapshot).get("valid", true)), "duplicate terrain tile id was accepted")
	var missing_tile_snapshot: Dictionary = serialized.duplicate(true)
	missing_tile_snapshot["tiles"].resize(99)
	_check(not bool(CityTerrainMapScript.validate_snapshot(missing_tile_snapshot).get("valid", true)), "incomplete terrain coverage was accepted")
	var unknown_kind_snapshot: Dictionary = serialized.duplicate(true)
	unknown_kind_snapshot["tiles"][5]["base_kind"] = "lava"
	_check(not bool(CityTerrainMapScript.validate_snapshot(unknown_kind_snapshot).get("valid", true)), "unknown terrain kind was accepted by snapshot validation")
	var impossible_flat_snapshot: Dictionary = serialized.duplicate(true)
	impossible_flat_snapshot["tiles"][5]["flattened"] = true
	_check(not bool(CityTerrainMapScript.validate_snapshot(impossible_flat_snapshot).get("valid", true)), "flat grass with flattened=true was accepted")
	var non_boolean_snapshot: Dictionary = serialized.duplicate(true)
	non_boolean_snapshot["tiles"][5]["flattened"] = 0
	_check(not bool(CityTerrainMapScript.validate_snapshot(non_boolean_snapshot).get("valid", true)), "non-boolean flattened flag was accepted")
	var wrong_layout_snapshot: Dictionary = serialized.duplicate(true)
	wrong_layout_snapshot["layout_version"] = int(serialized["layout_version"]) + 1
	_check(not bool(CityTerrainMapScript.validate_snapshot(wrong_layout_snapshot).get("valid", true)), "unknown terrain layout version was accepted")
	var restored = CityTerrainMapScript.create_from_dict(serialized)
	_check(restored.coordinate_for_tile_id(63) == Vector2i(8, 8), "serialization changed legacy mapping")
	_check(restored.base_kind(0) == "trees" and restored.is_flattened(0), "flattened terrain did not round-trip")
	_check(restored.effective_kind(3) == "road_path" and not restored.is_walkable(3), "road blocker did not round-trip")
	_check(restored.effective_kind(4) == "rail_track" and not restored.is_walkable(4), "rail blocker did not round-trip")

	var compact = CityTerrainMapScript.create_from_dict({
		"terrain_by_tile": {
			"64": {"base_kind": "river_lake", "flattened": false},
			"65": {"base_kind": "rail_track", "flattened": true},
			"66": {"base_kind": "unknown", "flattened": true},
		}
	})
	_check(compact.effective_kind(64) == "river_lake", "compact river state did not load")
	_check(compact.effective_kind(65) == "flat_grass" and compact.base_kind(65) == "rail_track", "compact flattened rail did not load")
	_check(compact.effective_kind(66) == "flat_grass", "invalid compact terrain did not retain safe default")

	var centers := PackedVector2Array()
	centers.resize(100)
	for tile_id in range(100):
		centers[tile_id] = Vector2(200 + tile_id, 400)
	var blockers: Dictionary = restored.navigation_blockers(centers)
	_check(blockers.has(3) and str(blockers[3].get("kind", "")) == "road_path", "road navigation blocker is missing")
	_check(blockers.has(4) and str(blockers[4].get("kind", "")) == "rail_track", "rail navigation blocker is missing")
	_check(not blockers.has(0), "flattened tree still emits a navigation blocker")
	_run_terrain_step01_diagnostic_if_requested()

	if not _failed:
		print("City terrain map unit test passed. Checks=%d Cells=100 Legacy=64 OuterRing=36" % _checks)
	quit(1 if _failed else 0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("City terrain map unit test failed: %s" % message)


func _run_terrain_step01_diagnostic_if_requested() -> void:
	if OS.get_environment(TERRAIN_STEP01_DIAGNOSTIC_ENV) != "1":
		return
	var fixture := _load_terrain_step01_fixture()
	if fixture.is_empty():
		return
	var terrain = CityTerrainMapScript.new()
	terrain.apply_default_city_layout()
	var centers := PackedVector2Array()
	centers.resize(terrain.cell_count())
	for tile_id in range(terrain.cell_count()):
		centers[tile_id] = Vector2(200 + tile_id, 400)
	var blockers: Dictionary = terrain.navigation_blockers(centers)
	var sample_results: Array = []
	for sample_variant: Variant in Array(fixture.get("samples", [])):
		var sample: Dictionary = sample_variant
		var tile_id := int(sample.get("tile_id", -1))
		var expected_kinds: Array = Array(sample.get("expected_obstacle_kinds", []))
		var actual_kind := terrain.base_kind(tile_id)
		var buildable := terrain.is_buildable(tile_id)
		var walkable := terrain.is_walkable(tile_id)
		var has_blocker := blockers.has(tile_id)
		var blocked := not buildable and not walkable and has_blocker
		var result := {
			"id": str(sample.get("id", "")),
			"label": _sample_label(sample),
			"tile_id": tile_id,
			"grid": Array(sample.get("grid", [])),
			"witnesses": Array(sample.get("witnesses", [])),
			"expected_obstacle_kinds": expected_kinds,
			"actual_kind": actual_kind,
			"actual_feature_ids": Array(terrain.tile_state(tile_id).get("backdrop_feature_ids", [])),
			"buildable": buildable,
			"walkable": walkable,
			"navigation_blocker": has_blocker,
			"difference": "",
		}
		if expected_kinds.is_empty():
			var flat_ok := actual_kind == "flat_grass" and buildable and walkable and not has_blocker
			result["difference"] = "一致：可蓋、可走且無自然 blocker" if flat_ok else "意外障礙或平地契約不一致"
			_check(flat_ok, "%s expected visible flat ground" % result["id"])
		elif expected_kinds.size() > 1:
			result["difference"] = "混合格表示限制：witness 僅證明兩種障礙存在，不要求唯一 winner kind"
			_check(blocked, "%s missed obstacle as flat/buildable/walkable" % result["id"])
		elif not blocked:
			result["difference"] = "漏標成平地而可蓋/可走：缺少自然 blocker"
			_check(false, "%s missed obstacle as flat/buildable/walkable" % result["id"])
		elif actual_kind != str(expected_kinds[0]):
			result["difference"] = "種類錯但仍被阻擋"
			_check(false, "%s kind mismatch while still blocked: expected=%s actual=%s" % [result["id"], expected_kinds[0], actual_kind])
		else:
			result["difference"] = "一致：種類與 blocker 均符合此 witness 的有限主張"
		sample_results.append(result)

	var geometry_results: Array = []
	var plot_rect := Rect2(Vector2.ZERO, Vector2(100, 100))
	for geometry_variant: Variant in Array(fixture.get("geometry_cases", [])):
		var geometry_case: Dictionary = geometry_variant
		var polygons := _fixture_polygons(Array(geometry_case.get("polygons", [])))
		var classification := CityTerrainLayoutScript._classify_plot_rect(plot_rect, polygons)
		var expected: Dictionary = geometry_case.get("expected", {})
		var expected_blocked := bool(expected.get("blocked", false))
		var actual_blocked := str(classification.get("kind", "flat_grass")) != "flat_grass"
		var union_area := _polygon_union_area(plot_rect, polygons)
		var expected_union_area := float(expected.get("union_area", 0.0))
		var union_oracle_match := absf(union_area - expected_union_area) <= TERRAIN_STEP01_UNION_TOLERANCE
		var result := {
			"id": str(geometry_case.get("id", "")),
			"expected_blocked": expected_blocked,
			"actual_blocked": actual_blocked,
			"expected_union_area": expected_union_area,
			"actual_union_area": union_area,
			"union_oracle_match": union_oracle_match,
			"actual_kind": str(classification.get("kind", "flat_grass")),
			"actual_coverage": float(classification.get("coverage", 0.0)),
			"actual_feature_ids": Array(classification.get("feature_ids", [])),
			"difference": "",
		}
		if not union_oracle_match:
			result["difference"] = "union oracle mismatch：expected=%s actual=%s tolerance=%s" % [expected_union_area, union_area, TERRAIN_STEP01_UNION_TOLERANCE]
			_check(false, "geometry %s union oracle mismatch expected=%s actual=%s" % [result["id"], expected_union_area, union_area])
		elif actual_blocked != expected_blocked:
			result["difference"] = "正面積交集被 3.5% per-polygon 門檻略過" if expected_blocked else "零面積案例意外被標示為障礙"
			_check(false, "geometry %s blocked mismatch expected=%s actual=%s" % [result["id"], expected_blocked, actual_blocked])
		elif expected.has("winning_coverage") and not is_equal_approx(float(expected["winning_coverage"]), float(classification.get("coverage", 0.0))):
			result["difference"] = "同 kind 重疊面積被逐 polygon 相加，未採 union"
			_check(false, "geometry %s overlap coverage expected=%s actual=%s" % [result["id"], expected["winning_coverage"], classification.get("coverage", 0.0)])
		elif expected.has("winning_kind") and str(expected["winning_kind"]) != str(classification.get("kind", "")):
			result["difference"] = "mixed-kind winner 與目前結果不同"
			_check(false, "geometry %s winner mismatch" % result["id"])
		else:
			result["difference"] = "一致"
		geometry_results.append(result)
	_write_terrain_step01_artifacts(fixture, sample_results, geometry_results)


func _load_terrain_step01_fixture() -> Dictionary:
	var fixture_path := OS.get_environment(TERRAIN_STEP01_FIXTURE_OVERRIDE_ENV)
	if fixture_path.is_empty():
		fixture_path = TERRAIN_STEP01_FIXTURE
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	if parsed is Dictionary:
		var fixture: Dictionary = parsed.duplicate(true)
		_apply_terrain_step01_negative_control(fixture)
		return fixture
	_check(false, "terrain step01 fixture is not a JSON object")
	return {}


func _apply_terrain_step01_negative_control(fixture: Dictionary) -> void:
	match OS.get_environment(TERRAIN_STEP01_NEGATIVE_CONTROL_ENV):
		"hash_mismatch":
			var hash_source: Dictionary = fixture.get("source", {})
			hash_source["sha256"] = "0000000000000000000000000000000000000000000000000000000000000000"
		"missing_asset":
			var missing_source: Dictionary = fixture.get("source", {})
			missing_source["asset"] = "res://assets/images/world/backgrounds/terrain-step01-missing.png"
		"union_oracle_mismatch":
			for geometry_variant: Variant in Array(fixture.get("geometry_cases", [])):
				var geometry_case: Dictionary = geometry_variant
				if str(geometry_case.get("id", "")) == "positive_1_percent":
					var expected: Dictionary = geometry_case.get("expected", {})
					expected["union_area"] = 101.0
					return


func _sample_label(sample: Dictionary) -> String:
	var labels := {
		"flat_tile36": "平地",
		"lake_tile12": "湖泊 witness",
		"riverbank_tile14": "河岸 witness",
		"hill_tile3": "山崖 witness",
		"trees_edge_tile59": "樹林邊緣 witness",
		"mixed_tree_cliff_tile2": "樹／崖混合 witness",
	}
	var grid: Array = sample.get("grid", [])
	return "格 %s（%s）" % [str(grid), str(labels.get(str(sample.get("id", "")), sample.get("id", "")))]


func _fixture_polygons(raw_polygons: Array) -> Array:
	var result: Array = []
	for raw_variant: Variant in raw_polygons:
		var raw: Dictionary = raw_variant
		var points := PackedVector2Array()
		for point_variant: Variant in Array(raw.get("points", [])):
			var point: Array = point_variant
			points.append(Vector2(float(point[0]), float(point[1])))
		result.append({
			"id": str(raw.get("id", "")),
			"kind": str(raw.get("kind", "")),
			"points": points,
		})
	return result


func _polygon_union_area(plot_rect: Rect2, polygons: Array) -> float:
	var disjoint_regions: Array = []
	var plot := PackedVector2Array([
		plot_rect.position,
		plot_rect.position + Vector2(plot_rect.size.x, 0.0),
		plot_rect.end,
		plot_rect.position + Vector2(0.0, plot_rect.size.y),
	])
	for polygon_variant: Variant in polygons:
		var polygon: Dictionary = polygon_variant
		var remaining: Array = []
		for intersection: PackedVector2Array in Geometry2D.intersect_polygons(
			plot, PackedVector2Array(polygon.get("points", PackedVector2Array()))
		):
			remaining.append(intersection)
		for existing_variant: Variant in disjoint_regions:
			var existing: PackedVector2Array = existing_variant
			var next_remaining: Array = []
			for candidate_variant: Variant in remaining:
				var candidate: PackedVector2Array = candidate_variant
				for clipped: PackedVector2Array in Geometry2D.clip_polygons(candidate, existing):
					next_remaining.append(clipped)
			remaining = next_remaining
		for fresh_variant: Variant in remaining:
			disjoint_regions.append(fresh_variant)
	var area := 0.0
	for region_variant: Variant in disjoint_regions:
		area += _polygon_area(region_variant)
	return area


func _polygon_area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var doubled_area := 0.0
	for point_index in points.size():
		var current := points[point_index]
		var next := points[(point_index + 1) % points.size()]
		doubled_area += current.x * next.y - next.x * current.y
	return absf(doubled_area) * 0.5


func _write_terrain_step01_artifacts(fixture: Dictionary, samples: Array, geometry: Array) -> void:
	var output_root := OS.get_environment(TERRAIN_STEP01_OUTPUT_ROOT_ENV)
	if output_root.is_empty():
		_check(false, "terrain step01 diagnostic output root is missing")
		return
	var verified_source := _verified_terrain_step01_source(fixture)
	if verified_source.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(output_root)
	var report := {
		"task_id": "terrain-step01",
		"status": "expected_failures_detected",
		"source": verified_source,
		"bitmap_observation_status": "assistant visual review pending human confirmation",
		"sample_results": samples,
		"geometry_results": geometry,
		"classifier_contract": "3.5% threshold, same-kind addition, maximum-kind winner preserved intentionally for step 01",
		"acceptance_limit": "Headless diagnostic only. It does not verify native GUI, physical input, NPC movement, or save behavior.",
	}
	_write_text_file(output_root.path_join("terrain-step01-diagnostic.json"), JSON.stringify(report, "\t") + "\n")
	_write_text_file(output_root.path_join("Review-Terrain.html"), _terrain_step01_html(report, fixture))


func _verified_terrain_step01_source(fixture: Dictionary) -> Dictionary:
	var source: Dictionary = Dictionary(fixture.get("source", {})).duplicate(true)
	var asset := str(source.get("asset", ""))
	var expected_hash := str(source.get("sha256", "")).to_lower()
	if asset.is_empty() or expected_hash.is_empty():
		_check(false, "terrain step01 source asset/hash metadata is missing")
		return {}
	var asset_path := ProjectSettings.globalize_path(asset)
	var asset_bytes := FileAccess.get_file_as_bytes(asset_path)
	if asset_bytes.is_empty():
		_check(false, "terrain step01 source PNG missing or empty: %s" % asset)
		return {}
	var actual_hash := _sha256_bytes(asset_bytes)
	if actual_hash != expected_hash:
		_check(false, "terrain step01 source PNG hash mismatch expected=%s actual=%s" % [expected_hash, actual_hash])
		return {}
	var tracked_hashes := {
		"classifier": _sha256_res_file("res://data/catalogs/city_terrain_layout.gd"),
		"test": _sha256_res_file("res://tests/ui/city_terrain_map_unit_test.gd"),
		"fixture": _sha256_res_file("res://tests/fixtures/terrain_step01_ground_truth.json"),
	}
	if str(tracked_hashes["classifier"]).is_empty() or str(tracked_hashes["test"]).is_empty() or str(tracked_hashes["fixture"]).is_empty():
		_check(false, "terrain step01 tracked source hash could not be read")
		return {}
	source["expected_sha256"] = expected_hash
	source["actual_sha256"] = actual_hash
	source["sha256_verified"] = true
	source["tracked_file_sha256"] = tracked_hashes
	return source


func _sha256_res_file(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path))
	if bytes.is_empty():
		return ""
	return _sha256_bytes(bytes)


func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode().to_lower()


func _write_text_file(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "cannot write terrain step01 artifact: %s" % path)
		return
	file.store_string(content)
	file.close()


func _terrain_step01_html(report: Dictionary, fixture: Dictionary) -> String:
	var source: Dictionary = report.get("source", {})
	var asset_path := ProjectSettings.globalize_path(str(source.get("asset", "")))
	var image_base64 := Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(asset_path))
	var grid_svg := _terrain_step01_grid_svg(source)
	var witness_svg := _terrain_step01_witness_svg(Array(fixture.get("samples", [])))
	var polygon_svg := _terrain_step01_polygon_svg()
	return """<!doctype html><html lang=\"zh-Hant\"><meta charset=\"utf-8\"><title>Review Terrain Step 01</title><style>body{font-family:system-ui,sans-serif;margin:20px;color:#17212b}svg{max-width:100%;border:1px solid #789}table{border-collapse:collapse;width:100%;margin:12px 0}th,td{border:1px solid #c8d1da;padding:6px;text-align:left}.warn{color:#9b2c2c}.ok{color:#17663a}.muted{color:#52616b}.polygons{display:none}.legend span{margin-right:14px}code{word-break:break-all}</style><h1>Terrain Step 01 對照</h1><p class=\"warn\">原圖樣本由助理依原圖目視判讀，待使用者人工核對；不是使用者已驗收。</p><p class=\"warn\">診斷完成，遊戲尚未修正。</p><p>預設顯示原 PNG、stage 格線與六個 witness。<label><input type=\"checkbox\" onchange=\"document.querySelector('.polygons').style.display=this.checked?'block':'none'\"> 顯示現有程式輪廓（待校正）</label></p><svg viewBox=\"0 0 1672 941\"><image href=\"data:image/png;base64,""" + image_base64 + "\" width=\"1672\" height=\"941\"/>" + grid_svg + witness_svg + polygon_svg + "</svg><p class=\"legend\"><span>藍：stage 格線</span><span>橘：witness</span><span>紅虛線：現有程式 polygon，預設關閉</span></p><h2>六格樣本與目前結果</h2>" + _terrain_step01_table(Array(report.get("sample_results", [])), ["label", "expected_obstacle_kinds", "actual_kind", "actual_feature_ids", "buildable", "walkable", "navigation_blocker", "difference"]) + "<h2>解析幾何診斷</h2><p>union 面積是獨立計算；它不把同 kind 個別 polygon 相加。任何正面積交集的 expected blocked=true；僅邊接觸 expected blocked=false。</p>" + _terrain_step01_table(Array(report.get("geometry_results", [])), ["id", "expected_blocked", "actual_blocked", "expected_union_area", "actual_union_area", "union_oracle_match", "actual_kind", "actual_coverage", "difference"]) + "<h2>來源與限制</h2><p>PNG SHA-256（fixture expected／實際 verified）：<code>" + _html_escape(str(source.get("expected_sha256", ""))) + " / " + _html_escape(str(source.get("actual_sha256", ""))) + "</code></p><p>六個原圖 witness 與八個解析幾何案例只覆蓋此診斷範圍；不代表全圖或 NPC 實際行走。</p><p>" + _html_escape(str(report.get("classifier_contract", ""))) + "</p><p class=\"muted\">" + _html_escape(str(report.get("acceptance_limit", ""))) + "</p></html>"


func _terrain_step01_grid_svg(source: Dictionary) -> String:
	var grid: Dictionary = source.get("grid", {})
	var origin: Array = grid.get("origin", [])
	var cell := float(grid.get("cell_size", 70))
	var columns := int(grid.get("columns", 10))
	var rows := int(grid.get("rows", 10))
	var transform := "translate(193.376334 0) scale(1.147561)"
	var lines := "<g stroke=\"#1268c4\" stroke-width=\"1.5\" fill=\"none\" transform=\"%s\">" % transform
	for column in range(columns + 1):
		lines += "<path d=\"M %f %f V %f\"/>" % [float(origin[0]) + column * cell, float(origin[1]), float(origin[1]) + rows * cell]
	for row in range(rows + 1):
		lines += "<path d=\"M %f %f H %f\"/>" % [float(origin[0]), float(origin[1]) + row * cell, float(origin[0]) + columns * cell]
	return lines + "</g>"


func _terrain_step01_witness_svg(samples: Array) -> String:
	var svg := "<g fill=\"#ef8b21\" stroke=\"#5a2b00\" stroke-width=\"2\">"
	for sample_variant: Variant in samples:
		var sample: Dictionary = sample_variant
		for witness_variant: Variant in Array(sample.get("witnesses", [])):
			var witness: Array = witness_variant
			svg += "<circle cx=\"%s\" cy=\"%s\" r=\"8\"><title>%s</title></circle>" % [witness[0], witness[1], _html_escape(str(sample.get("id", "")))]
	return svg + "</g>"


func _terrain_step01_polygon_svg() -> String:
	var svg := "<g class=\"polygons\" transform=\"translate(193.376334 0) scale(1.147561)\" fill=\"none\" stroke=\"#c62828\" stroke-width=\"2\" stroke-dasharray=\"8 5\">"
	for polygon_data: Dictionary in CityBackdropTerrainCatalog.static_polygons():
		var points := PackedVector2Array(polygon_data.get("points", PackedVector2Array()))
		var point_text := ""
		for point: Vector2 in points:
			point_text += "%f,%f " % [point.x, point.y]
		svg += "<polygon points=\"%s\"><title>%s</title></polygon>" % [point_text, _html_escape(str(polygon_data.get("id", "")))]
	return svg + "</g>"


func _terrain_step01_table(rows: Array, fields: Array) -> String:
	var html := "<table><thead><tr>"
	for field_variant: Variant in fields:
		html += "<th>%s</th>" % _html_escape(_terrain_step01_field_label(str(field_variant)))
	html += "</tr></thead><tbody>"
	for row_variant: Variant in rows:
		var row: Dictionary = row_variant
		html += "<tr>"
		for field_variant: Variant in fields:
			var value: Variant = row.get(str(field_variant), "")
			html += "<td>%s</td>" % _html_escape(JSON.stringify(value) if value is Array or value is Dictionary else str(value))
		html += "</tr>"
	return html + "</tbody></table>"


func _terrain_step01_field_label(field: String) -> String:
	var labels := {
		"label": "樣本",
		"id": "案例",
		"expected_obstacle_kinds": "預期障礙",
		"actual_kind": "目前種類",
		"actual_feature_ids": "目前 feature IDs",
		"buildable": "可建築",
		"walkable": "可步行",
		"navigation_blocker": "有無阻擋",
		"expected_blocked": "預期阻擋",
		"actual_blocked": "目前阻擋",
		"expected_union_area": "預期 union 面積",
		"actual_union_area": "實際 union 面積",
		"union_oracle_match": "union oracle 一致",
		"actual_coverage": "目前 coverage",
		"difference": "差異",
	}
	return str(labels.get(field, field))


func _html_escape(value: String) -> String:
	return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
