class_name MunicipalEconomyService
extends RefCounted

## Pure municipal-economy calculations shared by the application shell.
##
## This service deliberately does not mutate population or UI state.  The main
## controller keeps ownership of orchestration while these deterministic rules
## remain independently testable.


static func resident_income_tax_base(resident_income_total: int, treasury_scale: float) -> float:
	return float(maxi(0, resident_income_total)) * maxf(0.0, treasury_scale)


static func build_open_jobs(
	building_source: Variant,
	buildings: Dictionary,
	cell_count: int,
	law_job_attraction: float
) -> Array[Dictionary]:
	var open_jobs: Array[Dictionary] = []
	for entry: Dictionary in _active_building_entries(building_source, cell_count):
		var building_name := str(entry.get("building_name", ""))
		if building_name.is_empty() or not buildings.has(building_name):
			continue
		var definition_variant: Variant = buildings[building_name]
		if not definition_variant is Dictionary:
			continue
		var definition: Dictionary = definition_variant
		var slots := maxi(0, int(definition.get("job_capacity", definition.get("job_attraction", 0))))
		if slots <= 0:
			continue
		open_jobs.append({
			# Building jobs use their own namespace. Legacy seeded residents have
			# generic IDs such as `商業_019`, so those IDs cannot consume a new
			# building's declared capacity before it has offered a job.
			"job_id": "building:%s:%s" % [str(entry.get("building_id", "unknown")), job_sector_for_building(building_name, buildings)],
			"slots": slots,
			# Availability is authoritative, but salary remains unknown until an
			# explicit wage-setting command supplies one.
			"salary": -1,
		})
	var law_slots := maxi(0, int(round(law_job_attraction)))
	if law_slots > 0:
		open_jobs.append({"job_id": "policy:public_service", "slots": law_slots, "salary": -1})
	return open_jobs


static func _active_building_entries(building_source: Variant, cell_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if building_source is Dictionary:
		var records: Dictionary = building_source
		var record_ids: Array = records.keys()
		record_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		for record_id_variant: Variant in record_ids:
			var record_value: Variant = records[record_id_variant]
			if not record_value is Dictionary:
				continue
			var record: Dictionary = record_value
			if str(record.get("status", "active")) == "scrapped":
				continue
			var building_name := str(record.get("building_name", ""))
			if building_name.is_empty():
				continue
			result.append({
				"building_id": str(record.get("building_id", record_id_variant)),
				"building_name": building_name,
			})
		return result
	if building_source is Array:
		var city_grid: Array = building_source
		var inspected_cells := mini(maxi(0, cell_count), city_grid.size())
		for tile_index: int in inspected_cells:
			var building_name := str(city_grid[tile_index])
			if not building_name.is_empty():
				result.append({
					"building_id": "%03d" % tile_index,
					"building_name": building_name,
				})
	return result


static func job_sector_for_building(building_name: String, buildings: Dictionary) -> String:
	var definition_variant: Variant = buildings.get(building_name, {})
	var definition: Dictionary = definition_variant if definition_variant is Dictionary else {}
	var category := str(definition.get("category", "服務類"))
	if "商業" in category:
		return "商業"
	if "產業" in category or "工業" in category:
		return "工業"
	if "公共" in category or "政府" in category:
		return "公共服務"
	return "服務業"
